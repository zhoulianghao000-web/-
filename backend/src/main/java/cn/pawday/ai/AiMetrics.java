package cn.pawday.ai;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class AiMetrics {
 public AiMetrics(MeterRegistry metrics,JdbcTemplate db){
  for(String state:List.of("RESERVED","CONSUMED","RELEASED"))metrics.gauge("pawday.ai.quota.requests",io.micrometer.core.instrument.Tags.of("state",state),db,j->j.queryForObject("SELECT count(*) FROM ai_quota_reservations WHERE status=?",Long.class,state));
  metrics.gauge("pawday.ai.quota.expired.leases",db,j->j.queryForObject("SELECT count(*) FROM ai_quota_reservations WHERE status='RESERVED' AND lease_expires_at<=now()",Long.class));
 }
}
