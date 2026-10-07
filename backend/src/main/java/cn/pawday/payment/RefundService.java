package cn.pawday.payment;

import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.util.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** Original-route refunds bound to the actually collected attempt. Channel I/O stays outside business transactions. */
@Service public class RefundService {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final ObjectProvider<PaymentGateway> gateways;private final OutboxWriter outbox;private final AuditWriter audit;private final cn.pawday.settlement.SettlementService settlement;private final cn.pawday.points.PointsService points;private final Clock clock;
 public RefundService(JdbcTemplate db,TransactionTemplate tx,ObjectProvider<PaymentGateway> gateways,OutboxWriter outbox,AuditWriter audit,cn.pawday.settlement.SettlementService settlement,cn.pawday.points.PointsService points,Clock clock){this.db=db;this.tx=tx;this.gateways=gateways;this.outbox=outbox;this.audit=audit;this.settlement=settlement;this.points=points;this.clock=clock;}
 private PaymentGateway gateway(){var g=gateways.getIfAvailable();if(g==null)throw new Failure(503,"PAYMENT_PROVIDER_UNAVAILABLE");return g;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->v.put(k,x instanceof Timestamp t?t.toInstant().toString():x));return v;}

 /** Created inside the caller's business transaction so acceptance and refund intent commit or roll back together. */
 public UUID createIntent(UUID paymentId,UUID cancellationId,UUID aftersaleId,long amountFen){
  if(amountFen<1)return null;
  var payment=one("SELECT * FROM payments WHERE id=? FOR UPDATE",paymentId);
  if(!payment.get("status").equals("SUCCEEDED")||payment.get("successful_attempt_id")==null)throw new Failure(409,"PAYMENT_NOT_REFUNDABLE");
  UUID id=UUID.randomUUID();
  db.update("INSERT INTO refunds(id,refund_no,payment_id,payment_attempt_id,cancellation_id,aftersale_id,amount_fen) VALUES (?,?,?,?,?,?,?)",id,"R"+id.toString().replace("-",""),paymentId,payment.get("successful_attempt_id"),cancellationId,aftersaleId,amountFen);
  return id;
 }
 public void dueForPayment(UUID paymentId){for(var r:db.queryForList("SELECT id FROM refunds WHERE payment_id=? AND status IN ('CREATED','PROCESSING','FAILED_RETRYABLE') AND (next_retry_at IS NULL OR next_retry_at<=clock_timestamp()) ORDER BY created_at,id",paymentId))drive((UUID)r.get("id"));}
 public int recoverBatch(){if(gateways.getIfAvailable()==null)return 0;int count=0;for(var r:db.queryForList("SELECT id FROM refunds WHERE status IN ('CREATED','PROCESSING','FAILED_RETRYABLE') AND (next_retry_at IS NULL OR next_retry_at<=clock_timestamp()) ORDER BY created_at,id LIMIT 50")){try{drive((UUID)r.get("id"));count++;}catch(Exception e){org.slf4j.LoggerFactory.getLogger(RefundService.class).warn("Refund recovery retained for retry: {}",r.get("id"));}}return count;}
 public void drive(UUID id){
  var held=tx.execute(s->{var rows=db.queryForList("SELECT * FROM refunds WHERE id=? AND status IN ('CREATED','PROCESSING','FAILED_RETRYABLE') FOR UPDATE",id);if(rows.isEmpty())return null;var r=rows.getFirst();
   if(r.get("status").equals("PROCESSING")&&r.get("next_retry_at")!=null&&((Timestamp)r.get("next_retry_at")).toInstant().isAfter(clock.instant()))return null;
   db.update("UPDATE refunds SET status='PROCESSING',attempt_count=attempt_count+1,last_error_code=NULL,next_retry_at=NULL WHERE id=?",id);
   return one("SELECT r.*,p.currency FROM refunds r JOIN payments p ON p.id=r.payment_id WHERE r.id=?",id);});
  if(held==null)return;
  PaymentGateway.RefundOutcome outcome;
  try{var receipt=one("SELECT provider,channel_transaction_id FROM payment_receipts WHERE attempt_id=?",held.get("payment_attempt_id"));
   outcome=gateway().refund(new PaymentGateway.RefundInstruction(held.get("refund_no").toString(),receipt.get("provider").toString(),receipt.get("channel_transaction_id").toString(),n(held.get("amount_fen")),held.get("currency").toString()));
  }catch(Exception e){outcome=new PaymentGateway.RefundOutcome("UNKNOWN",null,"PROVIDER_UNAVAILABLE");}
  if(outcome.status().equals("NOT_FOUND")||outcome.status()==null)outcome=new PaymentGateway.RefundOutcome("UNKNOWN",null,outcome.errorCode());
  settle(id,outcome);
 }
 private long backoff(int attempts){return Math.min(300,5L*(1L<<Math.min(Math.max(attempts,1),6)));}
 private void settle(UUID id,PaymentGateway.RefundOutcome o){
  tx.executeWithoutResult(s->{var rows=db.queryForList("SELECT * FROM refunds WHERE id=? AND status='PROCESSING' FOR UPDATE",id);if(rows.isEmpty())return;var r=rows.getFirst();long amount=n(r.get("amount_fen"));int attempts=((Number)r.get("attempt_count")).intValue();
   if(o.status().equals("SUCCEEDED")){
    if(o.channelRefundNo()==null||o.channelRefundNo().isBlank())throw new Failure(409,"INVALID_PROVIDER_RECEIPT");
    db.update("UPDATE refunds SET status='SUCCEEDED',channel_refund_no=?,decided_at=clock_timestamp(),next_retry_at=NULL,last_error_code=NULL WHERE id=?",o.channelRefundNo(),id);
    db.update("UPDATE order_refund_unit_claims SET status='REFUNDED' WHERE refund_id=? AND status='RESERVED'",id);
    if(r.get("cancellation_id")!=null)completeCancellation((UUID)r.get("cancellation_id"),id);else completeAftersale((UUID)r.get("aftersale_id"),id);
    settlement.recordRefundSuccess(id);
    points.recordRefundSuccess(id);
    if(r.get("aftersale_id")!=null)settlement.unfreezeIfClear((UUID)one("SELECT suborder_id FROM aftersales WHERE id=?",r.get("aftersale_id")).get("suborder_id"));
    outbox.append("PAYMENT",r.get("payment_id").toString(),"RefundSucceeded",1,Map.of("refund_id",id.toString(),"amount_fen",amount),null);
    audit.write(null,"refund.succeeded","REFUND",id.toString(),Map.of(),Map.of("amount_fen",amount),null);
   }else if(o.status().equals("FAILED")){
    boolean fin=attempts>=8;
    db.update("UPDATE refunds SET status=?,last_error_code=?,next_retry_at=CASE WHEN ? THEN NULL ELSE clock_timestamp()+(?*interval '1 second') END WHERE id=?",fin?"FAILED_FINAL":"FAILED_RETRYABLE",o.errorCode(),fin,backoff(attempts),id);
    outbox.append("PAYMENT",r.get("payment_id").toString(),"RefundFailed",1,Map.of("refund_id",id.toString(),"final",fin),null);
    audit.write(null,"refund.failed","REFUND",id.toString(),Map.of(),Map.of("status",fin?"FAILED_FINAL":"FAILED_RETRYABLE","error_code",o.errorCode()==null?"":o.errorCode()),null);
   }else db.update("UPDATE refunds SET next_retry_at=clock_timestamp()+(?*interval '1 second'),last_error_code=? WHERE id=?",backoff(attempts),o.errorCode(),id);});
 }
 /** Refund success only settles money and completes the source document; quantities and stock are never replayed. */
 private void completeCancellation(UUID cid,UUID refundId){
  var c=one("SELECT * FROM order_cancellations WHERE id=? FOR UPDATE",cid);
  db.update("UPDATE order_cancellations SET status='COMPLETED',version=version+1 WHERE id=?",cid);
  db.update("INSERT INTO order_cancellation_events(id,cancellation_id,from_status,to_status,reason_code) VALUES (?,?,?,'COMPLETED',?)",UUID.randomUUID(),cid,c.get("status"),c.get("reason_code"));
  returnCoupons(cid,(UUID)c.get("order_id"));
  outbox.append("ORDER",c.get("order_id").toString(),"CancellationCompleted",1,Map.of("cancellation_id",cid.toString(),"refund_id",refundId.toString()),null);
  audit.write(null,"cancellation.completed","ORDER_CANCELLATION",cid.toString(),Map.of("status",c.get("status")),Map.of("status","COMPLETED"),null);
 }
 private void completeAftersale(UUID aid,UUID refundId){
  var a=one("SELECT status FROM aftersales WHERE id=? FOR UPDATE",aid);
  db.update("UPDATE aftersales SET status='COMPLETED',version=version+1 WHERE id=?",aid);
  db.update("INSERT INTO aftersale_events(id,aftersale_id,from_status,to_status,actor_type,reason) VALUES (?,?,?,'COMPLETED','SYSTEM','REFUND_SUCCEEDED')",UUID.randomUUID(),aid,a.get("status"));
  outbox.append("AFTERSALE",aid.toString(),"AfterSaleCompleted",1,Map.of("aftersale_id",aid.toString(),"refund_id",refundId.toString()),null);
  audit.write(null,"aftersale.completed","AFTERSALE",aid.toString(),Map.of("status",a.get("status")),Map.of("status","COMPLETED"),null);
 }
 /** Whole discount scope cancelled and every original refund finished: return the coupon once per its frozen snapshot. */
 public void returnCoupons(UUID cancellationId,UUID orderId){
  UUID payment=(UUID)one("SELECT id FROM payments WHERE order_id=?",orderId).get("id");
  long open=db.queryForObject("SELECT count(*) FROM refunds WHERE payment_id=? AND status IN ('CREATED','PROCESSING','FAILED_RETRYABLE')",Integer.class,payment);
  for(var snap:db.queryForList("SELECT coupon_id FROM order_coupon_snapshots WHERE order_id=? ORDER BY coupon_id",orderId)){
   UUID cid=(UUID)snap.get("coupon_id");var coupon=one("SELECT * FROM user_coupons WHERE id=? FOR UPDATE",cid);
   if(!coupon.get("status").equals("USED")||open>0)continue;
   UUID merchant=(UUID)coupon.get("merchant_id");
   long remaining=merchant==null?db.queryForObject("SELECT count(*) FROM order_items i JOIN suborders s ON s.id=i.suborder_id WHERE s.order_id=? AND i.quantity>i.cancelled_qty",Integer.class,orderId):db.queryForObject("SELECT count(*) FROM order_items i JOIN suborders s ON s.id=i.suborder_id WHERE s.order_id=? AND i.merchant_id=? AND i.quantity>i.cancelled_qty",Integer.class,orderId,merchant);
   if(remaining>0)continue;
   String target=((Timestamp)coupon.get("expires_at")).toInstant().isAfter(clock.instant())?"RETURNED":"EXPIRED";
   db.update("INSERT INTO coupon_return_events(id,coupon_id,order_id,cancellation_id,resulting_status) VALUES (?,?,?,?,?)",UUID.randomUUID(),cid,orderId,cancellationId,target);
   db.update("UPDATE user_coupons SET status=?,version=version+1 WHERE id=?",target,cid);
   outbox.append("ORDER",orderId.toString(),"CouponReturned",1,Map.of("coupon_id",cid.toString(),"resulting_status",target),null);
   audit.write(null,"coupon.return","USER_COUPON",cid.toString(),Map.of("status","USED"),Map.of("status",target),null);
  }
 }
 public Map<String,Object> refundView(UUID id){var r=view(one("SELECT r.*,p.order_id,p.currency FROM refunds r JOIN payments p ON p.id=r.payment_id WHERE r.id=?",id));return r;}
 public List<Map<String,Object>> list(Actor a,String status,UUID after,int limit){
  if(a.realm()!=Actor.Realm.ADMIN||!a.permissions().contains("payment.read"))throw new Failure(403,"PERMISSION_DENIED");
  if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(status!=null&&!Set.of("CREATED","PROCESSING","SUCCEEDED","FAILED_RETRYABLE","FAILED_FINAL","CANCELLED").contains(status))throw new Failure(400,"VALIDATION_ERROR");
  return db.queryForList("SELECT r.*,p.order_id,p.currency FROM refunds r JOIN payments p ON p.id=r.payment_id WHERE r.id>? "+(status==null?"":"AND r.status=?")+" ORDER BY r.id LIMIT ?",status==null?new Object[]{after,limit+1}:new Object[]{after,status,limit+1}).stream().map(this::view).toList();
 }
}
