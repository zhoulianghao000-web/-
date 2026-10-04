package cn.pawday.outbox;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
@Component
public class DeliveryPolicy {
    public final int maxAttempts;public final long baseMillis,maxMillis,leaseMillis,confirmMillis;
    public DeliveryPolicy(@Value("${pawday.outbox.max-attempts:5}") int attempts,@Value("${pawday.outbox.retry-base-ms:1000}") long base,
        @Value("${pawday.outbox.retry-max-ms:60000}") long max,@Value("${pawday.outbox.lease-ms:30000}") long lease,@Value("${pawday.outbox.confirm-timeout-ms:3000}") long confirm) {
        if(attempts<1 || attempts>20 || base<1 || max<base || confirm<1 || lease<confirm+1000) throw new IllegalArgumentException("Invalid delivery policy");
        maxAttempts=attempts;baseMillis=base;maxMillis=max;leaseMillis=lease;confirmMillis=confirm;
    }
    public long backoff(int attempt){return Math.min(maxMillis,baseMillis*(1L<<Math.min(20,Math.max(0,attempt-1))));}
}
