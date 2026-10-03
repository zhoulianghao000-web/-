package cn.pawday.search;
import cn.pawday.outbox.OutboxWriter;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.*;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import tools.jackson.databind.json.JsonMapper;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchSyncWorker {
    public record Claim(UUID sourceId,String index,UUID token,long revision,UUID eventId,int attempt,Map<String,Object> document){}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OpenSearchClient client;private final SearchDeliveryPolicy policy;private final OutboxWriter writer;
    private final JsonMapper json=JsonMapper.builder().build();
    public SearchSyncWorker(JdbcTemplate db,TransactionTemplate tx,OpenSearchClient client,SearchDeliveryPolicy policy,OutboxWriter writer){this.db=db;this.tx=tx;this.client=client;this.policy=policy;this.writer=writer;}
    @SuppressWarnings("unchecked") public Optional<Claim> claim(String onlyIndex) {
        return tx.execute(s->{
            var expired=db.queryForList("SELECT t.* FROM search_sync_task t JOIN search_index_version i ON i.index_name=t.target_index WHERE t.status='SYNCING' AND t.lease_expires_at<clock_timestamp() AND i.status IN ('ACTIVE','BUILDING') ORDER BY t.lease_expires_at FOR UPDATE OF t SKIP LOCKED LIMIT 32");
            for(var row:expired)expire(row);
            var rows=db.queryForList("SELECT t.*,s.revision,s.document::text AS source_document FROM search_sync_task t JOIN catalog_search_source s ON s.sku_id=t.source_id JOIN search_index_version i ON i.index_name=t.target_index WHERE t.status IN ('PENDING','FAILED_RETRYABLE') AND t.available_at<=clock_timestamp() AND i.status IN ('ACTIVE','BUILDING') AND (?::text IS NULL OR t.target_index=?) ORDER BY t.available_at,t.source_id FOR UPDATE OF t SKIP LOCKED LIMIT 1",onlyIndex,onlyIndex);
            if(rows.isEmpty())return Optional.empty();var row=rows.getFirst();UUID token=UUID.randomUUID();long revision=((Number)row.get("revision")).longValue();
            int attempt=((Number)row.get("attempt_count")).intValue()+1;
            db.update("UPDATE search_sync_task SET status='SYNCING',attempt_count=?,desired_revision=greatest(desired_revision,?),claim_token=?,lease_expires_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE source_id=? AND target_index=?",attempt,revision,token,policy.leaseMs,row.get("source_id"),row.get("target_index"));
            return Optional.of(new Claim((UUID)row.get("source_id"),row.get("target_index").toString(),token,revision,(UUID)row.get("event_id"),attempt,json.readValue(row.get("source_document").toString(),Map.class)));
        });
    }
    private void expire(Map<String,Object> row) {
        int attempt=((Number)row.get("attempt_count")).intValue();boolean dead=attempt>=policy.maxAttempts;
        db.update("UPDATE search_sync_task SET status=?,claim_token=NULL,lease_expires_at=NULL,last_error_code='SEARCH_LEASE_EXPIRED',available_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE source_id=? AND target_index=?",dead?"DEAD":"FAILED_RETRYABLE",policy.backoff(attempt),row.get("source_id"),row.get("target_index"));
        if(dead && row.get("event_id")!=null)writer.deadLetter((UUID)row.get("event_id"),"SEARCH_SYNC","SEARCH_LEASE_EXPIRED",generation((UUID)row.get("event_id")));
    }
    public boolean runOne(){return runOne(null);}
    public boolean runOne(String onlyIndex) {
        var optional=claim(onlyIndex);if(optional.isEmpty())return false;var claim=optional.get();
        try {
            if(TransactionSynchronizationManager.isActualTransactionActive())throw new IllegalStateException("Search call must run outside a PostgreSQL transaction");
            client.put(claim.index(),claim.sourceId(),claim.revision(),claim.document());complete(claim);
        }catch(Exception e){failed(claim,e instanceof OpenSearchClient.Unavailable unavailable?unavailable.code:"SEARCH_SYNC_FAILURE");}return true;
    }
    public boolean complete(Claim claim) {
        return tx.execute(s->db.update("UPDATE search_sync_task SET status=CASE WHEN desired_revision>? THEN 'PENDING' ELSE 'APPLIED' END,completed_revision=greatest(completed_revision,?),attempt_count=0,claim_token=NULL,lease_expires_at=NULL,last_error_code=NULL,available_at=clock_timestamp(),updated_at=clock_timestamp() WHERE source_id=? AND target_index=? AND status='SYNCING' AND claim_token=? AND lease_expires_at>clock_timestamp()",claim.revision(),claim.revision(),claim.sourceId(),claim.index(),claim.token())==1);
    }
    public boolean failed(Claim claim,String code) {
        return tx.execute(s->{
            var rows=db.queryForList("SELECT desired_revision FROM search_sync_task WHERE source_id=? AND target_index=? AND status='SYNCING' AND claim_token=? AND lease_expires_at>clock_timestamp() FOR UPDATE",claim.sourceId(),claim.index(),claim.token());
            if(rows.isEmpty())return false;
            boolean superseded=((Number)rows.getFirst().get("desired_revision")).longValue()>claim.revision();boolean dead=!superseded&&claim.attempt()>=policy.maxAttempts;
            db.update("UPDATE search_sync_task SET status=?,attempt_count=CASE WHEN ? THEN 0 ELSE attempt_count END,claim_token=NULL,lease_expires_at=NULL,last_error_code=?,available_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE source_id=? AND target_index=?",superseded?"PENDING":dead?"DEAD":"FAILED_RETRYABLE",superseded,code,superseded?0:policy.backoff(claim.attempt()),claim.sourceId(),claim.index());
            if(dead&&claim.eventId()!=null)writer.deadLetter(claim.eventId(),"SEARCH_SYNC",code,generation(claim.eventId()));return true;
        });
    }
    private int generation(UUID event){var rows=db.queryForList("SELECT generation FROM outbox_event WHERE id=?",event);return rows.isEmpty()?0:((Number)rows.getFirst().get("generation")).intValue();}
}
