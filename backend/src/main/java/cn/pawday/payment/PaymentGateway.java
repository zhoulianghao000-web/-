package cn.pawday.payment;
import java.util.UUID;
/** Channel I/O must execute outside the PostgreSQL business transaction. */
public interface PaymentGateway {
 record Request(UUID attemptId,String attemptNo,String channel,long amountFen,String currency){}
 record Result(String status,String provider,String transactionId,long amountFen,String currency){}
 Result start(Request request);
 Result query(Request request);
 Result close(Request request);
 boolean refund(String refundNo,Result collected);
}
