package cn.pawday.pet;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Date;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Service
public class PetService {
 private final JdbcTemplate db; private final TransactionTemplate tx; private final AuditWriter audit;
 private final Crypto crypto; private final Clock clock; private final JsonMapper json=JsonMapper.builder().build();
 private static final Set<String> FIELDS=Set.of("name","species_id","breed_id","birth_date","age_estimate_months","sex","neutered_status","allergens","avoidance_notes");
 public PetService(JdbcTemplate db,TransactionTemplate tx,AuditWriter audit,Crypto crypto,Clock clock){this.db=db;this.tx=tx;this.audit=audit;this.crypto=crypto;this.clock=clock;}
 static void check(boolean valid){if(!valid)throw new Failure(400,"VALIDATION_ERROR");}
 public static String text(Object value,int max){check(value instanceof String && !((String)value).isBlank() && ((String)value).length()<=max);return ((String)value).trim();}
 public static UUID uuid(Object value){try{return UUID.fromString(String.valueOf(value));}catch(Exception ex){throw new Failure(400,"VALIDATION_ERROR");}}
 public static long number(Object value,long min,long max){check(value instanceof Integer || value instanceof Long);long n=((Number)value).longValue();check(n>=min&&n<=max);return n;}
 static String choice(Object value,String... allowed){String v=text(value,32);check(Arrays.asList(allowed).contains(v));return v;}
 private LocalDate today(){return LocalDate.now(clock.withZone(ZoneId.of("Asia/Shanghai")));}
 private LocalDate date(Object raw){try{LocalDate d=LocalDate.parse(String.valueOf(raw));check(!d.isAfter(today())&&d.getYear()>=1900);return d;}catch(Failure f){throw f;}catch(Exception ex){throw new Failure(400,"VALIDATION_ERROR");}}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER||a.userId()==null)throw new Failure(403,"PERMISSION_DENIED");}
 public Map<String,Object> command(Actor actor,String action,String key,Object payload,Supplier<Map<String,Object>> work){
  if(key==null||key.length()<16||key.length()>128)throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");
  String hash=crypto.hash(json.writeValueAsString(canonical(payload)));
  return tx.execute(s->{
   db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.principalId()+":"+action+":"+key);
   var prior=db.queryForList("SELECT payload_hash,result_json FROM identity_command WHERE principal_id=? AND action=? AND idempotency_key=?",actor.principalId(),action,key);
   if(!prior.isEmpty()){if(!hash.equals(prior.getFirst().get("payload_hash")))throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");return json.readValue(prior.getFirst().get("result_json").toString(),Map.class);}
   var result=work.get();db.update("INSERT INTO identity_command(principal_id,action,idempotency_key,payload_hash,result_json) VALUES (?,?,?,?,?::jsonb)",actor.principalId(),action,key,hash,json.writeValueAsString(result));return result;
  });
 }
 private Object canonical(Object value){if(value instanceof Map<?,?> map){Map<String,Object> sorted=new TreeMap<>();map.forEach((k,v)->sorted.put(k.toString(),canonical(v)));return sorted;}if(value instanceof List<?> values)return values.stream().map(this::canonical).toList();return value;}
 public record ResultPage(List<Map<String,Object>> data,String nextCursor,boolean hasMore) {}
 public ResultPage list(Actor a,String cursor,int limit){consumer(a);check(limit>=1&&limit<=100);UUID after=cursor==null?new UUID(0,0):uuid(cursor);return tx.execute(s->{var rows=db.queryForList("SELECT id FROM pets WHERE owner_user_id=? AND status='ACTIVE' AND id>? ORDER BY id LIMIT ?",a.userId(),after,limit+1);boolean more=rows.size()>limit;var data=rows.stream().limit(limit).map(row->get(a,(UUID)row.get("id"))).toList();return new ResultPage(data,more?data.getLast().get("id").toString():null,more);});}
 private Map<String,Object> owned(Actor a,UUID id){consumer(a);var rows=db.queryForList("SELECT * FROM pets WHERE id=? AND owner_user_id=? AND status='ACTIVE' FOR UPDATE",id,a.userId());if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 public Map<String,Object> get(Actor a,UUID id){return tx.execute(s->view(owned(a,id)));}
 private Map<String,Object> view(Map<String,Object> row){
  Map<String,Object> out=new LinkedHashMap<>();for(String f:List.of("id","name","species_id","breed_id","sex","neutered_status","version","age_estimate_months"))out.put(f,row.get(f));
  out.put("birth_date",row.get("birth_date")==null?null:row.get("birth_date").toString());out.put("avoidance_notes",json.readValue(row.get("avoidance_notes").toString(),List.class));
  out.put("allergens",db.query("SELECT allergen_id,status,source,note FROM pet_allergens WHERE pet_id=? ORDER BY allergen_id",(r,i)->{Map<String,Object> item=new LinkedHashMap<>();item.put("allergen_id",r.getObject(1));item.put("status",r.getString(2));item.put("source",r.getString(3));if(r.getString(4)!=null)item.put("note",r.getString(4));return item;},row.get("id")));
  var stages=db.queryForList("SELECT d.* FROM pet_life_stage_definitions d JOIN pet_life_stage_rule_versions v ON v.id=d.rule_version_id WHERE v.species_id=? AND v.status='PUBLISHED' ORDER BY d.is_unknown,d.stage_code",row.get("species_id"));
  Object stageId=null;boolean unknown=true;
  for(var stage:stages){if(Boolean.TRUE.equals(stage.get("is_unknown"))){if(unknown)stageId=stage.get("id");continue;}
   // Estimated months cannot establish a trustworthy boundary; exact birthday uses calendar units.
   if(row.get("birth_date")==null)continue;LocalDate birth=((Date)row.get("birth_date")).toLocalDate();
   long age=switch(stage.get("age_unit").toString()){case "DAY"->ChronoUnit.DAYS.between(birth,today());case "MONTH"->ChronoUnit.MONTHS.between(birth,today());default->ChronoUnit.YEARS.between(birth,today());};
   long min=((Number)stage.get("min_age_value")).longValue();Object max=stage.get("max_age_value");if(age>=min&&(max==null||age<((Number)max).longValue())){stageId=stage.get("id");unknown=false;}
  }
  out.put("life_stage_id",stageId);out.put("life_stage_unknown",unknown);return out;
 }
 private Map<String,Object> validate(Map<String,Object> b,Map<String,Object> before){
  check(b.keySet().equals(FIELDS)||FIELDS.containsAll(b.keySet()));for(String f:List.of("name","species_id","sex","neutered_status","allergens","avoidance_notes"))check(b.containsKey(f)&&b.get(f)!=null);
  Map<String,Object> v=new LinkedHashMap<>(b);v.put("name",text(b.get("name"),160));UUID species=uuid(b.get("species_id"));v.put("species_id",species);
  if(!species.toString().equals(String.valueOf(before.get("species_id")))&&db.queryForObject("SELECT count(*) FROM pet_species s WHERE s.id=? AND s.status='ACTIVE' AND NOT EXISTS(SELECT 1 FROM pet_species p WHERE p.id=s.parent_id AND p.status<>'ACTIVE')",Integer.class,species)==0)throw new Failure(422,"SPECIES_UNAVAILABLE");
  UUID breed=b.get("breed_id")==null?null:uuid(b.get("breed_id"));v.put("breed_id",breed);
  boolean sameBreed=breed!=null&&breed.toString().equals(String.valueOf(before.get("breed_id")))&&species.toString().equals(String.valueOf(before.get("species_id")));
  if(breed!=null&&!sameBreed&&db.queryForObject("SELECT count(*) FROM pet_breeds WHERE id=? AND species_id=? AND status='ACTIVE'",Integer.class,breed,species)==0)throw new Failure(422,"BREED_SPECIES_MISMATCH");
  v.put("birth_date",b.get("birth_date")==null?null:date(b.get("birth_date")));v.put("age_estimate_months",b.get("age_estimate_months")==null?null:number(b.get("age_estimate_months"),0,2400));check(v.get("birth_date")==null||v.get("age_estimate_months")==null);
  v.put("sex",choice(b.get("sex"),"MALE","FEMALE","UNKNOWN"));v.put("neutered_status",choice(b.get("neutered_status"),"YES","NO","UNKNOWN"));
  check(b.get("avoidance_notes") instanceof List<?>);var notes=(List<?>)b.get("avoidance_notes");check(notes.size()<=50);notes.forEach(n->text(n,2000));
  check(b.get("allergens") instanceof List<?>);var entries=(List<?>)b.get("allergens");check(entries.size()<=100);Set<UUID> ids=new HashSet<>();
  for(Object raw:entries){check(raw instanceof Map<?,?>);var item=(Map<?,?>)raw;check(Set.of("allergen_id","status","source","note").containsAll(item.keySet()));UUID id=uuid(item.get("allergen_id"));check(ids.add(id));choice(item.get("status"),"YES","NO","UNKNOWN");choice(item.get("source"),"OWNER_OBSERVATION","VET_DIAGNOSIS");if(item.containsKey("note"))text(item.get("note"),2000);boolean existed=before.get("allergens") instanceof List<?> previous&&previous.stream().anyMatch(old->id.toString().equals(String.valueOf(((Map<?,?>)old).get("allergen_id"))));if(!existed&&db.queryForObject("SELECT count(*) FROM allergens WHERE id=? AND status='ACTIVE'",Integer.class,id)==0)throw new Failure(422,"ALLERGEN_UNAVAILABLE");}
  return v;
 }
 public Map<String,Object> save(Actor a,UUID id,Long expected,Map<String,Object> body,String key,HttpServletRequest r){
  consumer(a);check(!body.isEmpty()&&FIELDS.containsAll(body.keySet()));
  return command(a,id==null?"pet.create":"pet.update:"+id,key,Arrays.asList(expected,body),()->{
   Map<String,Object> before=id==null?Map.of():view(owned(a,id));if(id!=null&& !Objects.equals(((Number)before.get("version")).longValue(),expected))throw new Failure(409,"CONCURRENT_MODIFICATION");
   Map<String,Object> merged=new LinkedHashMap<>();for(String f:FIELDS)if(before.containsKey(f))merged.put(f,before.get(f));merged.putAll(body);var v=validate(merged,before);UUID petId=id==null?UUID.randomUUID():id;
   if(id==null)db.update("INSERT INTO pets(id,owner_user_id,name,species_id,breed_id,birth_date,age_estimate_months,sex,neutered_status,avoidance_notes) VALUES (?,?,?,?,?,?,?,?,?,?::jsonb)",petId,a.userId(),v.get("name"),v.get("species_id"),v.get("breed_id"),v.get("birth_date"),v.get("age_estimate_months"),v.get("sex"),v.get("neutered_status"),json.writeValueAsString(v.get("avoidance_notes")));
   else db.update("UPDATE pets SET name=?,species_id=?,breed_id=?,birth_date=?,age_estimate_months=?,sex=?,neutered_status=?,avoidance_notes=?::jsonb,version=version+1 WHERE id=?",v.get("name"),v.get("species_id"),v.get("breed_id"),v.get("birth_date"),v.get("age_estimate_months"),v.get("sex"),v.get("neutered_status"),json.writeValueAsString(v.get("avoidance_notes")),petId);
   db.update("DELETE FROM pet_allergens WHERE pet_id=?",petId);for(Object raw:(List<?>)v.get("allergens")){var item=(Map<?,?>)raw;db.update("INSERT INTO pet_allergens(pet_id,allergen_id,status,source,note) VALUES (?,?,?,?,?)",petId,uuid(item.get("allergen_id")),item.get("status"),item.get("source"),item.get("note"));}
   audit.write(a,id==null?"pet.create":"pet.update","PET",petId.toString(),id==null?Map.of():Map.of("version",expected),Map.of("version",id==null?0:expected+1),r);return view(owned(a,petId));
  });
 }
 public Map<String,Object> delete(Actor a,UUID id,long expected,String key,HttpServletRequest r){consumer(a);return command(a,"pet.delete:"+id,key,expected,()->{var row=owned(a,id);if(((Number)row.get("version")).longValue()!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");db.update("UPDATE pets SET status='DELETED',version=version+1 WHERE id=?",id);audit.write(a,"pet.delete","PET",id.toString(),Map.of("version",expected),Map.of("status","DELETED","version",expected+1),r);return Map.of("id",id,"version",expected+1,"status","DELETED");});}
 public ResultPage weights(Actor a,UUID id,String cursor,int limit){check(limit>=1&&limit<=100);return tx.execute(s->{owned(a,id);List<Map<String,Object>> rows;
  if(cursor==null)rows=db.queryForList("SELECT id,weight_g,recorded_on::text,source FROM pet_weight_records WHERE pet_id=? ORDER BY recorded_on DESC,created_at DESC,id DESC LIMIT ?",id,limit+1);
  else{UUID after=uuid(cursor);if(db.queryForObject("SELECT count(*) FROM pet_weight_records WHERE id=? AND pet_id=?",Integer.class,after,id)==0)throw new Failure(400,"INVALID_CURSOR");rows=db.queryForList("SELECT id,weight_g,recorded_on::text,source FROM pet_weight_records WHERE pet_id=? AND (recorded_on,created_at,id)<(SELECT recorded_on,created_at,id FROM pet_weight_records WHERE id=? AND pet_id=?) ORDER BY recorded_on DESC,created_at DESC,id DESC LIMIT ?",id,after,id,limit+1);}
  boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new ResultPage(data,more?data.getLast().get("id").toString():null,more);
 });}
 public Map<String,Object> weight(Actor a,UUID id,long expected,Map<String,Object> b,String key,HttpServletRequest r){consumer(a);check(b.keySet().equals(Set.of("weight_g","recorded_on","source")));long grams=number(b.get("weight_g"),1,100000000);LocalDate day=date(b.get("recorded_on"));String source=choice(b.get("source"),"OWNER_OBSERVATION","VET_DIAGNOSIS");return command(a,"pet.weight:"+id,key,Arrays.asList(expected,b),()->{var row=owned(a,id);if(((Number)row.get("version")).longValue()!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");UUID record=UUID.randomUUID();db.update("INSERT INTO pet_weight_records(id,pet_id,weight_g,recorded_on,source) VALUES (?,?,?,?,?)",record,id,grams,day,source);db.update("UPDATE pets SET current_weight_g=(SELECT weight_g FROM pet_weight_records WHERE pet_id=? ORDER BY recorded_on DESC,created_at DESC,id DESC LIMIT 1),version=version+1 WHERE id=?",id,id);audit.write(a,"pet.weight.record","PET",id.toString(),Map.of("version",expected),Map.of("version",expected+1),r);return Map.of("id",record,"weight_g",grams,"recorded_on",day.toString(),"source",source,"pet_version",expected+1);});}
}
