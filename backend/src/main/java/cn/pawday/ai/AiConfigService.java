package cn.pawday.ai;
import cn.pawday.common.*;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;

@Service
public class AiConfigService {
 private final PublishingSupport p;private final IdempotentCommandExecutor commands;private final AuthService auth;private final AuditWriter audit;private final AiEvidenceService evidence;private final ExplanationProvider provider;
 public AiConfigService(PublishingSupport p,IdempotentCommandExecutor commands,AuthService auth,AuditWriter audit,AiEvidenceService evidence,ExplanationProvider provider){this.p=p;this.commands=commands;this.auth=auth;this.audit=audit;this.evidence=evidence;this.provider=provider;}
 void read(Actor a){permission(a,Actor.Realm.ADMIN,"ai.read");}
 public Map<String,Object> release(Actor a){read(a);var out=p.view(p.one("SELECT * FROM ai_release"));out.remove("singleton");out.put("provider_available",provider.available());out.put("fit_rule_version",cn.pawday.catalog.ConsumerCatalogService.FIT_RULE_VERSION);return out;}
 public List<Map<String,Object>> prompts(Actor a){read(a);return p.db.queryForList("SELECT v.*,CASE WHEN r.active_prompt_id=v.id THEN 'ACTIVE' WHEN r.staged_prompt_id=v.id THEN 'STAGED' WHEN EXISTS(SELECT 1 FROM ai_evaluations e WHERE e.prompt_id=v.id AND e.passed) THEN 'VALIDATED' ELSE 'DRAFT' END status FROM ai_prompt_versions v CROSS JOIN ai_release r ORDER BY v.created_at DESC,v.id LIMIT 100").stream().map(p::view).toList();}
 public List<Map<String,Object>> policies(Actor a){read(a);return p.db.queryForList("SELECT * FROM ai_policy_versions ORDER BY created_at DESC,id LIMIT 100").stream().map(p::view).toList();}
 public List<Map<String,Object>> evaluations(Actor a){read(a);return p.db.queryForList("SELECT * FROM ai_evaluations ORDER BY created_at DESC,id LIMIT 100").stream().map(x->{var v=p.view(x);v.put("cases",p.json.readValue(x.get("cases").toString(),List.class));return v;}).toList();}
 public Map<String,Object> rules(Actor a){read(a);return Map.of("fit_rule_version",cn.pawday.catalog.ConsumerCatalogService.FIT_RULE_VERSION,"authority","POSTGRESQL_DETERMINISTIC_RULES","model_tools",List.of(),"hard_conflicts_overridable",false,"maximum_comparison_skus",3);}
 private Map<String,Object> mutate(Actor a,String action,Map<String,Object>b,String key,String proof,HttpServletRequest r,java.util.function.Supplier<Map<String,Object>> work){permission(a,Actor.Realm.ADMIN,"ai.manage");read(a);return commands.command(a,"ai.manage:"+action,key,b,()->{auth.consumeProof(a,"ai.manage",proof);var result=work.get();audit.write(a,"ai."+action,"AI_CONFIGURATION",result.get("id")==null?null:result.get("id").toString(),Map.of(),result,r);return result;});}
 public Map<String,Object> prompt(Actor a,Map<String,Object>b,String key,String proof,HttpServletRequest r){fields(b,"instruction");String value=text(b.get("instruction"),2000);var ref=mutate(a,"prompt.create",b,key,proof,r,()->{UUID id=UUID.randomUUID();p.db.update("INSERT INTO ai_prompt_versions(id,instruction) VALUES (?,?)",id,value);return Map.of("id",id);});return p.view(p.one("SELECT * FROM ai_prompt_versions WHERE id=?",UUID.fromString(ref.get("id").toString())));}
 private List<Map<String,Object>> checks(String instruction){
  var snapshot=new AiEvidenceService.Snapshot(null,null,null,List.of(),List.of(Map.of("id","known","kind","FIT")));var cases=new ArrayList<Map<String,Object>>();
  cases.add(Map.of("case_code","EDITORIAL_JSON_CONTRACT","passed",instruction.toLowerCase(Locale.ROOT).contains("json")));
  for(var ids:List.of(List.<String>of(),List.of("invented"),List.of("known","known"),List.of("pay_order"),List.of("diagnose_disease"),List.of("modify_pet_profile_without_confirmation"))){boolean rejected=false;try{evidence.render(snapshot,new ExplanationProvider.Plan(ids));}catch(Failure f){rejected=true;}cases.add(Map.of("case_code",ids.isEmpty()?"EMPTY_PLAN":String.join(",",ids),"passed",rejected));}
  boolean good=true;try{evidence.render(snapshot,new ExplanationProvider.Plan(List.of("known")));}catch(Failure f){good=false;}cases.add(Map.of("case_code","KNOWN_EVIDENCE_PLAN","passed",good));return cases;
 }
 public Map<String,Object> validate(Actor a,UUID prompt,String key,String proof,HttpServletRequest r){var ref=mutate(a,"prompt.validate",Map.of("prompt_id",prompt),key,proof,r,()->{String instruction=p.one("SELECT instruction FROM ai_prompt_versions WHERE id=?",prompt).get("instruction").toString();var cases=checks(instruction);boolean passed=cases.stream().allMatch(x->Boolean.TRUE.equals(x.get("passed")));UUID id=UUID.randomUUID();p.db.update("INSERT INTO ai_evaluations(id,prompt_id,passed,cases) VALUES (?,?,?,?::jsonb)",id,prompt,passed,p.json.writeValueAsString(cases));return Map.of("id",id);});var row=p.one("SELECT * FROM ai_evaluations WHERE id=?",UUID.fromString(ref.get("id").toString()));var out=p.view(row);out.put("cases",p.json.readValue(row.get("cases").toString(),List.class));return out;}
 private void validated(UUID prompt){if(p.db.queryForObject("SELECT count(*) FROM ai_evaluations WHERE prompt_id=? AND passed",Integer.class,prompt)==0)throw new Failure(409,"AI_PROMPT_NOT_VALIDATED");}
 public Map<String,Object> publish(Actor a,UUID prompt,String action,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){long expected=version(match);if(action.equals("stage"))fields(b,"percentage");else fields(b);int percent=action.equals("stage")?integer(b.get("percentage"),1,99):0;
  mutate(a,"prompt."+action,Map.of("prompt_id",prompt,"version",expected,"percentage",percent),key,proof,r,()->{var prior=p.one("SELECT * FROM ai_release FOR UPDATE");sameVersion(prior,expected);if(action.equals("rollback")){if(p.db.queryForObject("SELECT count(*) FROM ai_release_history WHERE active_prompt_id=?",Integer.class,prompt)==0)throw new Failure(409,"AI_ROLLBACK_TARGET_NOT_RELEASED");}else validated(prompt);
   p.db.update("UPDATE ai_release SET active_prompt_id=?,staged_prompt_id=?,staged_percent=?,version=version+1",action.equals("stage")?prior.get("active_prompt_id"):prompt,action.equals("stage")?prompt:null,percent);record(action);return Map.of("id",prompt,"version",expected+1,"percentage",percent);});return release(a);
 }
 void record(String action){p.db.update("INSERT INTO ai_release_history SELECT gen_random_uuid(),active_prompt_id,staged_prompt_id,staged_percent,policy_id,version,?,now() FROM ai_release",action);}
 public Map<String,Object> policy(Actor a,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){fields(b,"ordinary_daily_limit","member_daily_ceiling","retention_days","lease_seconds","enabled");int ordinary=integer(b.get("ordinary_daily_limit"),0,1000),member=integer(b.get("member_daily_ceiling"),0,10000),retention=integer(b.get("retention_days"),1,90),lease=integer(b.get("lease_seconds"),10,120);boolean enabled=bool(b.get("enabled"));long expected=version(match);
  var result=mutate(a,"policy.publish",Map.of("body",b,"version",expected),key,proof,r,()->{var prior=p.one("SELECT * FROM ai_release FOR UPDATE");sameVersion(prior,expected);UUID id=UUID.randomUUID();p.db.update("INSERT INTO ai_policy_versions(id,ordinary_daily_limit,member_daily_ceiling,retention_days,lease_seconds,enabled) VALUES (?,?,?,?,?,?)",id,ordinary,member,retention,lease,enabled);p.db.update("UPDATE ai_release SET policy_id=?,version=version+1",id);record("policy");return Map.of("id",id,"version",expected+1);});return p.view(p.one("SELECT * FROM ai_policy_versions WHERE id=?",UUID.fromString(result.get("id").toString())));
 }
}
