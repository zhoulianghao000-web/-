package cn.pawday.checkout;
import java.sql.Timestamp;
import java.time.Clock;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component
public class QuoteExpiryWorker {
 private final JdbcTemplate db;private final Clock clock;private final boolean enabled;
 public QuoteExpiryWorker(JdbcTemplate db,Clock clock,@Value("${pawday.checkout.expiry-enabled:true}")boolean enabled){this.db=db;this.clock=clock;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.checkout.expiry-ms:30000}") public void expire(){if(!enabled)return;try{
  db.update("UPDATE pricing_quotes SET status='EXPIRED',version=version+1 WHERE id IN (SELECT id FROM pricing_quotes WHERE status='ACTIVE' AND expires_at<=? ORDER BY expires_at LIMIT 100 FOR UPDATE SKIP LOCKED)",Timestamp.from(clock.instant()));
 }catch(org.springframework.dao.DataAccessException unavailable){/* Durable active rows are retried on the next sweep. */}}
}
