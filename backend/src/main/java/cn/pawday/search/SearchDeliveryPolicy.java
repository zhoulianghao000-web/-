package cn.pawday.search;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchDeliveryPolicy {
    public final int maxAttempts;public final long baseMs,leaseMs;
    public SearchDeliveryPolicy(@Value("${pawday.search.retry-max-attempts:5}") int max,@Value("${pawday.search.retry-base-ms:1000}") long base,@Value("${pawday.search.lease-ms:30000}") long lease) {
        if(max<1 || max>20 || base<1 || base>60000 || lease<1000)throw new IllegalArgumentException("Invalid search retry policy");maxAttempts=max;baseMs=base;leaseMs=lease;
    }
    public long backoff(int attempt){return Math.min(60000,baseMs*(1L<<Math.min(20,Math.max(0,attempt-1))));}
}
