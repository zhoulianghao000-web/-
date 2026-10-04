package cn.pawday.outbox;
import java.util.Map;
import java.util.UUID;
public record EventEnvelope(UUID event_id,String event_type,int event_version,String aggregate_type,String aggregate_id,
    String correlation_id,int delivery_attempt,int generation,Map<String,Object> payload) {}
