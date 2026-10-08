package cn.pawday.points;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.identity.AuthService;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.math.BigInteger;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/**
 * Consumer points: append-only ledger with unique business keys; the balance is always derived from the ledger.
 * Negative balances are allowed so refund clawbacks can overtake spent points; new redemptions require
 * balance>=0 and balance>=cost, checked atomically under the per-user account row lock.
 */
@Service public class PointsService {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final IdempotentCommandExecutor commands;
 private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;private final Clock clock;
 private final JsonMapper json=JsonMapper.builder().build();
 public PointsService(JdbcTemplate db,TransactionTemplate tx,IdempotentCommandExecutor commands,OutboxWriter outbox,AuditWriter audit,AuthService auth,Clock clock){this.db=db;this.tx=tx;this.commands=commands;this.outbox=outbox;this.audit=audit;this.auth=auth;this.clock=clock;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->v.put(k,x instanceof Timestamp t?t.toInstant().toString():k.equals("reward_snapshot")&&x!=null?json.readValue(x.toString(),Map.class):x instanceof Date d?d.toLocalDate().toString():x));return v;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 private void permission(Actor a,String p){if(a.realm()!=Actor.Realm.ADMIN||!a.permissions().contains(p))throw new Failure(403,"PERMISSION_DENIED");}
 private Map<String,Object> policy(){return one("SELECT * FROM points_policies ORDER BY policy_version DESC LIMIT 1");}
 private void account(UUID user){db.update("INSERT INTO points_accounts(user_id) VALUES (?) ON CONFLICT(user_id) DO NOTHING",user);}
 private void lockAccount(UUID user){account(user);one("SELECT user_id FROM points_accounts WHERE user_id=? FOR UPDATE",user);}
 private long goodsPayable(UUID order){return db.queryForObject("SELECT coalesce(sum(i.payable_amount_fen),0) FROM order_items i JOIN suborders s ON s.id=i.suborder_id WHERE s.order_id=?",Long.class,order);}
 private long balance(UUID user){return db.queryForObject("SELECT coalesce(sum(points),0) FROM points_ledger WHERE user_id=?",Long.class,user);}
 private void entry(UUID user,String type,long points,String businessKey,UUID order,UUID refund,UUID redemption,Integer policyVersion,String reason,Actor actor){
  int inserted=db.update("INSERT INTO points_ledger(id,user_id,entry_type,points,business_key,order_id,refund_id,redemption_id,policy_version,reason,created_by_type,created_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(business_key) DO NOTHING",
   UUID.randomUUID(),user,type,points,businessKey,order,refund,redemption,policyVersion,reason,actor==null?"SYSTEM":"PRINCIPAL",actor==null?null:actor.principalId());
  if(inserted==1)outbox.append("POINTS",user.toString(),"PointsChanged",1,Map.of("user_id",user.toString(),"reason",type),null);
 }

 /** Goods payment success earns points from the payable amount at the policy rate frozen in the entry. */
 public void recordGoodsPaymentSuccess(UUID order,UUID payment,UUID user){
  var policies=db.queryForList("SELECT * FROM points_policies ORDER BY policy_version DESC LIMIT 1");
  if(policies.isEmpty())throw new Failure(503,"POINTS_POLICY_UNAVAILABLE");
  var p=policies.getFirst();long rate=n(p.get("earn_points_per_yuan"));
  long goodsPayable=goodsPayable(order);
  long earn=goodsPayable/100*rate;
  if(earn<1)return;
  lockAccount(user);
  entry(user,"PURCHASE_EARN",earn,"PURCHASE:"+payment,order,null,null,((Number)p.get("policy_version")).intValue(),null,null);
 }

 /** Refund success claws back the proportional share of what the order earned; the balance may go negative. */
 public void recordRefundSuccess(UUID refundId){
  recordReviewRefundSuccess(refundId);
  var refund=one("SELECT * FROM refunds WHERE id=?",refundId);
  UUID payment=(UUID)refund.get("payment_id");
  var earns=db.queryForList("SELECT * FROM points_ledger WHERE business_key=?","PURCHASE:"+payment);
  if(earns.isEmpty())return;
  var earn=earns.getFirst();UUID user=(UUID)earn.get("user_id"),order=(UUID)earn.get("order_id");
  lockAccount(user);
  if(db.queryForObject("SELECT count(*) FROM points_ledger WHERE business_key=?",Integer.class,"CLAWBACK:"+refundId)>0)return;
  long orderGoods=goodsPayable(order);
  if(orderGoods<1)return;
  // Cumulative successful frozen units, rather than flooring every separate partial refund.
  long refundedGoods=db.queryForObject("SELECT coalesce(sum(u.paid_amount_fen),0) FROM order_refund_unit_claims c JOIN order_item_refund_units u USING(order_item_id,unit_index) JOIN refunds r ON r.id=c.refund_id WHERE r.payment_id=? AND r.status='SUCCEEDED' AND c.status='REFUNDED'",Long.class,payment);
  if(refundedGoods<1)return;
  long earned=n(earn.get("points"));
  long clawed=db.queryForObject("SELECT coalesce(-sum(points),0) FROM points_ledger WHERE entry_type='REFUND_CLAWBACK' AND order_id=?",Long.class,order);
  long target=BigInteger.valueOf(earned).multiply(BigInteger.valueOf(Math.min(refundedGoods,orderGoods))).divide(BigInteger.valueOf(orderGoods)).longValueExact();
  long clawback=Math.max(0,target-clawed);
  if(clawback<1)return;
  entry(user,"REFUND_CLAWBACK",-clawback,"CLAWBACK:"+refundId,order,refundId,null,((Number)earn.get("policy_version")).intValue(),"退款追回",null);
 }

 /** Daily check-in: one row per user per day; the streak cycle continues from yesterday and resets after the configured cycle. */
 public Map<String,Object> checkin(Actor a,String key,HttpServletRequest r){
  consumer(a);
  var held=commands.command(a,"points.checkin:"+a.userId(),key,Map.of(),()->tx.execute(s->{
   account(a.userId());one("SELECT user_id FROM points_accounts WHERE user_id=? FOR UPDATE",a.userId());
   var p=policy();int cycleDays=((Number)p.get("checkin_cycle_days")).intValue();int points=((Number)p.get("checkin_points")).intValue();
   LocalDate today=clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
   if(db.queryForObject("SELECT count(*) FROM points_checkins WHERE user_id=? AND checkin_date=?",Integer.class,a.userId(),Date.valueOf(today))>0)throw new Failure(409,"CHECKIN_ALREADY_DONE");
   var yesterday=db.queryForList("SELECT cycle_day FROM points_checkins WHERE user_id=? AND checkin_date=?",a.userId(),Date.valueOf(today.minusDays(1)));
   int cycleDay=yesterday.isEmpty()?1:(((Number)yesterday.getFirst().get("cycle_day")).intValue()%cycleDays)+1;
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO points_checkins(id,user_id,checkin_date,cycle_day,points) VALUES (?,?,?,?,?)",id,a.userId(),Date.valueOf(today),cycleDay,points);
   entry(a.userId(),"CHECKIN_EARN",points,"CHECKIN:"+a.userId()+":"+today,null,null,null,((Number)p.get("policy_version")).intValue(),"连续签到第 "+cycleDay+" 天",null);
   audit.write(a,"points.checkin","POINTS_CHECKIN",id.toString(),Map.of(),Map.of("cycle_day",cycleDay,"points",points),r);
   return Map.of("checkin_id",id.toString());
  }));
  return view(one("SELECT * FROM points_checkins WHERE id=?",UUID.fromString(held.get("checkin_id").toString())));
 }

 /** Atomic redemption under the account row lock: negative balances and insufficient funds are both rejected. */
 public Map<String,Object> redeem(Actor a,Map<String,Object> b,String key,HttpServletRequest r){
  consumer(a);
  if(!b.keySet().equals(Set.of("reward_id"))||!(b.get("reward_id")instanceof String rewardRaw))throw new Failure(400,"VALIDATION_ERROR");
  UUID rewardId;try{rewardId=UUID.fromString(rewardRaw);}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}
  var held=commands.command(a,"points.redeem:"+a.userId(),key,b,()->tx.execute(s->{
   account(a.userId());one("SELECT user_id FROM points_accounts WHERE user_id=? FOR UPDATE",a.userId());
   var seed=one("SELECT code FROM points_rewards WHERE id=?",rewardId);
   db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,"points.reward:"+seed.get("code"));
   var reward=one("SELECT * FROM points_rewards WHERE code=? ORDER BY reward_version DESC LIMIT 1",seed.get("code"));
   if(!reward.get("id").equals(rewardId)||!reward.get("status").equals("ACTIVE"))throw new Failure(404,"RESOURCE_NOT_FOUND");
   long cost=n(reward.get("cost_points"));long balance=balance(a.userId());
   if(balance<0||balance<cost)throw new Failure(422,"POINTS_INSUFFICIENT");
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO points_redemptions(id,redemption_no,user_id,reward_id,reward_snapshot,cost_points,status) VALUES (?,?,?,?,?::jsonb,?,'SUCCEEDED')",
    id,"D"+id.toString().replace("-",""),a.userId(),rewardId,json.writeValueAsString(view(reward)),cost);
   entry(a.userId(),"REDEMPTION_SPEND",-cost,"REDEEM:"+id,null,null,id,((Number)reward.get("reward_version")).intValue(),"兑换 "+reward.get("name"),null);
   audit.write(a,"points.redeem","POINTS_REDEMPTION",id.toString(),Map.of(),Map.of("reward_code",reward.get("code"),"cost_points",cost),r);
   return Map.of("redemption_id",id.toString());
  }));
  return view(one("SELECT * FROM points_redemptions WHERE id=?",UUID.fromString(held.get("redemption_id").toString())));
 }

 public Map<String,Object> overview(Actor a){
  consumer(a);
  var result=new LinkedHashMap<String,Object>();
  result.put("balance",balance(a.userId()));
  LocalDate today=clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
  result.put("checked_in_today",db.queryForObject("SELECT count(*) FROM points_checkins WHERE user_id=? AND checkin_date=?",Integer.class,a.userId(),Date.valueOf(today))>0);
  var streak=db.queryForList("SELECT cycle_day FROM points_checkins WHERE user_id=? AND checkin_date IN (?,?) ORDER BY checkin_date DESC LIMIT 1",a.userId(),Date.valueOf(today),Date.valueOf(today.minusDays(1)));
  result.put("current_cycle_day",streak.isEmpty()?0:((Number)streak.getFirst().get("cycle_day")).intValue());
  result.put("policy",view(policy()));
  return result;
 }

 public List<Map<String,Object>> ledger(Actor a,String type,UUID after,int limit){
  consumer(a);if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(type!=null&&!Set.of("PURCHASE_EARN","REVIEW_EARN","MEDIA_REVIEW_BONUS","CHECKIN_EARN","REDEMPTION_SPEND","REFUND_CLAWBACK","REVIEW_CLAWBACK","MANUAL_ADJUSTMENT").contains(type))throw new Failure(400,"VALIDATION_ERROR");
  var args=new ArrayList<>();args.add(a.userId());args.add(after);
  String where="WHERE user_id=? AND id>?";
  if(type!=null){where+=" AND entry_type=?";args.add(type);}
  args.add(limit+1);
  return db.queryForList("SELECT * FROM points_ledger "+where+" ORDER BY id LIMIT ?",args.toArray()).stream().map(this::view).toList();
 }

 public List<Map<String,Object>> rewards(Actor a){consumer(a);return db.queryForList("SELECT DISTINCT ON(code) * FROM points_rewards ORDER BY code,reward_version DESC").stream().filter(x->x.get("status").equals("ACTIVE")).map(this::view).toList();}
 public List<Map<String,Object>> checkins(Actor a,int limit){consumer(a);if(limit<1||limit>62)throw new Failure(400,"VALIDATION_ERROR");return db.queryForList("SELECT * FROM points_checkins WHERE user_id=? ORDER BY checkin_date DESC LIMIT ?",a.userId(),limit).stream().map(this::view).toList();}

 public Map<String,Object> adjust(Actor a,UUID user,Map<String,Object> b,String key,String proof,HttpServletRequest r){
  permission(a,"points.adjust");
  if(!b.keySet().equals(Set.of("points","reason"))||!(b.get("points")instanceof Number points)||points.longValue()==0||points.longValue() < -100000000||points.longValue()>100000000||points.doubleValue()!=points.longValue()||!(b.get("reason")instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  var held=commands.command(a,"points.adjust:"+user,key,b,()->tx.execute(s->{
   auth.consumeProof(a,"points.adjust",proof);
   one("SELECT id FROM app_user WHERE id=?",user);
   account(user);one("SELECT user_id FROM points_accounts WHERE user_id=? FOR UPDATE",user);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO points_ledger(id,user_id,entry_type,points,business_key,reason,created_by_type,created_by) VALUES (?,?,'MANUAL_ADJUSTMENT',?,?,?,'PRINCIPAL',?)",id,user,points.longValue(),"MANUAL:"+id,reason,a.principalId());
   audit.write(a,"points.adjust","POINTS_LEDGER",id.toString(),Map.of(),Map.of("user_id",user,"points",points.longValue(),"reason",reason),r);
   outbox.append("POINTS",user.toString(),"PointsChanged",1,Map.of("user_id",user.toString(),"reason","MANUAL_ADJUSTMENT"),null);
   return Map.of("entry_id",id.toString());
  }));
  return view(one("SELECT * FROM points_ledger WHERE id=?",UUID.fromString(held.get("entry_id").toString())));
 }

 public Map<String,Object> adminOverview(Actor a,UUID user){
  permission(a,"points.read");
  one("SELECT id FROM app_user WHERE id=?",user);
  return Map.of("user_id",user.toString(),"balance",balance(user));
 }
 public List<Map<String,Object>> adminLedger(Actor a,UUID user,UUID after,int limit){
  permission(a,"points.read");if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  return db.queryForList("SELECT * FROM points_ledger WHERE user_id=? AND id>? ORDER BY id LIMIT ?",user,after,limit+1).stream().map(this::view).toList();
 }

 public Map<String,Object> createPolicy(Actor a,Map<String,Object> b,String proof,HttpServletRequest r){
  permission(a,"points.policy.manage");
  if(!b.keySet().equals(Set.of("earn_points_per_yuan","checkin_points","checkin_cycle_days"))||!(b.get("earn_points_per_yuan")instanceof Number rate)||rate.longValue()<0||rate.longValue()>1000||rate.doubleValue()!=rate.longValue()||!(b.get("checkin_points")instanceof Number cp)||cp.longValue()<1||cp.longValue()>10000||cp.doubleValue()!=cp.longValue()||!(b.get("checkin_cycle_days")instanceof Number cd)||cd.longValue()<1||cd.longValue()>30||cd.doubleValue()!=cd.longValue())throw new Failure(400,"VALIDATION_ERROR");
  return tx.execute(s->{
   auth.consumeProof(a,"points.policy.manage",proof);
   db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,"points.policy");
   int version=db.queryForObject("SELECT coalesce(max(policy_version),0)+1 FROM points_policies",Integer.class);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO points_policies(id,earn_points_per_yuan,checkin_points,checkin_cycle_days,policy_version,created_by) VALUES (?,?,?,?,?,?)",id,rate.intValue(),cp.intValue(),cd.intValue(),version,a.principalId());
   audit.write(a,"points.policy.create","POINTS_POLICY",id.toString(),Map.of(),Map.of("policy_version",version),r);
   return view(one("SELECT * FROM points_policies WHERE id=?",id));
  });
 }
 public List<Map<String,Object>> policies(Actor a){permission(a,"points.read");return db.queryForList("SELECT * FROM points_policies ORDER BY policy_version,id").stream().map(this::view).toList();}

 public Map<String,Object> createReward(Actor a,Map<String,Object> b,String proof,HttpServletRequest r){
  permission(a,"points.reward.manage");
  if(!b.keySet().equals(Set.of("code","name","cost_points","status"))||!(b.get("code")instanceof String code)||code.isBlank()||code.length()>60||!(b.get("name")instanceof String name)||name.isBlank()||name.length()>120||!(b.get("cost_points")instanceof Number cost)||cost.longValue()<1||cost.longValue()>100000000||cost.doubleValue()!=cost.longValue()||!Set.of("ACTIVE","RETIRED").contains(b.get("status")))throw new Failure(400,"VALIDATION_ERROR");
  return tx.execute(s->{
   auth.consumeProof(a,"points.reward.manage",proof);
   db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,"points.reward:"+code);
   int version=db.queryForObject("SELECT coalesce(max(reward_version),0)+1 FROM points_rewards WHERE code=?",Integer.class,code);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO points_rewards(id,code,name,cost_points,status,reward_version,created_by) VALUES (?,?,?,?,?,?,?)",id,code,name,cost.longValue(),b.get("status"),version,a.principalId());
   audit.write(a,"points.reward.publish","POINTS_REWARD",id.toString(),Map.of(),Map.of("code",code,"reward_version",version,"status",b.get("status")),r);
   return view(one("SELECT * FROM points_rewards WHERE id=?",id));
  });
 }
 public List<Map<String,Object>> adminRewards(Actor a){permission(a,"points.read");return db.queryForList("SELECT * FROM points_rewards ORDER BY code,reward_version DESC").stream().map(this::view).toList();}

 /** Caller holds the parent order lock and has approved a currently eligible received-item review. */
 public void recordReviewApproved(UUID reviewId,UUID revisionId){
  var review=one("SELECT * FROM reviews WHERE id=?",reviewId);
  UUID order=(UUID)review.get("order_id"),user=(UUID)review.get("user_id");
  var policies=db.queryForList("SELECT * FROM review_reward_policies ORDER BY policy_version DESC LIMIT 1");
  if(policies.isEmpty())throw new Failure(503,"REVIEW_POLICY_UNAVAILABLE");
  db.update("INSERT INTO review_reward_grants(order_id,user_id,policy_id,first_review_id) VALUES (?,?,?,?) ON CONFLICT(order_id) DO NOTHING",order,user,policies.getFirst().get("id"),reviewId);
  var policy=one("SELECT p.* FROM review_reward_grants g JOIN review_reward_policies p ON p.id=g.policy_id WHERE g.order_id=?",order);
  lockAccount(user);
  int v=((Number)policy.get("policy_version")).intValue();long base=n(policy.get("base_points")),bonus=n(policy.get("media_bonus_points"));
  if(base>0)entry(user,"REVIEW_EARN",base,"REVIEW_BASE:"+order,order,null,null,v,"审核通过评价奖励",null);
  var revision=one("SELECT asset_ids FROM review_revisions WHERE id=? AND review_id=?",revisionId,reviewId);
  if(bonus>0&&!json.readValue(revision.get("asset_ids").toString(),List.class).isEmpty())entry(user,"MEDIA_REVIEW_BONUS",bonus,"REVIEW_MEDIA:"+order,order,null,null,v,"审核通过媒体评价增量奖励",null);
  reconcileReviewRefund(order,null,"AWARD:"+revisionId);
 }

 private void recordReviewRefundSuccess(UUID refundId){
  var row=one("SELECT p.order_id FROM refunds r JOIN payments p ON p.id=r.payment_id WHERE r.id=?",refundId);
  if(row.get("order_id")!=null)reconcileReviewRefund((UUID)row.get("order_id"),refundId,"REFUND:"+refundId);
 }
 private void reconcileReviewRefund(UUID order,UUID refund,String suffix){
  var grants=db.queryForList("SELECT g.user_id,p.refund_strategy,p.policy_version FROM review_reward_grants g JOIN review_reward_policies p ON p.id=g.policy_id WHERE g.order_id=?",order);
  if(grants.isEmpty()||!grants.getFirst().get("refund_strategy").equals("PROPORTIONAL_GOODS"))return;
  UUID user=(UUID)grants.getFirst().get("user_id");lockAccount(user);
  long amount=goodsPayable(order);if(amount<1)return;
  long refunded=db.queryForObject("SELECT coalesce(sum(u.paid_amount_fen),0) FROM order_refund_unit_claims c JOIN order_item_refund_units u USING(order_item_id,unit_index) JOIN refunds r ON r.id=c.refund_id JOIN payments p ON p.id=r.payment_id WHERE p.order_id=? AND r.status='SUCCEEDED' AND c.status='REFUNDED'",Long.class,order);
  long earned=db.queryForObject("SELECT coalesce(sum(points),0) FROM points_ledger WHERE order_id=? AND entry_type IN ('REVIEW_EARN','MEDIA_REVIEW_BONUS')",Long.class,order);
  long clawed=db.queryForObject("SELECT coalesce(-sum(points),0) FROM points_ledger WHERE order_id=? AND entry_type='REVIEW_CLAWBACK'",Long.class,order);
  long target=BigInteger.valueOf(earned).multiply(BigInteger.valueOf(Math.min(amount,refunded))).divide(BigInteger.valueOf(amount)).longValueExact();
  if(target>clawed)entry(user,"REVIEW_CLAWBACK",-(target-clawed),"REVIEW_CLAWBACK:"+suffix,order,refund,null,((Number)grants.getFirst().get("policy_version")).intValue(),"按冻结评价规则追回退款对应奖励",null);
 }
}
