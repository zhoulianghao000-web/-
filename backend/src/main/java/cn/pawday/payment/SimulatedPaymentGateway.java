package cn.pawday.payment;
import cn.pawday.common.Api.Failure;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;
@org.springframework.context.annotation.Profile("!production")
@Component @ConditionalOnProperty(name="pawday.payment.simulation-enabled",havingValue="true")
public class SimulatedPaymentGateway implements PaymentGateway {
 private final JdbcTemplate db;
 public SimulatedPaymentGateway(JdbcTemplate db){this.db=db;}
 private void outside(){if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Payment I/O inside business transaction");}
 public Result start(Request r){outside();db.update("INSERT INTO simulated_payment_transactions(attempt_no,channel,amount_fen,currency,status) VALUES (?,?,?,?,'PENDING') ON CONFLICT DO NOTHING",r.attemptNo(),r.channel(),r.amountFen(),r.currency());return query(r);}
 public Result query(Request r){outside();var rows=db.queryForList("SELECT * FROM simulated_payment_transactions WHERE attempt_no=?",r.attemptNo());if(rows.isEmpty())return new Result("NOT_FOUND","SIMULATED_"+r.channel(),null,0,r.currency());var x=rows.getFirst();return new Result(x.get("status").toString(),"SIMULATED_"+r.channel(),(String)x.get("transaction_id"),((Number)x.get("amount_fen")).longValue(),x.get("currency").toString());}
 public Result close(Request r){outside();db.update("INSERT INTO simulated_payment_transactions(attempt_no,channel,amount_fen,currency,status) VALUES (?,?,?,?,'CLOSED') ON CONFLICT DO NOTHING",r.attemptNo(),r.channel(),r.amountFen(),r.currency());db.update("UPDATE simulated_payment_transactions SET status='CLOSED',updated_at=clock_timestamp() WHERE attempt_no=? AND status='PENDING'",r.attemptNo());return query(r);}
 /** Development channel controls; callers still confirm by server query. */
 public void outcome(Request r,String status){outside();if(!Set.of("SUCCEEDED","FAILED","UNKNOWN").contains(status))throw new Failure(400,"VALIDATION_ERROR");db.update("UPDATE simulated_payment_transactions SET status=?,transaction_id=CASE WHEN ?='SUCCEEDED' THEN coalesce(transaction_id,?) ELSE transaction_id END,updated_at=clock_timestamp() WHERE attempt_no=? AND status IN ('PENDING','UNKNOWN')",status,status,"SIM-"+r.attemptNo(),r.attemptNo());}
 /** Several partial refunds may share one collected transaction; the same refund_no never double-refunds. */
 public RefundOutcome refund(RefundInstruction i){outside();
  var directive=db.queryForList("SELECT outcome FROM simulated_refund_directives WHERE refund_no=?",i.refundNo());
  if(!directive.isEmpty()&&directive.getFirst().get("outcome").equals("FAIL_TRANSIENT"))return new RefundOutcome("UNKNOWN",null,"SIMULATED_TRANSIENT");
  if(!directive.isEmpty()&&directive.getFirst().get("outcome").equals("FAIL_FINAL"))return new RefundOutcome("FAILED",null,"SIMULATED_FINAL");
  if(!db.queryForList("SELECT refund_no FROM simulated_payment_refund_requests WHERE refund_no=?",i.refundNo()).isEmpty())return queryRefund(i.refundNo());
  var collected=db.queryForList("SELECT amount_fen,currency FROM simulated_payment_transactions WHERE transaction_id=? AND status='SUCCEEDED'",i.transactionId());
  if(collected.isEmpty())return new RefundOutcome("FAILED",null,"SIMULATED_NOT_COLLECTED");
  long cap=((Number)collected.getFirst().get("amount_fen")).longValue();
  if(!collected.getFirst().get("currency").equals(i.currency()))return new RefundOutcome("FAILED",null,"SIMULATED_CURRENCY");
  Long used=db.queryForObject("SELECT (SELECT coalesce(sum(amount_fen),0) FROM simulated_payment_refund_requests WHERE transaction_id=?)+(SELECT coalesce(sum(amount_fen),0) FROM simulated_payment_refunds WHERE transaction_id=?)",Long.class,i.transactionId(),i.transactionId());
  if(used==null)used=0L;
  if(used+i.amountFen()>cap)return new RefundOutcome("FAILED",null,"SIMULATED_EXCEEDS_COLLECTION");
  db.update("INSERT INTO simulated_payment_refund_requests(refund_no,transaction_id,amount_fen,currency,status,channel_refund_no) VALUES (?,?,?,?,'SUCCEEDED',?) ON CONFLICT (refund_no) DO NOTHING",i.refundNo(),i.transactionId(),i.amountFen(),i.currency(),"SIMR-"+i.refundNo());
  return queryRefund(i.refundNo());
 }
 public RefundOutcome queryRefund(String refundNo){outside();var rows=db.queryForList("SELECT * FROM simulated_payment_refund_requests WHERE refund_no=?",refundNo);if(rows.isEmpty())return new RefundOutcome("NOT_FOUND",null,null);var x=rows.getFirst();return new RefundOutcome(x.get("status").toString(),x.get("channel_refund_no").toString(),null);}
}
