package cn.pawday.outbox;
import io.micrometer.core.instrument.*;
import org.springframework.stereotype.Component;
@Component
public class OutboxMetrics {
    public OutboxMetrics(MeterRegistry registry,OutboxOperations operations) {
        for(String status:java.util.List.of("PENDING","PUBLISHING","PUBLISHED","FAILED_RETRYABLE","DEAD"))
            Gauge.builder("pawday.outbox.events",operations,o->o.count("SELECT count(*) FROM outbox_event WHERE status='"+status+"'")).tag("status",status).register(registry);
        Gauge.builder("pawday.outbox.backlog",operations,o->((Number)o.stats().get("backlog")).doubleValue()).register(registry);
        Gauge.builder("pawday.outbox.oldest.age.seconds",operations,o->((Number)o.stats().get("oldest_event_age_seconds")).doubleValue()).register(registry);
        Gauge.builder("pawday.inbox.dead",operations,o->o.count("SELECT count(*) FROM processed_event WHERE status='DEAD'")).register(registry);
        Gauge.builder("pawday.sms.dead",operations,o->o.count("SELECT count(*) FROM sms_delivery WHERE status='DEAD'")).register(registry);
    }
}
