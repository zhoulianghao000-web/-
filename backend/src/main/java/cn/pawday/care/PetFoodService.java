package cn.pawday.care;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class PetFoodService {
 private final PublishingSupport p; private final IdempotentCommandExecutor commands;
 private final AuditWriter audit; private final OutboxWriter outbox; private final TransactionTemplate tx; private final Clock clock;
 public PetFoodService(PublishingSupport p,IdempotentCommandExecutor commands,AuditWriter audit,OutboxWriter outbox,TransactionTemplate tx,Clock clock){this.p=p;this.commands=commands;this.audit=audit;this.outbox=outbox;this.tx=tx;this.clock=clock;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER||a.userId()==null)throw new Failure(403,"PERMISSION_DENIED");}
 private void owned(Actor a,UUID pet){consumer(a);p.one("SELECT id FROM pets WHERE id=? AND owner_user_id=? AND status='ACTIVE' FOR UPDATE",pet,a.userId());}
 private LocalDate today(){return LocalDate.now(clock.withZone(ZoneId.of("Asia/Shanghai")));}
 private LocalDate day(Object raw){try{LocalDate d=LocalDate.parse(text(raw,10));if(d.getYear()<1900||d.isAfter(today()))throw new IllegalArgumentException();return d;}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 public static long remaining(Map<String,Object> row,LocalDate now){long elapsed=Math.max(0,ChronoUnit.DAYS.between(LocalDate.parse(row.get("baseline_on").toString()),now));return Math.max(0,number(row.get("baseline_remaining_g"))-elapsed*number(row.get("daily_amount_g")));}
 public static LocalDate finish(Map<String,Object> row){long grams=number(row.get("baseline_remaining_g")),daily=number(row.get("daily_amount_g"));return LocalDate.parse(row.get("baseline_on").toString()).plusDays((grams+daily-1)/daily);}
 private Map<String,Object> view(Map<String,Object> row){var v=p.view(row);for(String key:List.of("started_on","baseline_on"))v.put(key,row.get(key).toString());v.remove("emitted_event_id");v.put("estimated_remaining_g",remaining(row,today()));v.put("estimated_finish_on",finish(row).toString());v.put("estimate_as_of",today().toString());v.put("estimate_notice","按你填写的每日用量估算，可随时校准；不是喂食建议。");return v;}
 public Map<String,Object> get(Actor a,UUID pet){return tx.execute(s->{owned(a,pet);var rows=p.db.queryForList("SELECT * FROM pet_food_plans WHERE pet_id=?",pet);return rows.isEmpty()?null:view(rows.getFirst());});}
 public List<Map<String,Object>> history(Actor a,UUID pet,UUID after,int limit){limit(limit);return tx.execute(s->{owned(a,pet);return p.db.queryForList("SELECT c.id,c.plan_id,c.version,c.action,c.created_at FROM pet_food_changes c JOIN pet_food_plans f ON f.id=c.plan_id WHERE f.pet_id=? AND c.id>? ORDER BY c.id LIMIT ?",pet,after,limit+1).stream().map(p::view).toList();});}
 public Map<String,Object> start(Actor a,UUID pet,Map<String,Object>b,String match,String key,HttpServletRequest request){consumer(a);fields(b,"sku_id","food_name","package_weight_g","daily_amount_g","started_on","reminder_enabled","remind_before_days");long expected=version(match);return commands.command(a,"pet.food.start:"+pet,key,Map.of("body",b,"version",expected),()->{
  owned(a,pet);var prior=p.db.queryForList("SELECT * FROM pet_food_plans WHERE pet_id=? FOR UPDATE",pet);if(prior.isEmpty()?expected!=0:number(prior.getFirst().get("version"))!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");
  UUID sku=b.get("sku_id")==null?null:id(b.get("sku_id"));String name=text(b.get("food_name"),160).trim();
  if(sku!=null)p.one("SELECT k.id FROM skus k JOIN spus s ON s.id=k.spu_id AND s.status='ACTIVE' JOIN brands b ON b.id=s.brand_id AND b.status='ACTIVE' JOIN sku_standard_versions v ON v.sku_id=k.id AND v.status='PUBLISHED' WHERE k.id=? AND k.status='ACTIVE'",sku);
  long grams=integer(b.get("package_weight_g"),1,100000000);int daily=integer(b.get("daily_amount_g"),1,1000000),before=integer(b.get("remind_before_days"),0,30);LocalDate started=day(b.get("started_on"));boolean enabled=bool(b.get("reminder_enabled"));
  UUID plan=prior.isEmpty()?UUID.randomUUID():(UUID)prior.getFirst().get("id");long next=prior.isEmpty()?1:expected+1;
  p.db.update("INSERT INTO pet_food_plans(id,pet_id,sku_id,food_name,package_weight_g,daily_amount_g,started_on,baseline_on,baseline_remaining_g,reminder_enabled,remind_before_days,version) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(pet_id) DO UPDATE SET sku_id=excluded.sku_id,food_name=excluded.food_name,package_weight_g=excluded.package_weight_g,daily_amount_g=excluded.daily_amount_g,started_on=excluded.started_on,baseline_on=excluded.baseline_on,baseline_remaining_g=excluded.baseline_remaining_g,reminder_enabled=excluded.reminder_enabled,remind_before_days=excluded.remind_before_days,active=true,version=excluded.version,emitted_event_id=NULL,updated_at=clock_timestamp()",plan,pet,sku,name,grams,daily,java.sql.Date.valueOf(started),java.sql.Date.valueOf(started),grams,enabled,before,next);
  return changed(a,plan,pet,"START",request);
 });}
 public Map<String,Object> calibrate(Actor a,UUID pet,Map<String,Object>b,String match,String key,HttpServletRequest request){consumer(a);fields(b,"remaining_g","recorded_on");long expected=version(match);return commands.command(a,"pet.food.calibrate:"+pet,key,Map.of("body",b,"version",expected),()->{owned(a,pet);var row=p.one("SELECT * FROM pet_food_plans WHERE pet_id=? AND active FOR UPDATE",pet);sameVersion(row,expected);long grams=integer(b.get("remaining_g"),0,100000000);LocalDate day=day(b.get("recorded_on"));if(grams>number(row.get("package_weight_g"))||day.isBefore(LocalDate.parse(row.get("baseline_on").toString())))throw new Failure(400,"VALIDATION_ERROR");p.db.update("UPDATE pet_food_plans SET baseline_remaining_g=?,baseline_on=?,version=version+1,emitted_event_id=NULL,updated_at=clock_timestamp() WHERE id=?",grams,java.sql.Date.valueOf(day),row.get("id"));return changed(a,(UUID)row.get("id"),pet,"CALIBRATE",request);});}
 public Map<String,Object> stop(Actor a,UUID pet,String match,String key,HttpServletRequest request){consumer(a);long expected=version(match);return commands.command(a,"pet.food.stop:"+pet,key,expected,()->{owned(a,pet);var row=p.one("SELECT * FROM pet_food_plans WHERE pet_id=? FOR UPDATE",pet);sameVersion(row,expected);p.db.update("UPDATE pet_food_plans SET active=false,version=version+1,updated_at=clock_timestamp() WHERE id=?",row.get("id"));return changed(a,(UUID)row.get("id"),pet,"STOP",request);});}
 private Map<String,Object> changed(Actor a,UUID plan,UUID pet,String action,HttpServletRequest request){var row=p.one("SELECT * FROM pet_food_plans WHERE id=?",plan);p.db.update("INSERT INTO pet_food_changes(id,plan_id,version,action,snapshot) VALUES (?,?,?,?,?::jsonb)",UUID.randomUUID(),plan,row.get("version"),action,p.json.writeValueAsString(view(row)));audit.write(a,"pet.food."+action.toLowerCase(Locale.ROOT),"PET",pet.toString(),Map.of(),Map.of("plan_id",plan,"version",row.get("version")),request);return view(row);}
 public int enqueueDue(){return tx.execute(s->{var rows=p.db.queryForList("SELECT f.* FROM pet_food_plans f JOIN pets p ON p.id=f.pet_id WHERE f.active AND f.reminder_enabled AND f.emitted_event_id IS NULL AND p.status='ACTIVE' AND f.baseline_on+((f.baseline_remaining_g+f.daily_amount_g-1)/f.daily_amount_g)::integer-f.remind_before_days<=?::date ORDER BY f.id LIMIT 100 FOR UPDATE OF f SKIP LOCKED",java.sql.Date.valueOf(today()));for(var row:rows){UUID plan=(UUID)row.get("id");UUID event=outbox.append("PET_FOOD_PLAN",plan.toString(),"PetFoodReminderDue",1,Map.of("plan_id",plan.toString(),"plan_version",row.get("version")),null);p.db.update("UPDATE pet_food_plans SET emitted_event_id=? WHERE id=?",event,plan);}return rows.size();});}
}
