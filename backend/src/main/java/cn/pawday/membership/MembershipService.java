package cn.pawday.membership;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.identity.AuthService;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Period;
import java.time.ZoneOffset;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/**
 * Paid membership: versioned immutable plans, purchase orders paid through the shared payments pipeline,
 * activation extends the single per-user subscription row (renewal continues from the current expiry).
 * Membership refunds are intentionally deferred; PAID membership orders stay terminal in M5.1.
 */
@Service public class MembershipService {
 public static final long PAYMENT_WINDOW_SECONDS=900;
 private final JdbcTemplate db;private final TransactionTemplate tx;private final IdempotentCommandExecutor commands;
 private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;private final Clock clock;
 private final JsonMapper json=JsonMapper.builder().build();
 public MembershipService(JdbcTemplate db,TransactionTemplate tx,IdempotentCommandExecutor commands,OutboxWriter outbox,AuditWriter audit,AuthService auth,Clock clock){this.db=db;this.tx=tx;this.commands=commands;this.outbox=outbox;this.audit=audit;this.auth=auth;this.clock=clock;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->v.put(k,x instanceof Timestamp t?t.toInstant().toString():(k.equals("benefits")||k.equals("plan_snapshot"))&&x!=null?json.readValue(x.toString(),Object.class):x));return v;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 private void permission(Actor a,String p){if(a.realm()!=Actor.Realm.ADMIN||!a.permissions().contains(p))throw new Failure(403,"PERMISSION_DENIED");}

 /** Latest version per plan code; only ACTIVE versions are purchasable. */
 public List<Map<String,Object>> plans(Actor a){consumer(a);return db.queryForList("SELECT DISTINCT ON(code) * FROM membership_plans ORDER BY code,plan_version DESC").stream().filter(p->p.get("status").equals("ACTIVE")).map(this::view).toList();}
 public List<Map<String,Object>> adminPlans(Actor a){permission(a,"membership.plan.manage");return db.queryForList("SELECT * FROM membership_plans ORDER BY code,plan_version DESC").stream().map(this::view).toList();}

 public Map<String,Object> current(Actor a){
  consumer(a);
  var rows=db.queryForList("SELECT * FROM membership_subscriptions WHERE user_id=?",a.userId());
  if(rows.isEmpty())return Map.of("effective_status","NONE");
  var result=view(rows.getFirst());
  boolean active=result.get("status").equals("ACTIVE")&&((Timestamp)rows.getFirst().get("expires_at")).toInstant().isAfter(clock.instant());
  result.put("effective_status",active?"ACTIVE":"EXPIRED");
  return result;
 }

 public List<Map<String,Object>> orders(Actor a,UUID after,int limit){
  consumer(a);if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  return db.queryForList("SELECT * FROM membership_orders WHERE user_id=? AND id>? ORDER BY id LIMIT ?",a.userId(),after,limit+1).stream().map(this::view).toList();
 }

 public Map<String,Object> getOrder(Actor a,UUID id){
  consumer(a);var order=one("SELECT * FROM membership_orders WHERE id=? AND user_id=?",id,a.userId());
  var result=view(order);
  if(order.get("payment_id")!=null)result.put("payment",view(one("SELECT * FROM payments WHERE id=?",order.get("payment_id"))));
  return result;
 }

 /** Create a membership order and its payment intent; the renewal base is decided at activation, not at purchase. */
 public Map<String,Object> purchase(Actor a,Map<String,Object> b,String key,HttpServletRequest r){
  consumer(a);
  if(!b.keySet().equals(Set.of("plan_code"))||!(b.get("plan_code")instanceof String code)||code.isBlank()||code.length()>40)throw new Failure(400,"VALIDATION_ERROR");
  var held=commands.command(a,"membership.purchase:"+a.userId(),key,b,()->tx.execute(s->{
   db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,"membership.plan:"+code);
   var plans=db.queryForList("SELECT * FROM membership_plans WHERE code=? ORDER BY plan_version DESC LIMIT 1",code);
   if(plans.isEmpty()||!plans.getFirst().get("status").equals("ACTIVE"))throw new Failure(404,"RESOURCE_NOT_FOUND");
   var plan=plans.getFirst();
   UUID id=UUID.randomUUID(),payment=UUID.randomUUID();
   var snapshot=Map.of("plan_id",plan.get("id").toString(),"code",plan.get("code"),"name",plan.get("name"),"term",plan.get("term"),"price_fen",n(plan.get("price_fen")),"ai_quota",((Number)plan.get("ai_quota")).intValue(),"plan_version",((Number)plan.get("plan_version")).intValue(),"benefits",json.readValue(plan.get("benefits").toString(),List.class));
   db.update("INSERT INTO membership_orders(id,order_no,user_id,plan_id,plan_snapshot,amount_fen) VALUES (?,?,?,?,?::jsonb,?)",
    id,"M"+id.toString().replace("-",""),a.userId(),plan.get("id"),json.writeValueAsString(snapshot),n(plan.get("price_fen")));
   db.update("INSERT INTO payments(id,payment_no,membership_order_id,amount_fen,currency,expires_at) VALUES (?,?,?,?,'CNY',?)",
    payment,"P"+payment.toString().replace("-",""),id,n(plan.get("price_fen")),Timestamp.from(clock.instant().plusSeconds(PAYMENT_WINDOW_SECONDS)));
   db.update("UPDATE membership_orders SET payment_id=?,version=version+1 WHERE id=?",payment,id);
   audit.write(a,"membership.purchase","MEMBERSHIP_ORDER",id.toString(),Map.of(),Map.of("plan_code",code,"amount_fen",n(plan.get("price_fen"))),r);
   outbox.append("MEMBERSHIP_ORDER",id.toString(),"MembershipOrderCreated",1,Map.of("membership_order_id",id.toString(),"payment_id",payment.toString()),null);
   return Map.of("membership_order_id",id.toString());
  }));
  return getOrder(a,UUID.fromString(held.get("membership_order_id").toString()));
 }

 /** Payment success hook, executed inside the payment transaction; replay-safe. */
 public void activate(UUID membershipOrderId,UUID paymentId){
  var order=one("SELECT * FROM membership_orders WHERE id=? FOR UPDATE",membershipOrderId);
  if(order.get("status").equals("PAID"))return;
  if(!order.get("status").equals("PENDING_PAYMENT"))throw new Failure(409,"MEMBERSHIP_ORDER_STATE_CONFLICT");
  var plan=one("SELECT * FROM membership_plans WHERE id=?",order.get("plan_id"));
  db.update("INSERT INTO membership_plan_versions(id,version_code,parameters) VALUES (?,?,?::jsonb) ON CONFLICT(version_code) DO NOTHING",
   UUID.randomUUID(),"MP:"+plan.get("id"),json.writeValueAsString(json.readValue(order.get("plan_snapshot").toString(),Map.class)));
  UUID planVersion=(UUID)one("SELECT id FROM membership_plan_versions WHERE version_code=?","MP:"+plan.get("id").toString()).get("id");
  Timestamp now=Timestamp.from(clock.instant());
  Period term=plan.get("term").equals("YEAR")?Period.ofYears(1):Period.ofMonths(1);
  // The user row exists even before the first subscription; concurrent first purchases must serialize too.
  one("SELECT id FROM app_user WHERE id=? FOR UPDATE",order.get("user_id"));
  var subs=db.queryForList("SELECT * FROM membership_subscriptions WHERE user_id=? FOR UPDATE",order.get("user_id"));
  boolean extend=!subs.isEmpty()&&subs.getFirst().get("status").equals("ACTIVE")&&((Timestamp)subs.getFirst().get("expires_at")).toInstant().isAfter(clock.instant());
  if(subs.isEmpty()){
   Timestamp expiry=Timestamp.from(now.toInstant().atZone(ZoneOffset.UTC).plus(term).toInstant());
   db.update("INSERT INTO membership_subscriptions(user_id,plan_version_id,starts_at,expires_at,status) VALUES (?,?,?,?,'ACTIVE')",order.get("user_id"),planVersion,now,expiry);
  }else if(extend){
   Timestamp expiry=Timestamp.from(((Timestamp)subs.getFirst().get("expires_at")).toInstant().atZone(ZoneOffset.UTC).plus(term).toInstant());
   db.update("UPDATE membership_subscriptions SET plan_version_id=?,expires_at=?,status='ACTIVE',version=version+1 WHERE user_id=?",planVersion,expiry,order.get("user_id"));
  }else{
   Timestamp expiry=Timestamp.from(now.toInstant().atZone(ZoneOffset.UTC).plus(term).toInstant());
   db.update("UPDATE membership_subscriptions SET plan_version_id=?,starts_at=?,expires_at=?,status='ACTIVE',version=version+1 WHERE user_id=?",planVersion,now,expiry,order.get("user_id"));
  }
  Timestamp grantStart=extend?(Timestamp)subs.getFirst().get("expires_at"):now;
  Timestamp grantEnd=(Timestamp)one("SELECT expires_at FROM membership_subscriptions WHERE user_id=?",order.get("user_id")).get("expires_at");
  int aiUnits=((Number)json.readValue(order.get("plan_snapshot").toString(),Map.class).get("ai_quota")).intValue();
  db.update("INSERT INTO ai_membership_quota_grants VALUES (?,?,?,?,?) ON CONFLICT DO NOTHING",membershipOrderId,order.get("user_id"),grantStart,grantEnd,aiUnits);
  db.update("UPDATE membership_orders SET status='PAID',paid_at=?,version=version+1 WHERE id=?",now,membershipOrderId);
  outbox.append("MEMBERSHIP",order.get("user_id").toString(),"MembershipActivated",1,Map.of("user_id",order.get("user_id").toString(),"membership_order_id",membershipOrderId.toString(),"payment_id",paymentId.toString(),"renewal_extension",extend),null);
  audit.write(null,"membership.activate","MEMBERSHIP_ORDER",membershipOrderId.toString(),Map.of("status","PENDING_PAYMENT"),Map.of("status","PAID","renewal_extension",extend),null);
 }

 /** Close membership orders whose payment window has lapsed; in-flight attempts are left to payment recovery. */
 public int expireBatch(){
  int count=0;
  for(var row:db.queryForList("SELECT mo.id,p.id payment_id FROM membership_orders mo JOIN payments p ON p.id=mo.payment_id WHERE mo.status='PENDING_PAYMENT' AND p.status='PENDING' AND p.expires_at<=? ORDER BY p.expires_at,mo.id LIMIT 50",Timestamp.from(clock.instant()))){
   boolean closed=tx.execute(s->{var held=db.queryForList("SELECT id FROM membership_orders WHERE id=? AND status='PENDING_PAYMENT' FOR UPDATE SKIP LOCKED",row.get("id"));if(held.isEmpty())return false;
    if(!one("SELECT status FROM payments WHERE id=? FOR UPDATE",row.get("payment_id")).get("status").equals("PENDING"))return false;
    db.update("UPDATE payments SET status='CLOSED',version=version+1 WHERE id=?",row.get("payment_id"));
    db.update("UPDATE membership_orders SET status='EXPIRED',version=version+1 WHERE id=?",row.get("id"));
    audit.write(null,"membership.expire","MEMBERSHIP_ORDER",row.get("id").toString(),Map.of("status","PENDING_PAYMENT"),Map.of("status","EXPIRED"),null);
    return true;});
   if(closed)count++;
  }
  return count;
 }

 /** Publish a newer plan version; prior versions stay immutable and historically activated subscriptions keep their snapshot. */
 public Map<String,Object> createPlan(Actor a,Map<String,Object> b,String proof,HttpServletRequest r){
  permission(a,"membership.plan.manage");
  if(!b.keySet().equals(Set.of("code","name","term","price_fen","ai_quota","benefits","status"))||!(b.get("code")instanceof String code)||code.isBlank()||code.length()>40||!(b.get("name")instanceof String name)||name.isBlank()||name.length()>80||!Set.of("MONTH","YEAR").contains(b.get("term"))||!(b.get("price_fen")instanceof Number price)||price.longValue()<1||price.longValue()>100000000||price.doubleValue()!=price.longValue()||!Set.of("ACTIVE","RETIRED").contains(b.get("status")))throw new Failure(400,"VALIDATION_ERROR");
  long quota=b.get("ai_quota")instanceof Number q&&q.longValue()>=0&&q.doubleValue()==q.longValue()?q.longValue():-1;
  if(quota<0||quota>Integer.MAX_VALUE)throw new Failure(400,"VALIDATION_ERROR");
  Object benefits=b.get("benefits");if(!(benefits instanceof List<?> list)||list.stream().anyMatch(x->!(x instanceof String)))throw new Failure(400,"VALIDATION_ERROR");
  return tx.execute(s->{
   auth.consumeProof(a,"membership.plan.manage",proof);
   db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,"membership.plan:"+code);
   int version=db.queryForObject("SELECT coalesce(max(plan_version),0)+1 FROM membership_plans WHERE code=?",Integer.class,code);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO membership_plans(id,code,name,term,price_fen,ai_quota,benefits,status,plan_version,created_by) VALUES (?,?,?,?,?,?,?::jsonb,?,?,?)",id,code,name,b.get("term"),price.longValue(),(int)quota,json.writeValueAsString(benefits),b.get("status"),version,a.principalId());
   audit.write(a,"membership.plan.publish","MEMBERSHIP_PLAN",id.toString(),Map.of(),Map.of("code",code,"plan_version",version,"status",b.get("status")),r);
   return view(one("SELECT * FROM membership_plans WHERE id=?",id));
  });
 }
}
