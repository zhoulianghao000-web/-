package cn.pawday.search;
import cn.pawday.identity.Crypto;
import cn.pawday.outbox.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import tools.jackson.databind.json.JsonMapper;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchInboxConsumer {
    public static final String CONSUMER="search-product-v1";
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OutboxWriter writer;private final DeliveryPolicy policy;private final Crypto crypto;
    private final JsonMapper json=JsonMapper.builder().build();
    public SearchInboxConsumer(JdbcTemplate db,TransactionTemplate tx,OutboxWriter writer,DeliveryPolicy policy,Crypto crypto){this.db=db;this.tx=tx;this.writer=writer;this.policy=policy;this.crypto=crypto;}
    public void process(EventEnvelope event) {
        if(event.event_id()==null || event.event_type()==null || event.event_type().isBlank() || event.event_version()<1 || event.aggregate_type()==null || event.aggregate_id()==null || event.payload()==null || event.delivery_attempt()<1 || event.generation()<0)throw new IllegalArgumentException("Invalid envelope");
        String hash=crypto.hash(json.writeValueAsString(List.of(event.event_type(),event.event_version(),event.aggregate_type(),event.aggregate_id(),new TreeMap<>(event.payload()))));
        tx.executeWithoutResult(status->{
            var roots=db.queryForList("SELECT generation FROM outbox_event WHERE id=?",event.event_id());
            if(!roots.isEmpty() && event.generation()!=((Number)roots.getFirst().get("generation")).intValue())return;
            db.update("INSERT INTO processed_event(consumer,event_id,status,payload_hash,generation) VALUES (?,?,'FAILED_RETRYABLE',?,?) ON CONFLICT DO NOTHING",CONSUMER,event.event_id(),hash,event.generation());
            var row=db.queryForMap("SELECT * FROM processed_event WHERE consumer=? AND event_id=? FOR UPDATE",CONSUMER,event.event_id());
            if(!hash.equals(row.get("payload_hash")))throw new IllegalArgumentException("Event identity payload conflict");
            if(row.get("status").equals("PROCESSED") || row.get("status").equals("DEAD"))return;
            int attempt=((Number)row.get("attempt_count")).intValue()+1;
            if(event.delivery_attempt()!=attempt || event.generation()!=((Number)row.get("generation")).intValue())return;
            Object savepoint=status.createSavepoint();String code=null;
            try{handle(event);}catch(Exception e){status.rollbackToSavepoint(savepoint);code=e instanceof InvalidEvent failure?failure.code:"SEARCH_INBOX_FAILURE";}finally{status.releaseSavepoint(savepoint);}
            if(code==null)db.update("UPDATE processed_event SET status='PROCESSED',attempt_count=?,completed_at=clock_timestamp(),next_attempt_at=NULL,last_error_code=NULL,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",attempt,CONSUMER,event.event_id());
            else {
                boolean dead=attempt>=policy.maxAttempts;
                db.update("UPDATE processed_event SET status=?,attempt_count=?,last_error_code=?,next_attempt_at=CASE WHEN ? THEN NULL ELSE clock_timestamp()+(?*interval '1 millisecond') END,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",dead?"DEAD":"FAILED_RETRYABLE",attempt,code,dead,policy.backoff(attempt),CONSUMER,event.event_id());
                if(dead)writer.deadLetter(event.event_id(),"SEARCH_INBOX",code,event.generation());
                else writer.insert(UUID.randomUUID(),event.event_id(),"RETRY",event.aggregate_type(),event.aggregate_id(),event.event_type(),event.event_version(),event.payload(),event.correlation_id(),attempt+1,event.generation(),policy.backoff(attempt));
            }
        });
    }
    private void handle(EventEnvelope event) {
        if(event.event_version()!=1)throw new InvalidEvent("UNSUPPORTED_SEARCH_EVENT_VERSION");
        if(event.event_type().equals("SearchReindexRequested")) {
            if(!event.aggregate_type().equals("SEARCH_REBUILD") || !event.aggregate_id().equals(event.event_id().toString()) || !event.payload().keySet().equals(Set.of("request_id")) || !event.payload().get("request_id").equals(event.event_id().toString()))throw new InvalidEvent("INVALID_SEARCH_EVENT_PAYLOAD");
            db.update("INSERT INTO search_rebuild_job(id,event_id,target_index) VALUES (?,?,?) ON CONFLICT(event_id) DO NOTHING",event.event_id(),event.event_id(),SearchTasks.rebuildTarget(event.event_id()));return;
        }
        if(!CatalogSearchSource.CHANGE_EVENTS.contains(event.event_type()))throw new InvalidEvent("UNSUPPORTED_SEARCH_EVENT");
        if(!event.aggregate_type().equals("CATALOG_SKU") || !event.payload().keySet().equals(Set.of("sku_id","revision")))throw new InvalidEvent("INVALID_SEARCH_EVENT_PAYLOAD");
        UUID sku=UUID.fromString(event.payload().get("sku_id").toString());
        if(!sku.toString().equals(event.aggregate_id()) || !(event.payload().get("revision") instanceof Number requested) || requested.longValue()<1)throw new InvalidEvent("INVALID_SEARCH_EVENT_PAYLOAD");
        var source=db.queryForList("SELECT revision FROM catalog_search_source WHERE sku_id=?",sku);
        if(source.isEmpty())throw new InvalidEvent("SEARCH_SOURCE_NOT_FOUND");long latest=((Number)source.getFirst().get("revision")).longValue();
        if(latest<requested.longValue())throw new InvalidEvent("SEARCH_SOURCE_REVISION_NOT_COMMITTED");
        for(var target:db.queryForList("SELECT index_name FROM search_index_version WHERE status IN ('ACTIVE','BUILDING') ORDER BY index_name"))SearchTasks.enqueue(db,sku,target.get("index_name").toString(),latest,event.event_id());
        // An unavailable/uninitialized cluster does not affect this PostgreSQL commit.
        // IndexBootstrap seeds all current source rows once the cluster becomes ready.
    }
    private static class InvalidEvent extends RuntimeException{final String code;InvalidEvent(String code){this.code=code;}}
}
