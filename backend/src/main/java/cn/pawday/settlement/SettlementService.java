package cn.pawday.settlement;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.identity.AuthService;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.math.BigInteger;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Merchant settlement ledger: commission snapshots frozen at payment success, append-only ledger entries,
 * per-suborder settlement tracks with after-sale buffering, batch settlement with simulated disbursement.
 * Ledger rows are never updated or deleted; post-settlement refunds bridge through SETTLEMENT_ADJUSTMENT.
 */
@Service public class SettlementService {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final IdempotentCommandExecutor commands;
 private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;private final Clock clock;
 public SettlementService(JdbcTemplate db,TransactionTemplate tx,IdempotentCommandExecutor commands,OutboxWriter outbox,AuditWriter audit,AuthService auth,Clock clock){this.db=db;this.tx=tx;this.commands=commands;this.outbox=outbox;this.audit=audit;this.auth=auth;this.clock=clock;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->v.put(k,x instanceof Timestamp t?t.toInstant().toString():x));return v;}
 private String correlation(HttpServletRequest r){return r==null?null:(String)r.getAttribute("correlation_id");}
 private void permission(Actor a,String p){if(a.realm()!=Actor.Realm.ADMIN||!a.permissions().contains(p))throw new Failure(403,"PERMISSION_DENIED");}
 private UUID merchantScope(Actor a,String p){if(a.realm()==Actor.Realm.MERCHANT){if(!a.permissions().contains(p))throw new Failure(403,"PERMISSION_DENIED");return a.merchantId();}if(a.realm()==Actor.Realm.ADMIN&&a.permissions().contains(p))return null;throw new Failure(403,"PERMISSION_DENIED");}
 private long roundCommission(long base,long rateBp){return (base*rateBp+5000)/10000;}
 private void ledger(UUID merchant,String type,String direction,long amount,boolean affects,UUID order,UUID sub,UUID item,UUID refund,UUID settlement,String event,String reason,Actor actor){
  if(amount<1)return;
  db.update("INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,order_id,suborder_id,order_item_id,refund_id,settlement_id,source_event,reason,created_by_type,created_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
   UUID.randomUUID(),merchant,type,direction,amount,affects,order,sub,item,refund,settlement,event,reason,actor==null?"SYSTEM":"PRINCIPAL",actor==null?null:actor.principalId());
 }

 /** Payment success freezes commission snapshots and posts pending sale facts; money is not withdrawable yet. */
 public void recordPaymentSuccess(UUID order,UUID payment){
  for(var sub:db.queryForList("SELECT * FROM suborders WHERE order_id=? ORDER BY id",order)){
   UUID subId=(UUID)sub.get("id"),merchant=(UUID)sub.get("merchant_id");
   db.update("INSERT INTO settlement_tracks(id,suborder_id,order_id,merchant_id,status) VALUES (?,?,?,?,'WAITING_RECEIPT') ON CONFLICT(suborder_id) DO NOTHING",UUID.randomUUID(),subId,order,merchant);
   ledger(merchant,"SALE_CREDIT","CREDIT",n(sub.get("payable_amount_fen")),true,order,subId,null,null,null,"PAYMENT_SUCCEEDED",null,null);
   for(var item:db.queryForList("SELECT i.*,p.category FROM order_items i JOIN skus s ON s.id=i.sku_id JOIN spus p ON p.id=s.spu_id WHERE i.suborder_id=? ORDER BY i.id",subId)){
    UUID itemId=(UUID)item.get("id");long base=n(item.get("payable_amount_fen"));
    var policies=db.queryForList("SELECT * FROM commission_policies WHERE (merchant_id IS NULL OR merchant_id=?) AND (category IS NULL OR category=?) AND effective_from<=clock_timestamp() AND (effective_to IS NULL OR effective_to>clock_timestamp()) ORDER BY priority DESC,(merchant_id IS NULL) ASC,(category IS NULL) ASC,effective_from DESC LIMIT 1",merchant,item.get("category"));
    var policy=policies.isEmpty()?null:policies.getFirst();
    long rate=policy==null?0:n(policy.get("rate_basis_points"));long commission=roundCommission(base,rate);
    db.update("INSERT INTO commission_allocations(id,order_item_id,payment_id,policy_id,policy_version,priority,rate_basis_points,base_amount_fen,commission_fen) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(order_item_id) DO NOTHING",
     UUID.randomUUID(),itemId,payment,policy==null?null:policy.get("id"),policy==null?null:((Number)policy.get("policy_version")).intValue(),policy==null?null:((Number)policy.get("priority")).intValue(),rate,base,commission);
    ledger(merchant,"COMMISSION_DEBIT","DEBIT",commission,true,order,subId,itemId,null,null,"PAYMENT_SUCCEEDED",null,null);
   }
  }
 }

 /** Receipt completion starts the after-sale buffer; an already-open after-sale freezes the track immediately. */
 public void beginBuffering(UUID sub){
  var rows=db.queryForList("SELECT * FROM settlement_tracks WHERE suborder_id=? AND status='WAITING_RECEIPT' FOR UPDATE",sub);
  if(rows.isEmpty())return;
  db.update("INSERT INTO settlement_policies(id,buffer_days,policy_version) VALUES ('7b2f2b6a-7c1f-4d0d-9c1a-000000000002',7,1) ON CONFLICT(id) DO NOTHING");
  var policy=one("SELECT * FROM settlement_policies ORDER BY policy_version DESC LIMIT 1");
  boolean open=db.queryForObject("SELECT count(*) FROM aftersales WHERE suborder_id=? AND status NOT IN ('COMPLETED','REJECTED','CANCELLED')",Integer.class,sub)>0;
  db.update("UPDATE settlement_tracks SET status=?,settlement_policy_id=?,buffer_days=?,eligible_at=clock_timestamp()+(?*interval '1 day'),version=version+1 WHERE id=?",open?"FROZEN":"BUFFERING",policy.get("id"),((Number)policy.get("buffer_days")).intValue(),((Number)policy.get("buffer_days")).intValue(),rows.getFirst().get("id"));
 }

 /** A cancelled suborder never settles; the refund entries still post against the adjusted track. */
 public void onSuborderCancelled(UUID sub){db.update("UPDATE settlement_tracks SET status='ADJUSTED',version=version+1 WHERE suborder_id=? AND status='WAITING_RECEIPT'",sub);}

 /** After-sale creation freezes a buffering or eligible track; tracks in flight or settled stay untouched. */
 public void freezeForAftersale(UUID sub){db.update("UPDATE settlement_tracks SET status='FROZEN',version=version+1 WHERE suborder_id=? AND status IN ('BUFFERING','ELIGIBLE')",sub);}

 /** Terminal after-sale states recompute eligibility; other open after-sales keep the track frozen. */
 public void unfreezeIfClear(UUID sub){
  var rows=db.queryForList("SELECT * FROM settlement_tracks WHERE suborder_id=? AND status='FROZEN' FOR UPDATE",sub);
  if(rows.isEmpty())return;
  if(db.queryForObject("SELECT count(*) FROM aftersales WHERE suborder_id=? AND status NOT IN ('COMPLETED','REJECTED','CANCELLED')",Integer.class,sub)>0)return;
  var track=rows.getFirst();var eligibleAt=(Timestamp)track.get("eligible_at");
  boolean due=eligibleAt!=null&&!eligibleAt.toInstant().isAfter(clock.instant());
  db.update("UPDATE settlement_tracks SET status=?,version=version+1 WHERE id=?",due?"ELIGIBLE":"BUFFERING",track.get("id"));
 }

 /** Refund success posts negative/reversal entries against the frozen commission allocation, never recomputed from current rates. */
 public void recordRefundSuccess(UUID refundId){
  var refund=one("SELECT * FROM refunds WHERE id=?",refundId);
  UUID sub=refund.get("cancellation_id")!=null?(UUID)one("SELECT suborder_id FROM order_cancellations WHERE id=?",refund.get("cancellation_id")).get("suborder_id"):(UUID)one("SELECT suborder_id FROM aftersales WHERE id=?",refund.get("aftersale_id")).get("suborder_id");
  var subrow=one("SELECT * FROM suborders WHERE id=?",sub);
  UUID merchant=(UUID)subrow.get("merchant_id"),order=(UUID)subrow.get("order_id");
  record Line(UUID item,long goods){}
  var lines=new ArrayList<Line>();long shipping=0;
  if(refund.get("cancellation_id")!=null)for(var l:db.queryForList("SELECT order_item_id,item_payable_refund_fen,shipping_refund_fen FROM order_cancellation_items WHERE refund_id=? ORDER BY id",refundId)){lines.add(new Line((UUID)l.get("order_item_id"),n(l.get("item_payable_refund_fen"))));shipping+=n(l.get("shipping_refund_fen"));}
  else for(var l:db.queryForList("SELECT order_item_id,item_payable_refund_fen FROM aftersale_items WHERE refund_id=? ORDER BY id",refundId))lines.add(new Line((UUID)l.get("order_item_id"),n(l.get("item_payable_refund_fen"))));
  var track=one("SELECT * FROM settlement_tracks WHERE suborder_id=? FOR UPDATE",sub);
  // ADJUSTED is still a previously paid track. Its immutable batch reference is the authority.
  boolean settled=track.get("settlement_id")!=null;
  long amount=n(refund.get("amount_fen"));long goods=amount-shipping;long reversedTotal=0;
  for(var line:lines){
   var allocs=db.queryForList("SELECT * FROM commission_allocations WHERE order_item_id=?",line.item());
   if(allocs.isEmpty())continue;
   var alloc=allocs.getFirst();long commission=n(alloc.get("commission_fen")),base=n(alloc.get("base_amount_fen"));
   if(commission<1||base<1||line.goods()<1)continue;
   long already=db.queryForObject("SELECT coalesce(sum(amount_fen),0) FROM merchant_ledger_entries WHERE entry_type='COMMISSION_REVERSAL' AND order_item_id=?",Long.class,line.item());
   long refunded=db.queryForObject("SELECT coalesce(sum(u.paid_amount_fen),0) FROM order_refund_unit_claims c JOIN order_item_refund_units u USING(order_item_id,unit_index) JOIN refunds r ON r.id=c.refund_id WHERE c.order_item_id=? AND r.status='SUCCEEDED' AND c.status='REFUNDED'",Long.class,line.item());
   long target=BigInteger.valueOf(commission).multiply(BigInteger.valueOf(Math.min(base,refunded))).add(BigInteger.valueOf(base/2)).divide(BigInteger.valueOf(base)).longValueExact();
   long rev=Math.max(0,target-already);
   if(rev<1)continue;
   reversedTotal+=rev;
   ledger(merchant,"COMMISSION_REVERSAL","CREDIT",rev,!settled,order,sub,line.item(),refundId,null,"REFUND_SUCCEEDED",settled?"已结算后退款冲销":null,null);
  }
  ledger(merchant,"REFUND_DEBIT","DEBIT",goods,!settled,order,sub,null,refundId,null,"REFUND_SUCCEEDED",settled?"已结算后退款冲销":null,null);
  ledger(merchant,"SHIPPING_ADJUSTMENT","DEBIT",shipping,!settled,order,sub,null,refundId,null,"REFUND_SUCCEEDED",settled?"已结算后运费退款冲销":null,null);
  if(settled){
   long net=amount-reversedTotal;
   ledger(merchant,"SETTLEMENT_ADJUSTMENT","DEBIT",net,true,order,sub,null,refundId,(UUID)track.get("settlement_id"),"SETTLED_REFUND_ADJUSTMENT","已结算批次发生退款，从后续可结算金额抵扣",null);
   db.update("UPDATE settlement_tracks SET status='ADJUSTED',version=version+1 WHERE id=? AND status='SETTLED'",track.get("id"));
   outbox.append("SETTLEMENT",track.get("settlement_id").toString(),"SettlementAdjustmentCreated",1,Map.of("settlement_id",track.get("settlement_id").toString(),"refund_id",refundId.toString(),"amount_fen",net),null);
  }
 }

 /** Buffer expiry sweep: BUFFERING -> ELIGIBLE when due and no open after-sale blocks. */
 public int promoteDue(){
  int count=0;
  for(var t:db.queryForList("SELECT * FROM settlement_tracks WHERE status='BUFFERING' AND eligible_at<=clock_timestamp() ORDER BY eligible_at,id LIMIT 50")){
   UUID id=(UUID)t.get("id"),sub=(UUID)t.get("suborder_id");
   try{tx.executeWithoutResult(s->{var held=db.queryForList("SELECT id FROM settlement_tracks WHERE id=? AND status='BUFFERING' FOR UPDATE",id);if(held.isEmpty())return;
    if(db.queryForObject("SELECT count(*) FROM aftersales WHERE suborder_id=? AND status NOT IN ('COMPLETED','REJECTED','CANCELLED')",Integer.class,sub)>0){db.update("UPDATE settlement_tracks SET status='FROZEN',version=version+1 WHERE id=?",id);return;}
    db.update("UPDATE settlement_tracks SET status='ELIGIBLE',version=version+1 WHERE id=?",id);
    outbox.append("SETTLEMENT_TRACK",sub.toString(),"SettlementEligible",1,Map.of("suborder_id",sub.toString()),null);
    audit.write(null,"settlement.eligible","SETTLEMENT_TRACK",id.toString(),Map.of("status","BUFFERING"),Map.of("status","ELIGIBLE"),null);});
    count++;
   }catch(Exception e){org.slf4j.LoggerFactory.getLogger(SettlementService.class).warn("Settlement promotion retained for retry: {}",id);}
  }
  return count;
 }

 private Map<String,Object> attemptDisburse(UUID settlementId){
  var st=one("SELECT * FROM settlements WHERE id=? FOR UPDATE",settlementId);
  String status=st.get("status").toString();
  if(status.equals("FAILED_RETRYABLE"))db.update("UPDATE settlements SET status='PROCESSING',attempt_count=attempt_count+1,next_retry_at=NULL WHERE id=?",settlementId);
  else if(!status.equals("PROCESSING"))throw new Failure(409,"SETTLEMENT_STATE_CONFLICT");
  var directive=db.queryForList("SELECT outcome FROM simulated_settlement_directives WHERE settlement_no=?",st.get("settlement_no"));
  // Tests can stage a one-shot transient failure for the merchant's next disbursement before the settlement number exists.
  if(directive.isEmpty()&&1==db.update("DELETE FROM simulated_settlement_directives WHERE settlement_no=? AND outcome='FAIL_TRANSIENT'","MERCHANT:"+st.get("merchant_id")))directive=List.of(Map.of("outcome","FAIL_TRANSIENT"));
  boolean fail=!directive.isEmpty()&&directive.getFirst().get("outcome").equals("FAIL_TRANSIENT");
  if(fail){db.update("UPDATE settlements SET status='FAILED_RETRYABLE',last_error_code='DISBURSEMENT_TRANSIENT',next_retry_at=clock_timestamp()+(?*interval '1 second') WHERE id=?",Math.min(300,5L*(1L<<Math.min(n(st.get("attempt_count"))+1,6))),settlementId);audit.write(null,"settlement.failed","SETTLEMENT",settlementId.toString(),Map.of(),Map.of("status","FAILED_RETRYABLE"),null);return Map.of("status","FAILED_RETRYABLE");}
  String reference="SD"+st.get("settlement_no").toString().substring(1);
  db.update("INSERT INTO simulated_settlement_disbursements(settlement_no,merchant_id,amount_fen,channel_reference) VALUES (?,?,?,?) ON CONFLICT(settlement_no) DO NOTHING",st.get("settlement_no"),st.get("merchant_id"),st.get("amount_fen"),reference);
  ledger((UUID)st.get("merchant_id"),"SETTLEMENT_DEBIT","DEBIT",n(st.get("amount_fen")),true,null,null,null,null,settlementId,"SETTLEMENT_DISBURSED",null,null);
  UUID debit=(UUID)one("SELECT id FROM merchant_ledger_entries WHERE settlement_id=? AND entry_type='SETTLEMENT_DEBIT'",settlementId).get("id");
  db.update("INSERT INTO settlement_items(settlement_id,ledger_entry_id,signed_amount_fen) VALUES (?,?,?) ON CONFLICT DO NOTHING",settlementId,debit,-n(st.get("amount_fen")));
  db.update("UPDATE settlements SET status='SETTLED',settled_at=clock_timestamp(),channel_reference=?,last_error_code=NULL,next_retry_at=NULL WHERE id=?",reference,settlementId);
  for(var t:db.queryForList("SELECT DISTINCT t.id FROM settlement_tracks t WHERE t.status='PROCESSING' AND EXISTS(SELECT 1 FROM merchant_ledger_entries e JOIN settlement_items i ON i.ledger_entry_id=e.id WHERE i.settlement_id=? AND e.suborder_id=t.suborder_id)",settlementId))
   db.update("UPDATE settlement_tracks SET status='SETTLED',settlement_id=?,version=version+1 WHERE id=?",settlementId,t.get("id"));
  outbox.append("SETTLEMENT",settlementId.toString(),"SettlementCompleted",1,Map.of("settlement_id",settlementId.toString(),"merchant_id",st.get("merchant_id").toString(),"amount_fen",n(st.get("amount_fen"))),null);
  audit.write(null,"settlement.settled","SETTLEMENT",settlementId.toString(),Map.of(),Map.of("amount_fen",n(st.get("amount_fen"))),null);
  return Map.of("status","SETTLED");
 }

 /** Retry sweep for failed disbursements; simulated channel is idempotent per settlement number. */
 public int retryFailed(){
  int count=0;
  for(var st:db.queryForList("SELECT id FROM settlements WHERE status='FAILED_RETRYABLE' AND (next_retry_at IS NULL OR next_retry_at<=clock_timestamp()) ORDER BY created_at,id LIMIT 20")){
   try{tx.executeWithoutResult(s->attemptDisburse((UUID)st.get("id")));count++;}catch(Exception e){org.slf4j.LoggerFactory.getLogger(SettlementService.class).warn("Settlement retry retained: {}",st.get("id"));}
  }
  return count;
 }

 public Map<String,Object> initiate(Actor a,UUID merchantId,String key,String proof,HttpServletRequest r){
  permission(a,"settlement.execute");
  var held=commands.command(a,"settlement.initiate:"+merchantId,key,Map.of("merchant_id",merchantId.toString()),()->{
   auth.consumeProof(a,"settlement.execute",proof);
   one("SELECT id FROM merchant WHERE id=? FOR UPDATE",merchantId);
   // Freeze candidate eligibility under the same track locks used by after-sale and refund writers.
   db.queryForList("SELECT id FROM settlement_tracks WHERE merchant_id=? ORDER BY id FOR UPDATE",merchantId);
   var entries=db.queryForList("SELECT e.* FROM merchant_ledger_entries e WHERE e.merchant_id=? AND e.affects_balance AND NOT EXISTS(SELECT 1 FROM settlement_items i WHERE i.ledger_entry_id=e.id) AND (e.suborder_id IS NULL OR e.entry_type='SETTLEMENT_ADJUSTMENT' OR EXISTS(SELECT 1 FROM settlement_tracks t WHERE t.suborder_id=e.suborder_id AND (t.status='ELIGIBLE' OR (t.status='ADJUSTED' AND t.settlement_id IS NULL)))) ORDER BY e.created_at,e.id",merchantId);
   long sum=0;for(var e:entries)sum+=e.get("direction").equals("CREDIT")?n(e.get("amount_fen")):-n(e.get("amount_fen"));
   if(entries.isEmpty()||sum<1)throw new Failure(409,"NOTHING_TO_SETTLE");
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO settlements(id,settlement_no,merchant_id,status,amount_fen,entry_count,initiated_by) VALUES (?,?,?,'PROCESSING',?,?,?)",id,"S"+id.toString().replace("-",""),merchantId,sum,entries.size(),a.principalId());
   for(var e:entries)db.update("INSERT INTO settlement_items(settlement_id,ledger_entry_id,signed_amount_fen) VALUES (?,?,?)",id,e.get("id"),e.get("direction").equals("CREDIT")?n(e.get("amount_fen")):-n(e.get("amount_fen")));
   for(var t:db.queryForList("SELECT DISTINCT t.id FROM settlement_tracks t WHERE t.status='ELIGIBLE' AND t.merchant_id=? AND EXISTS(SELECT 1 FROM merchant_ledger_entries e JOIN settlement_items i ON i.ledger_entry_id=e.id WHERE i.settlement_id=? AND e.suborder_id=t.suborder_id)",merchantId,id))
    db.update("UPDATE settlement_tracks SET status='PROCESSING',version=version+1 WHERE id=?",t.get("id"));
   var result=attemptDisburse(id);
   audit.write(a,"settlement.initiate","SETTLEMENT",id.toString(),Map.of(),Map.of("amount_fen",sum,"entry_count",entries.size(),"result",result.get("status")),r);
   return Map.of("settlement_id",id.toString());
  });
  return get(a,UUID.fromString(held.get("settlement_id").toString()));
 }

 public Map<String,Object> retry(Actor a,UUID settlementId,String key,String proof,HttpServletRequest r){
  permission(a,"settlement.execute");
  commands.command(a,"settlement.retry:"+settlementId,key,Map.of("settlement_id",settlementId.toString()),()->{
   auth.consumeProof(a,"settlement.execute",proof);
   var st=one("SELECT * FROM settlements WHERE id=?",settlementId);
   if(!st.get("status").equals("FAILED_RETRYABLE"))throw new Failure(409,"SETTLEMENT_STATE_CONFLICT");
   attemptDisburse(settlementId);
   audit.write(a,"settlement.retry","SETTLEMENT",settlementId.toString(),Map.of(),Map.of("requested",true),r);
   return Map.of("settlement_id",settlementId.toString());
  });
  return get(a,settlementId);
 }

 public Map<String,Object> adjust(Actor a,UUID merchantId,Map<String,Object>body,String key,String proof,HttpServletRequest r){
  permission(a,"ledger.adjust");
  if(!Set.of("direction","amount_fen","reason","suborder_id").containsAll(body.keySet())||!Set.of("CREDIT","DEBIT").contains(body.get("direction"))||!(body.get("amount_fen")instanceof Number amount)||amount.longValue()<1||amount.longValue()>9007199254740991L||amount.doubleValue()!=amount.longValue()||!(body.get("reason")instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  UUID sub=body.get("suborder_id")==null?null:UUID.fromString(body.get("suborder_id").toString());
  var held=commands.command(a,"ledger.adjust:"+merchantId,key,body,()->{
   auth.consumeProof(a,"ledger.adjust",proof);
   one("SELECT id FROM merchant WHERE id=? FOR UPDATE",merchantId);
   UUID order=null;
   if(sub!=null){var s=one("SELECT * FROM suborders WHERE id=?",sub);if(!s.get("merchant_id").equals(merchantId))throw new Failure(404,"RESOURCE_NOT_FOUND");order=(UUID)s.get("order_id");}
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,order_id,suborder_id,source_event,reason,created_by_type,created_by) VALUES (?,?,'MANUAL_ADJUSTMENT',?,?,TRUE,?,?, 'MANUAL_ADJUSTMENT',?,'PRINCIPAL',?)",id,merchantId,body.get("direction"),amount.longValue(),order,sub,reason,a.principalId());
   audit.write(a,"ledger.adjust","LEDGER_ENTRY",id.toString(),Map.of(),Map.of("merchant_id",merchantId,"direction",body.get("direction"),"amount_fen",amount.longValue(),"reason",reason),r);
   return Map.of("entry_id",id.toString());
  });
  return view(one("SELECT * FROM merchant_ledger_entries WHERE id=?",UUID.fromString(held.get("entry_id").toString())));
 }

 public Map<String,Object> createCommissionPolicy(Actor a,Map<String,Object>body,String proof,HttpServletRequest r){
  permission(a,"settlement.policy.manage");
  if(!Set.of("name","merchant_id","category","campaign_code","rate_basis_points","priority","effective_from","effective_to").containsAll(body.keySet())||!(body.get("name")instanceof String name)||name.isBlank()||name.length()>160||!(body.get("rate_basis_points")instanceof Number rate)||rate.longValue()<0||rate.longValue()>10000||rate.doubleValue()!=rate.longValue()||!(body.get("effective_from")instanceof String from))throw new Failure(400,"VALIDATION_ERROR");
  UUID merchant=body.get("merchant_id")==null?null:UUID.fromString(body.get("merchant_id").toString());
  String category=body.get("category")==null?null:body.get("category").toString();
  String campaign=body.get("campaign_code")==null?null:body.get("campaign_code").toString();
  long priority=body.get("priority")instanceof Number p?p.longValue():0;
  if(merchant==null&&category==null&&campaign==null)throw new Failure(400,"VALIDATION_ERROR");
  if(category!=null&&(category.isBlank()||category.length()>80))throw new Failure(400,"VALIDATION_ERROR");
  java.time.Instant fromInstant;java.time.Instant toInstant=null;
  try{fromInstant=java.time.Instant.parse(from);if(body.get("effective_to")!=null)toInstant=java.time.Instant.parse(body.get("effective_to").toString());}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}
  if(toInstant!=null&&!toInstant.isAfter(fromInstant))throw new Failure(400,"VALIDATION_ERROR");
  final java.time.Instant effectiveFrom=fromInstant;final java.time.Instant effectiveTo=toInstant;
  return tx.execute(s->{
   auth.consumeProof(a,"settlement.policy.manage",proof);
   if(merchant!=null)one("SELECT id FROM merchant WHERE id=?",merchant);
   int version=db.queryForObject("SELECT coalesce(max(policy_version),0)+1 FROM commission_policies",Integer.class);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO commission_policies(id,name,merchant_id,category,campaign_code,rate_basis_points,priority,effective_from,effective_to,policy_version,created_by) VALUES (?,?,?,?,?,?,?,?,?,?,?)",id,name,merchant,category,campaign,rate.intValue(),(int)priority,Timestamp.from(effectiveFrom),effectiveTo==null?null:Timestamp.from(effectiveTo),version,a.principalId());
   audit.write(a,"settlement.commission-policy.create","COMMISSION_POLICY",id.toString(),Map.of(),Map.of("name",name,"rate_basis_points",rate.longValue(),"policy_version",version),r);
   return view(one("SELECT * FROM commission_policies WHERE id=?",id));
  });
 }

 public Map<String,Object> createSettlementPolicy(Actor a,Map<String,Object>body,String proof,HttpServletRequest r){
  permission(a,"settlement.policy.manage");
  if(!body.keySet().equals(Set.of("buffer_days"))||!(body.get("buffer_days")instanceof Number days)||days.longValue()<0||days.longValue()>90||days.doubleValue()!=days.longValue())throw new Failure(400,"VALIDATION_ERROR");
  return tx.execute(s->{
   auth.consumeProof(a,"settlement.policy.manage",proof);
   int version=db.queryForObject("SELECT coalesce(max(policy_version),0)+1 FROM settlement_policies",Integer.class);
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO settlement_policies(id,buffer_days,policy_version,created_by) VALUES (?,?,?,?)",id,days.intValue(),version,a.principalId());
   audit.write(a,"settlement.buffer-policy.create","SETTLEMENT_POLICY",id.toString(),Map.of(),Map.of("buffer_days",days.longValue(),"policy_version",version),r);
   return view(one("SELECT * FROM settlement_policies WHERE id=?",id));
  });
 }

 public List<Map<String,Object>> commissionPolicies(Actor a){permission(a,"settlement.read");return db.queryForList("SELECT * FROM commission_policies ORDER BY created_at,id").stream().map(this::view).toList();}
 public List<Map<String,Object>> settlementPolicies(Actor a){permission(a,"settlement.read");return db.queryForList("SELECT * FROM settlement_policies ORDER BY policy_version,id").stream().map(this::view).toList();}

 public Map<String,Object> get(Actor a,UUID settlementId){
  var st=one("SELECT * FROM settlements WHERE id=?",settlementId);
  UUID scope=merchantScope(a,"settlement.read");
  if(scope!=null&&!scope.equals(st.get("merchant_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");
  var result=view(st);
  result.put("items",db.queryForList("SELECT i.ledger_entry_id,i.signed_amount_fen,e.entry_type,e.suborder_id,e.source_event FROM settlement_items i JOIN merchant_ledger_entries e ON e.id=i.ledger_entry_id WHERE i.settlement_id=? ORDER BY e.created_at,e.id",settlementId));
  return result;
 }

 public List<Map<String,Object>> listSettlements(Actor a,String status,UUID after,int limit){
  UUID scope=merchantScope(a,"settlement.read");
  if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(status!=null&&!Set.of("PROCESSING","SETTLED","FAILED_RETRYABLE").contains(status))throw new Failure(400,"VALIDATION_ERROR");
  var args=new ArrayList<>();args.add(after);
  String where="WHERE id>?";
  if(scope!=null){where+=" AND merchant_id=?";args.add(scope);}
  if(status!=null){where+=" AND status=?";args.add(status);}
  args.add(limit+1);
  return db.queryForList("SELECT * FROM settlements "+where+" ORDER BY id LIMIT ?",args.toArray()).stream().map(this::view).toList();
 }

 public List<Map<String,Object>> listTracks(Actor a,String status,UUID after,int limit){
  UUID scope=merchantScope(a,"settlement.read");
  if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(status!=null&&!Set.of("WAITING_RECEIPT","BUFFERING","FROZEN","ELIGIBLE","PROCESSING","SETTLED","ADJUSTED").contains(status))throw new Failure(400,"VALIDATION_ERROR");
  var args=new ArrayList<>();args.add(after);
  String where="WHERE id>?";
  if(scope!=null){where+=" AND merchant_id=?";args.add(scope);}
  if(status!=null){where+=" AND status=?";args.add(status);}
  args.add(limit+1);
  return db.queryForList("SELECT t.*,(SELECT coalesce(sum(CASE WHEN e.direction='CREDIT' THEN e.amount_fen ELSE -e.amount_fen END),0) FROM merchant_ledger_entries e WHERE e.suborder_id=t.suborder_id AND e.affects_balance) net_fen FROM settlement_tracks t "+where+" ORDER BY t.id LIMIT ?",args.toArray()).stream().map(this::view).toList();
 }

 public List<Map<String,Object>> listEntries(Actor a,UUID merchantId,String type,UUID after,int limit){
  UUID scope=merchantScope(a,"ledger.read");
  UUID merchant=scope!=null?scope:merchantId;
  if(merchant==null)throw new Failure(400,"VALIDATION_ERROR");
  if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(type!=null&&!Set.of("SALE_CREDIT","COMMISSION_DEBIT","REFUND_DEBIT","COMMISSION_REVERSAL","SHIPPING_ADJUSTMENT","SETTLEMENT_DEBIT","SETTLEMENT_ADJUSTMENT","MANUAL_ADJUSTMENT").contains(type))throw new Failure(400,"VALIDATION_ERROR");
  var args=new ArrayList<>();args.add(merchant);args.add(after);
  String where="WHERE merchant_id=? AND id>?";
  if(type!=null){where+=" AND entry_type=?";args.add(type);}
  args.add(limit+1);
  return db.queryForList("SELECT * FROM merchant_ledger_entries "+where+" ORDER BY id LIMIT ?",args.toArray()).stream().map(this::view).toList();
 }

 public Map<String,Object> summary(Actor a,UUID merchantId){
  UUID scope=merchantScope(a,"settlement.read");
  UUID merchant=scope!=null?scope:merchantId;
  if(merchant==null)throw new Failure(400,"VALIDATION_ERROR");
  one("SELECT id FROM merchant WHERE id=?",merchant);
  long balance=db.queryForObject("SELECT coalesce(sum(CASE WHEN direction='CREDIT' THEN amount_fen ELSE -amount_fen END),0) FROM merchant_ledger_entries WHERE merchant_id=? AND affects_balance",Long.class,merchant);
  long eligible=db.queryForObject("SELECT coalesce(sum(CASE WHEN e.direction='CREDIT' THEN e.amount_fen ELSE -e.amount_fen END),0) FROM merchant_ledger_entries e JOIN settlement_tracks t ON t.suborder_id=e.suborder_id WHERE e.merchant_id=? AND e.affects_balance AND t.status='ELIGIBLE' AND NOT EXISTS(SELECT 1 FROM settlement_items i WHERE i.ledger_entry_id=e.id)",Long.class,merchant);
  long buffering=db.queryForObject("SELECT coalesce(sum(CASE WHEN e.direction='CREDIT' THEN e.amount_fen ELSE -e.amount_fen END),0) FROM merchant_ledger_entries e JOIN settlement_tracks t ON t.suborder_id=e.suborder_id WHERE e.merchant_id=? AND e.affects_balance AND t.status IN ('WAITING_RECEIPT','BUFFERING','FROZEN') AND NOT EXISTS(SELECT 1 FROM settlement_items i WHERE i.ledger_entry_id=e.id)",Long.class,merchant);
  long inFlight=db.queryForObject("SELECT coalesce(sum(CASE WHEN e.direction='CREDIT' THEN e.amount_fen ELSE -e.amount_fen END),0) FROM merchant_ledger_entries e JOIN settlement_items i ON i.ledger_entry_id=e.id JOIN settlements s ON s.id=i.settlement_id WHERE e.merchant_id=? AND s.status IN ('PROCESSING','FAILED_RETRYABLE') AND e.entry_type<>'SETTLEMENT_DEBIT'",Long.class,merchant);
  long settledTotal=db.queryForObject("SELECT coalesce(sum(amount_fen),0) FROM settlements WHERE merchant_id=? AND status='SETTLED'",Long.class,merchant);
  var result=new LinkedHashMap<String,Object>();
  result.put("merchant_id",merchant);result.put("balance_fen",balance);result.put("eligible_fen",eligible);result.put("buffering_fen",buffering);result.put("in_flight_fen",inFlight);result.put("settled_total_fen",settledTotal);result.put("receivable_fen",Math.max(0,-balance));
  return result;
 }

 /** Reconciliation gate: ledger sums must agree with payment, refund, commission and settlement facts. */
 public Map<String,Object> reconcile(Actor a){
  permission(a,"settlement.read");
  var checks=new ArrayList<Map<String,Object>>();
  checks.add(check("sale_credit_conservation","SELECT count(*) FROM suborders s JOIN payments p ON p.order_id=s.order_id AND p.status='SUCCEEDED' WHERE s.payable_amount_fen>0 AND s.payable_amount_fen<>coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.suborder_id=s.id AND e.entry_type='SALE_CREDIT'),0)"));
  checks.add(check("commission_conservation","SELECT count(*) FROM commission_allocations c WHERE c.commission_fen<>coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.order_item_id=c.order_item_id AND e.entry_type='COMMISSION_DEBIT'),0)"));
  checks.add(check("refund_conservation","SELECT count(*) FROM refunds r WHERE r.status='SUCCEEDED' AND r.amount_fen<>coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.refund_id=r.id AND e.entry_type='REFUND_DEBIT'),0)+coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.refund_id=r.id AND e.entry_type='SHIPPING_ADJUSTMENT'),0)"));
  checks.add(check("reversal_bound","SELECT count(*) FROM commission_allocations c WHERE c.commission_fen<(SELECT coalesce(sum(e.amount_fen),0) FROM merchant_ledger_entries e WHERE e.order_item_id=c.order_item_id AND e.entry_type='COMMISSION_REVERSAL')"));
  checks.add(check("settlement_conservation","SELECT count(*) FROM settlements s WHERE s.status='SETTLED' AND (SELECT coalesce(sum(i.signed_amount_fen),0) FROM settlement_items i WHERE i.settlement_id=s.id)<>0"));
  checks.add(check("settlement_debit_match","SELECT count(*) FROM settlements s WHERE s.status='SETTLED' AND s.amount_fen<>coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.settlement_id=s.id AND e.entry_type='SETTLEMENT_DEBIT'),0)"));
  checks.add(check("settled_track_consumption","SELECT count(*) FROM settlement_tracks t WHERE t.status='SETTLED' AND EXISTS(SELECT 1 FROM merchant_ledger_entries e WHERE e.suborder_id=t.suborder_id AND e.affects_balance AND e.entry_type<>'SETTLEMENT_ADJUSTMENT' AND NOT EXISTS(SELECT 1 FROM settlement_items i WHERE i.ledger_entry_id=e.id))"));
  boolean consistent=checks.stream().allMatch(c->((Number)c.get("mismatches")).longValue()==0);
  return Map.of("consistent",consistent,"checks",checks,"generated_at",clock.instant().toString());
 }
 private Map<String,Object> check(String name,String mismatchSql){return Map.of("name",name,"mismatches",db.queryForObject(mismatchSql,Integer.class));}
}
