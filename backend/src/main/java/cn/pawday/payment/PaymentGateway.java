package cn.pawday.payment;
import java.util.UUID;
/** Channel I/O must execute outside the PostgreSQL business transaction. */
public interface PaymentGateway {
 record Request(UUID attemptId,String attemptNo,String channel,long amountFen,String currency){}
 record Result(String status,String provider,String transactionId,long amountFen,String currency){}
 /** One idempotent refund instruction bound to an actually collected transaction. */
 record RefundInstruction(String refundNo,String provider,String transactionId,long amountFen,String currency){}
 /** SUCCEEDED / FAILED / UNKNOWN; UNKNOWN keeps the refund eligible for controlled retry. */
 record RefundOutcome(String status,String channelRefundNo,String errorCode){}
 Result start(Request request);
 Result query(Request request);
 Result close(Request request);
 RefundOutcome refund(RefundInstruction instruction);
 RefundOutcome queryRefund(String refundNo);
}
