package cn.pawday.storage;

import cn.pawday.common.Api.Failure;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Bounded ISO BMFF/H.264 envelope validation. Does not execute a codec or trust the filename. */
final class VideoContentValidator {
 private VideoContentValidator(){}
 private record Box(String type,int start,int end){}
 private static Failure invalid(){return new Failure(400,"UPLOAD_INVALID_VIDEO");}
 private static long u32(byte[] data,int offset){if(offset<0||offset+4>data.length)throw invalid();return Integer.toUnsignedLong(ByteBuffer.wrap(data,offset,4).getInt());}
 private static String ascii(byte[] data,int offset){if(offset<0||offset+4>data.length)throw invalid();return new String(data,offset,4,StandardCharsets.US_ASCII);}
 private static List<Box> boxes(byte[] data,int start,int end){var result=new ArrayList<Box>();while(start<end){if(end-start<8||result.size()>=10000)throw invalid();long size=u32(data,start);String type=ascii(data,start+4);int header=8;if(size==1){if(end-start<16)throw invalid();size=ByteBuffer.wrap(data,start+8,8).getLong();header=16;}else if(size==0)size=end-start;if(size<header||size>end-start)throw invalid();int next=start+(int)size;result.add(new Box(type,start+header,next));start=next;}return result;}
 private static Box find(List<Box> boxes,String type){return boxes.stream().filter(b->b.type().equals(type)).findFirst().orElseThrow(VideoContentValidator::invalid);}
 static void validate(Path path)throws java.io.IOException{
  long size=Files.size(path);if(size<64||size>5242880)throw invalid();byte[] data=Files.readAllBytes(path);var root=boxes(data,0,data.length);
  Box ftyp=find(root,"ftyp");if(!root.getFirst().type().equals("ftyp")||ftyp.end()-ftyp.start()<8||!Set.of("isom","iso2","mp41","mp42","avc1").contains(ascii(data,ftyp.start())))throw invalid();
  Box mdat=find(root,"mdat"),moov=find(root,"moov");if(mdat.end()-mdat.start()<1)throw invalid();var children=boxes(data,moov.start(),moov.end());Box mvhd=find(children,"mvhd");if(mvhd.end()-mvhd.start()<24)throw invalid();int version=data[mvhd.start()]&255;long scale,duration;if(version==0){scale=u32(data,mvhd.start()+12);duration=u32(data,mvhd.start()+16);}else if(version==1&&mvhd.end()-mvhd.start()>=36){scale=u32(data,mvhd.start()+20);duration=ByteBuffer.wrap(data,mvhd.start()+24,8).getLong();}else throw invalid();if(scale<1||duration<1||duration>scale*120L)throw new Failure(400,"UPLOAD_VIDEO_DURATION");
  boolean video=false;
  for(Box trak:children.stream().filter(b->b.type().equals("trak")).toList()){
   Box mdia=find(boxes(data,trak.start(),trak.end()),"mdia");var mdias=boxes(data,mdia.start(),mdia.end());Box hdlr=find(mdias,"hdlr");if(hdlr.end()-hdlr.start()<12)throw invalid();String handler=ascii(data,hdlr.start()+8);if(!Set.of("vide","soun").contains(handler))throw invalid();Box minf=find(mdias,"minf");var minfs=boxes(data,minf.start(),minf.end());
   Box dinf=find(minfs,"dinf"),dref=find(boxes(data,dinf.start(),dinf.end()),"dref");if(dref.end()-dref.start()<8)throw invalid();var refs=boxes(data,dref.start()+8,dref.end());if(refs.isEmpty()||u32(data,dref.start()+4)!=refs.size())throw invalid();for(Box ref:refs)if(!ref.type().equals("url ")||ref.end()-ref.start()!=4||u32(data,ref.start())!=1)throw invalid();
   if(handler.equals("vide")){
    Box stbl=find(minfs,"stbl"),stsd=find(boxes(data,stbl.start(),stbl.end()),"stsd");if(stsd.end()-stsd.start()<8)throw invalid();var entries=boxes(data,stsd.start()+8,stsd.end());if(entries.size()!=1||u32(data,stsd.start()+4)!=1)throw invalid();Box entry=entries.getFirst();if(!Set.of("avc1","avc3").contains(entry.type())||entry.end()-entry.start()<78)throw new Failure(400,"UPLOAD_VIDEO_CODEC");int width=Short.toUnsignedInt(ByteBuffer.wrap(data,entry.start()+24,2).getShort()),height=Short.toUnsignedInt(ByteBuffer.wrap(data,entry.start()+26,2).getShort());if(width<1||height<1||width>3840||height>3840)throw new Failure(400,"UPLOAD_VIDEO_DIMENSIONS");Box avcc=find(boxes(data,entry.start()+78,entry.end()),"avcC");if(avcc.end()-avcc.start()<7||data[avcc.start()]!=1)throw invalid();video=true;
   }
  }
  if(!video)throw invalid();
 }
}
