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
 public boolean refund(String no,Result r){outside();db.update("INSERT INTO simulated_payment_refunds(refund_no,transaction_id,amount_fen,currency,status) VALUES (?,?,?,?,'SUCCEEDED') ON CONFLICT DO NOTHING",no,r.transactionId(),r.amountFen(),r.currency());return db.queryForObject("SELECT count(*) FROM simulated_payment_refunds WHERE refund_no=? AND transaction_id=? AND amount_fen=? AND currency=?",Integer.class,no,r.transactionId(),r.amountFen(),r.currency())==1;}
}
