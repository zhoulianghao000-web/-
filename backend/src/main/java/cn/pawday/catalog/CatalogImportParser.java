package cn.pawday.catalog;

import cn.pawday.common.Api.Failure;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.*;
import tools.jackson.databind.json.JsonMapper;

/** Bounded two-column CSV/XLSX adapter. No formulas, external links or arbitrary ZIP paths. */
public final class CatalogImportParser {
 private CatalogImportParser(){}
 static final int MAX_BYTES=2_000_000,MAX_EXPANDED=8_000_000,MAX_ROWS=200;
 static Failure invalid(){return new Failure(400,"INVALID_IMPORT_FILE");}
 public static List<Map<String,Object>> parse(String format,String encoded){
  try{byte[] raw=Base64.getDecoder().decode(encoded);if(raw.length==0||raw.length>MAX_BYTES)throw invalid();List<List<String>> cells=switch(format){case "CSV"->csv(new String(raw,StandardCharsets.UTF_8));case "XLSX"->xlsx(raw);default->throw invalid();};if(cells.size()<2||cells.size()>MAX_ROWS+1||!cells.getFirst().equals(List.of("sku_code","standard_json")))throw invalid();var json=JsonMapper.builder().build();List<Map<String,Object>> rows=new ArrayList<>();for(var row:cells.subList(1,cells.size())){if(row.size()!=2||row.get(0).isBlank()||row.get(1).length()>100000)throw invalid();Object standard;try{standard=json.readValue(row.get(1),Map.class);}catch(Exception bad){standard=Map.of("invalid_json",true);}rows.add(Map.of("sku_code",row.get(0).trim(),"standard",standard));}return rows;}catch(Failure f){throw f;}catch(Exception e){throw invalid();}
 }
 static List<List<String>> csv(String raw){String s=raw.startsWith("\ufeff")?raw.substring(1):raw;List<List<String>> rows=new ArrayList<>();List<String> row=new ArrayList<>();StringBuilder cell=new StringBuilder();boolean quoted=false,closed=false;for(int i=0;i<s.length();i++){char c=s.charAt(i);if(quoted){if(c=='"'){if(i+1<s.length()&&s.charAt(i+1)=='"'){cell.append('"');i++;}else{quoted=false;closed=true;}}else cell.append(c);}else if(c=='"'){if(cell.length()!=0||closed)throw invalid();quoted=true;}else if(c==','||c=='\n'||c=='\r'){row.add(cell.toString());cell.setLength(0);closed=false;if(c!=','){if(c=='\r'&&i+1<s.length()&&s.charAt(i+1)=='\n')i++;rows.add(row);row=new ArrayList<>();if(rows.size()>MAX_ROWS+1)throw invalid();}}else{if(closed)throw invalid();cell.append(c);}if(cell.length()>100000)throw invalid();}if(quoted)throw invalid();if(cell.length()>0||closed||!row.isEmpty()){row.add(cell.toString());rows.add(row);}return rows;}
 static Document xml(byte[] bytes) throws Exception {var factory=DocumentBuilderFactory.newInstance();factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);factory.setFeature("http://xml.org/sax/features/external-general-entities",false);factory.setFeature("http://xml.org/sax/features/external-parameter-entities",false);factory.setXIncludeAware(false);factory.setExpandEntityReferences(false);factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD,"");factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA,"");return factory.newDocumentBuilder().parse(new ByteArrayInputStream(bytes));}
 static List<List<String>> xlsx(byte[] raw) throws Exception {
  Map<String,byte[]> zip=new HashMap<>();int total=0,count=0;try(var input=new ZipInputStream(new ByteArrayInputStream(raw))){ZipEntry entry;while((entry=input.getNextEntry())!=null){if(++count>100||entry.getName().contains("..")||entry.getName().startsWith("/")||entry.getName().contains("externalLinks")||entry.getName().endsWith("vbaProject.bin"))throw invalid();var bytes=input.readNBytes(MAX_EXPANDED-total+1);total+=bytes.length;if(total>MAX_EXPANDED||zip.put(entry.getName(),bytes)!=null)throw invalid();}}
  // Explicit single-sheet template avoids silently importing the wrong sheet.
  if(!zip.containsKey("xl/worksheets/sheet1.xml")||zip.keySet().stream().filter(x->x.startsWith("xl/worksheets/")&&x.endsWith(".xml")).count()!=1)throw invalid();
  List<String> shared=new ArrayList<>();if(zip.containsKey("xl/sharedStrings.xml")){var nodes=xml(zip.get("xl/sharedStrings.xml")).getElementsByTagName("si");for(int i=0;i<nodes.getLength();i++)shared.add(nodes.item(i).getTextContent());}
  var sheet=xml(zip.get("xl/worksheets/sheet1.xml"));if(sheet.getElementsByTagName("f").getLength()!=0)throw invalid();var nodes=sheet.getElementsByTagName("row");if(nodes.getLength()>MAX_ROWS+1)throw invalid();List<List<String>> rows=new ArrayList<>();for(int i=0;i<nodes.getLength();i++){var cells=((Element)nodes.item(i)).getElementsByTagName("c");String[] values={"",""};Set<Integer> columns=new HashSet<>();for(int j=0;j<cells.getLength();j++){var cell=(Element)cells.item(j);String ref=cell.getAttribute("r");if(!ref.matches("[AB][1-9][0-9]*"))throw invalid();int index=ref.charAt(0)-'A';if(!columns.add(index))throw invalid();String type=cell.getAttribute("t"),value;if(type.equals("inlineStr"))value=cell.getElementsByTagName("is").item(0).getTextContent();else{var v=cell.getElementsByTagName("v");value=v.getLength()==0?"":v.item(0).getTextContent();if(type.equals("s"))value=shared.get(Integer.parseInt(value));else if(!type.equals("str")&&!type.isEmpty())throw invalid();}values[index]=value;}rows.add(List.of(values));}return rows;
 }
}
