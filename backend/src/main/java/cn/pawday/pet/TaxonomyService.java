package cn.pawday.pet;
import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
import static cn.pawday.pet.PetService.*;

@Service
public class TaxonomyService {
 private final JdbcTemplate db;private final PetService commands;private final AuthService auth;private final AuditWriter audit;private final Clock clock;private final TransactionTemplate tx;
 private final JsonMapper json=JsonMapper.builder().build();
 public TaxonomyService(JdbcTemplate db,PetService commands,AuthService auth,AuditWriter audit,Clock clock,TransactionTemplate tx){this.db=db;this.commands=commands;this.auth=auth;this.audit=audit;this.clock=clock;this.tx=tx;}
 public List<Map<String,Object>> species(){return tx.execute(s->db.queryForList("SELECT id,parent_id,name,category FROM pet_species WHERE status='ACTIVE' ORDER BY category,parent_id NULLS FIRST,name,id").stream().map(row->{row.put("life_stages",db.queryForList("SELECT d.id,v.species_id,d.stage_code,d.display_name,d.rule_version_id,d.min_age_value,d.max_age_value,d.age_unit,d.is_unknown FROM pet_life_stage_definitions d JOIN pet_life_stage_rule_versions v ON v.id=d.rule_version_id WHERE v.species_id=? AND v.status='PUBLISHED' ORDER BY d.is_unknown,d.stage_code",row.get("id")));return row;}).toList());}
 public List<Map<String,Object>> breeds(UUID id){return db.queryForList("SELECT id,species_id,name FROM pet_breeds WHERE species_id=? AND status='ACTIVE' ORDER BY name,id",id);}
 public List<Map<String,Object>> allergens(){return db.queryForList("SELECT id,name FROM allergens WHERE status='ACTIVE' ORDER BY name,id");}
 public Map<String,Object> create(Actor a,String type,Map<String,Object> b,String proof,String key,HttpServletRequest r){
  if(a.realm()!=Actor.Realm.ADMIN||!a.permissions().contains("pet.taxonomy.write"))throw new Failure(403,"PERMISSION_DENIED");
  return commands.command(a,"pet.taxonomy."+type,key,b,()->{
   auth.consumeProof(a,"pet.taxonomy.write",proof);UUID id=UUID.randomUUID();String name=text(b.get("name"),160);
   switch(type){
    case "species"->{check(b.keySet().equals(Set.of("name","parent_id")));UUID parent=uuid(b.get("parent_id"));var roots=db.queryForList("SELECT category FROM pet_species WHERE id=? AND parent_id IS NULL AND status='ACTIVE' FOR UPDATE",parent);if(roots.isEmpty())throw new Failure(422,"PARENT_SPECIES_UNAVAILABLE");db.update("INSERT INTO pet_species(id,parent_id,name,category) VALUES (?,?,?,?)",id,parent,name,roots.getFirst().get("category"));}
    case "breeds"->{check(b.keySet().equals(Set.of("name","species_id")));UUID species=uuid(b.get("species_id"));if(db.queryForObject("SELECT count(*) FROM pet_species WHERE id=? AND status='ACTIVE'",Integer.class,species)==0)throw new Failure(422,"SPECIES_UNAVAILABLE");if(db.queryForObject("SELECT count(*) FROM pet_breeds WHERE species_id=? AND name=?",Integer.class,species,name)>0)throw new Failure(409,"ALREADY_EXISTS");db.update("INSERT INTO pet_breeds(id,species_id,name) VALUES (?,?,?)",id,species,name);}
    case "allergens"->{check(b.keySet().equals(Set.of("name")));db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","allergen:"+name);if(db.queryForObject("SELECT count(*) FROM allergens WHERE name=?",Integer.class,name)>0)throw new Failure(409,"ALREADY_EXISTS");db.update("INSERT INTO allergens(id,name) VALUES (?,?)",id,name);}
    default->throw new Failure(404,"RESOURCE_NOT_FOUND");
   }
   audit.write(a,"pet.taxonomy.create","PET_TAXONOMY",id.toString(),Map.of(),Map.of("type",type,"name",name),r);return Map.of("id",id,"name",name);
  });
 }
 public Map<String,Object> retire(Actor a,String type,UUID id,String proof,String key,HttpServletRequest r){return commands.command(a,"pet.taxonomy.retire:"+type+":"+id,key,id,()->{auth.consumeProof(a,"pet.taxonomy.write",proof);String table=switch(type){case "species"->"pet_species";case "breeds"->"pet_breeds";case "allergens"->"allergens";default->throw new Failure(404,"RESOURCE_NOT_FOUND");};if(type.equals("species")&&db.queryForObject("SELECT count(*) FROM pet_species WHERE id=? AND parent_id IS NULL",Integer.class,id)>0)throw new Failure(422,"ROOT_CATEGORY_REQUIRED");if(db.update("UPDATE "+table+" SET status='RETIRED' WHERE id=? AND status='ACTIVE'",id)!=1)throw new Failure(404,"RESOURCE_NOT_FOUND");audit.write(a,"pet.taxonomy.retire","PET_TAXONOMY",id.toString(),Map.of("status","ACTIVE"),Map.of("status","RETIRED"),r);return Map.of("id",id,"status","RETIRED");});}
 public Map<String,Object> publish(Actor a,Map<String,Object> b,String proof,String key,HttpServletRequest r){
  check(b.keySet().equals(Set.of("species_id","source_refs","stages")));UUID species=uuid(b.get("species_id"));check(b.get("source_refs") instanceof List<?> && b.get("stages") instanceof List<?>);
  var sources=(List<?>)b.get("source_refs");check(sources.size()<=20);sources.forEach(x->text(x,2000));var stages=(List<?>)b.get("stages");check(!stages.isEmpty()&&stages.size()<=30);
  Set<String> codes=new HashSet<>();int unknown=0;String unit=null;List<long[]> ranges=new ArrayList<>();
  for(Object raw:stages){check(raw instanceof Map<?,?>);var d=(Map<?,?>)raw;check(d.keySet().equals(Set.of("stage_code","display_name","min_age_value","max_age_value","age_unit","is_unknown")));check(codes.add(text(d.get("stage_code"),80)));text(d.get("display_name"),160);String age=text(d.get("age_unit"),8);check(Set.of("DAY","MONTH","YEAR").contains(age));check(d.get("is_unknown") instanceof Boolean);
   if(Boolean.TRUE.equals(d.get("is_unknown"))){unknown++;check(d.get("min_age_value")==null&&d.get("max_age_value")==null);}
   else{check(!sources.isEmpty());if(unit==null)unit=age;check(unit.equals(age));long min=number(d.get("min_age_value"),0,Integer.MAX_VALUE);long max=d.get("max_age_value")==null?Long.MAX_VALUE:number(d.get("max_age_value"),min+1,Integer.MAX_VALUE);for(long[] prior:ranges)check(min>=prior[1]||max<=prior[0]);ranges.add(new long[]{min,max});}
  }check(unknown==1);
  return commands.command(a,"pet.taxonomy.publish:"+species,key,b,()->{
   auth.consumeProof(a,"pet.taxonomy.write",proof);var rows=db.queryForList("SELECT id FROM pet_species WHERE id=? AND status='ACTIVE' FOR UPDATE",species);if(rows.isEmpty())throw new Failure(422,"SPECIES_UNAVAILABLE");
   long version=db.queryForObject("SELECT COALESCE(max(version_no),0)+1 FROM pet_life_stage_rule_versions WHERE species_id=?",Long.class,species);UUID id=UUID.randomUUID();db.update("INSERT INTO pet_life_stage_rule_versions(id,species_id,version_no,status,source_refs) VALUES (?,?,?,'DRAFT',?::jsonb)",id,species,version,json.writeValueAsString(sources));
   for(Object raw:stages){var d=(Map<?,?>)raw;db.update("INSERT INTO pet_life_stage_definitions(id,rule_version_id,stage_code,display_name,min_age_value,max_age_value,age_unit,is_unknown) VALUES (?,?,?,?,?,?,?,?)",UUID.randomUUID(),id,d.get("stage_code"),d.get("display_name"),d.get("min_age_value"),d.get("max_age_value"),d.get("age_unit"),d.get("is_unknown"));}
   db.update("UPDATE pet_life_stage_rule_versions SET status='RETIRED' WHERE species_id=? AND status='PUBLISHED'",species);db.update("UPDATE pet_life_stage_rule_versions SET status='PUBLISHED',published_at=? WHERE id=?",Timestamp.from(clock.instant()),id);audit.write(a,"pet.taxonomy.publish","PET_RULE",id.toString(),Map.of(),Map.of("species_id",species,"version_no",version,"source_refs",sources),r);return Map.of("id",id,"species_id",species,"version_no",version,"status","PUBLISHED");
  });
 }
}
