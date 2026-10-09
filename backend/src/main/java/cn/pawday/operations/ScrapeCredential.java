package cn.pawday.operations;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** A machine credential restricted to one read-only endpoint; no business identity. */
@Component
public final class ScrapeCredential {
    public enum Principal { METRICS }
    private final byte[] expected;
    public ScrapeCredential(@Value("${pawday.operations.scrape-token:}") String token) {
        if (!token.isEmpty() && !token.matches("[A-Za-z0-9_-]{43,128}"))
            throw new IllegalArgumentException("INVALID_METRICS_CREDENTIAL");
        expected=token.isEmpty()?null:token.getBytes(StandardCharsets.UTF_8);
    }
    public boolean accepts(String path,String header) {
        return expected!=null && "/actuator/prometheus".equals(path) && header!=null && header.startsWith("Bearer ")
            && MessageDigest.isEqual(expected,header.substring(7).getBytes(StandardCharsets.UTF_8));
    }
}
