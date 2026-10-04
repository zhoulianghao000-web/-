package cn.pawday.outbox;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import tools.jackson.databind.json.JsonMapper;

@Component
public class OutboxWriter {
    private final JdbcTemplate db;private final JsonMapper json=JsonMapper.builder().build();
    public OutboxWriter(JdbcTemplate db){this.db=db;}
    public UUID append(String aggregateType,String aggregateId,String type,int version,Map<String,?> payload,String correlation) {
        UUID id=UUID.randomUUID();insert(id,id,"EVENT",aggregateType,aggregateId,type,version,payload,correlation,1,0,0);return id;
    }
    public void insert(UUID id,UUID root,String kind,String aggregateType,String aggregateId,String type,int version,Map<String,?> payload,String correlation,int attempt,int generation,long delayMillis) {
        if(!TransactionSynchronizationManager.isActualTransactionActive() || db.getDataSource()==null || !TransactionSynchronizationManager.hasResource(db.getDataSource()))
            throw new IllegalStateException("OutboxWriter requires the business PostgreSQL transaction bound to this DataSource");
        db.update("""
            INSERT INTO outbox_event(id,root_event_id,transport_kind,aggregate_type,aggregate_id,event_type,event_version,payload,correlation_id,delivery_attempt,generation,available_at)
            VALUES (?,?,?,?,?,?,?,?::jsonb,?,?,?,clock_timestamp()+(? * interval '1 millisecond'))
            """,id,root,kind,aggregateType,aggregateId,type,version,json.writeValueAsString(payload),correlation,attempt,generation,delayMillis);
    }
    public void deadLetter(UUID root,String stage,String code,int generation) {
        insert(UUID.randomUUID(),root,"DEAD_LETTER","DELIVERY",root.toString(),"delivery.dead",1,
            Map.of("original_event_id",root.toString(),"stage",stage,"reason_code",code),null,1,generation,0);
    }
}
