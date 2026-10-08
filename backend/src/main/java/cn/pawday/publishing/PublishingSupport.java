package cn.pawday.publishing;

import cn.pawday.common.Api;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.storage.ObjectStorageProvider;
import java.sql.Timestamp;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

/** Shared publishing primitives; business visibility and ownership are checked by each domain. */
@Component
public class PublishingSupport {
 public final JdbcTemplate db;
 public final JsonMapper json=JsonMapper.builder().build();
 private final ObjectStorageProvider provider;
 public PublishingSupport(JdbcTemplate db,ObjectStorageProvider provider){this.db=db;this.provider=provider;}
 public Map<String,Object> one(String sql,Object...args){var rows=db.queryForList(sql,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 public static long number(Object value){return ((Number)value).longValue();}
 public static UUID id(Object raw){try{if(!(raw instanceof String s))throw new IllegalArgumentException();UUID id=UUID.fromString(s);if(!id.toString().equalsIgnoreCase(s))throw new IllegalArgumentException();return id;}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 public static String text(Object raw,int max){if(!(raw instanceof String s)||s.isBlank()||s.length()>max)throw new Failure(400,"VALIDATION_ERROR");return s;}
 public static boolean bool(Object raw){if(!(raw instanceof Boolean b))throw new Failure(400,"VALIDATION_ERROR");return b;}
 public static int integer(Object raw,int min,int max){if(!(raw instanceof Number n)||n.longValue()<min||n.longValue()>max||n.doubleValue()!=n.longValue())throw new Failure(400,"VALIDATION_ERROR");return n.intValue();}
 public static void fields(Map<String,Object>b,String...keys){if(!b.keySet().equals(Set.of(keys)))throw new Failure(400,"VALIDATION_ERROR");}
 public static long version(String raw){if(raw==null||!raw.matches("\"[0-9]{1,13}\""))throw new Failure(400,"IF_MATCH_REQUIRED");long n=Long.parseLong(raw.substring(1,raw.length()-1));if(n>9007199254741L)throw new Failure(400,"VALIDATION_ERROR");return n;}
 public static void sameVersion(Map<String,Object> row,long expected){if(number(row.get("version"))!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");}
 public static void permission(Actor actor,Actor.Realm realm,String code){if(actor.realm()!=realm||!actor.permissions().contains(code))throw new Failure(403,"PERMISSION_DENIED");}
 public static List<UUID> ids(Object raw,int max){if(!(raw instanceof List<?> items)||items.size()>max)throw new Failure(400,"VALIDATION_ERROR");var ids=items.stream().map(PublishingSupport::id).toList();if(new HashSet<>(ids).size()!=ids.size())throw new Failure(400,"VALIDATION_ERROR");return ids;}
 public List<UUID> storedIds(Object raw){return json.readValue(raw.toString(),List.class).stream().map(x->UUID.fromString(x.toString())).toList();}
 public Map<String,Object> view(Map<String,Object> row){var result=new LinkedHashMap<String,Object>();row.forEach((k,v)->result.put(k,v instanceof Timestamp t?t.toInstant().toString():v));return result;}
 public void bindMedia(Actor actor,String scope,UUID revision,List<UUID> assets){
  // SHARE locks serialize attachment against deletion; stable ordering avoids multi-resource deadlocks.
  for(UUID id:assets.stream().sorted().toList()){
   var media=one("SELECT * FROM media_asset WHERE id=? FOR SHARE",id);
   if(!actor.principalId().equals(media.get("owner_id"))||!actor.realm().name().equals(media.get("realm"))||!scope.equals(media.get("scope")))throw new Failure(404,"RESOURCE_NOT_FOUND");
   if(!"READY".equals(media.get("status")))throw new Failure(409,"MEDIA_NOT_READY");
   if(!Set.of("image/png","image/jpeg","video/mp4").contains(media.get("mime"))||scope.equals("ARTICLE")&&media.get("mime").equals("video/mp4"))throw new Failure(400,"UPLOAD_MIME_NOT_ALLOWED");
   db.update("INSERT INTO media_asset_usage(asset_id,kind,revision_id) VALUES (?,?,?)",id,scope,revision);
  }
 }
 public List<Map<String,Object>> media(Object stored,String path){return storedIds(stored).stream().map(id->{var row=one("SELECT id,mime,size_bytes,status FROM media_asset WHERE id=?",id);return Map.<String,Object>of("asset_id",id,"mime",row.get("mime"),"size_bytes",row.get("size_bytes"),"available",row.get("status").equals("READY"),"content_url",path+id);}).toList();}
 public record Content(String mime,long size,java.io.InputStream stream){}
 public Content content(Object stored,UUID id){if(!storedIds(stored).contains(id))throw new Failure(404,"RESOURCE_NOT_FOUND");var row=one("SELECT * FROM media_asset WHERE id=?",id);if(!"READY".equals(row.get("status")))throw new Failure(404,"RESOURCE_NOT_FOUND");if(!provider.providerId().equals(row.get("storage_provider")))throw new Failure(503,"OBJECT_PROVIDER_UNAVAILABLE");return new Content(row.get("mime").toString(),number(row.get("size_bytes")),provider.read(row.get("object_key").toString()));}
 public static UUID cursor(String raw){return raw==null?new UUID(0,0):id(raw);}
 public static void limit(int n){if(n<1||n>100)throw new Failure(400,"VALIDATION_ERROR");}
 public static Object paged(List<Map<String,Object>> rows,int limit,HttpServletRequest r){boolean more=rows.size()>limit;var data=more?rows.subList(0,limit):rows;return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}
}
