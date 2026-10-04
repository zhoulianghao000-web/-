package cn.pawday.search;
import cn.pawday.identity.Crypto;
import cn.pawday.outbox.OutboxWriter;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchRebuildWorker {
    public record Claim(UUID id,UUID event,String index,UUID token,int attempt){}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OpenSearchClient client;private final AliasManager aliases;
    private final SearchSyncWorker sync;private final SearchDeliveryPolicy policy;private final Crypto crypto;private final OutboxWriter writer;private final SearchTopologyLock coordination;
    public SearchRebuildWorker(JdbcTemplate db,TransactionTemplate tx,OpenSearchClient client,AliasManager aliases,SearchSyncWorker sync,SearchDeliveryPolicy policy,Crypto crypto,OutboxWriter writer,SearchTopologyLock coordination){this.db=db;this.tx=tx;this.client=client;this.aliases=aliases;this.sync=sync;this.policy=policy;this.crypto=crypto;this.writer=writer;this.coordination=coordination;}
    public Optional<Claim> claim() {
        return tx.execute(s->{
            var expired=db.queryForList("SELECT * FROM search_rebuild_job WHERE status='BUILDING' AND lease_expires_at<clock_timestamp() FOR UPDATE SKIP LOCKED");
            for(var row:expired){boolean dead=((Number)row.get("attempt_count")).intValue()>=policy.maxAttempts;db.update("UPDATE search_rebuild_job SET status=?,claim_token=NULL,lease_expires_at=NULL,last_error_code='SEARCH_REBUILD_LEASE_EXPIRED',available_at=clock_timestamp() WHERE id=?",dead?"DEAD":"FAILED_RETRYABLE",row.get("id"));}
            var rows=db.queryForList("SELECT * FROM search_rebuild_job WHERE status IN ('PENDING','FAILED_RETRYABLE') AND available_at<=clock_timestamp() ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1");
            if(rows.isEmpty())return Optional.empty();var row=rows.getFirst();UUID token=UUID.randomUUID();int attempt=((Number)row.get("attempt_count")).intValue()+1;
            db.update("UPDATE search_rebuild_job SET status='BUILDING',attempt_count=?,claim_token=?,lease_expires_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE id=?",attempt,token,policy.leaseMs,row.get("id"));
            return Optional.of(new Claim((UUID)row.get("id"),(UUID)row.get("event_id"),row.get("target_index").toString(),token,attempt));
        });
    }
    public boolean runOne() {
        var optional=claim();if(optional.isEmpty())return false;var job=optional.get();
        try {
            // Recovery from an applied alias request with a lost response/DB commit.
            if(job.index().equals(aliases.current())){finish(job);return true;}
            IndexVersion.ensure(client,job.index());
            tx.executeWithoutResult(s->{
                if(!renew(job))throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_LEASE_LOST");
                db.update("INSERT INTO search_index_version(index_name,schema_version,status) VALUES (?,?,'BUILDING') ON CONFLICT(index_name) DO NOTHING",job.index(),IndexVersion.SCHEMA);
                SearchTasks.seed(db,job.index(),job.event());
            });
            int processed=0;
            while(sync.runOne(job.index())){if(++processed%16==0&&!renew(job))throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_LEASE_LOST");if(processed>=10000)break;}
            if(db.queryForObject("SELECT count(*) FROM search_sync_task WHERE target_index=? AND status='DEAD'",Long.class,job.index())>0)throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_ITEM_DEAD");
            if(db.queryForObject("SELECT count(*) FROM search_sync_task WHERE target_index=? AND (status<>'APPLIED' OR completed_revision<desired_revision)",Long.class,job.index())>0) {
                defer(job);return true; // Durable item retries keep old aliases intact.
            }
            if(!renew(job))throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_LEASE_LOST");
            client.refresh(job.index());var documents=client.documents(job.index());
            var source=db.queryForList("SELECT sku_id,revision,deleted,document::text AS document FROM catalog_search_source ORDER BY sku_id");
            boolean valid=true;var digest=new StringBuilder();
            for(var row:source) {
                UUID id=(UUID)row.get("sku_id");long revision=((Number)row.get("revision")).longValue();var actual=documents.get(id);
                if(actual==null || !new tools.jackson.databind.json.JsonMapper().readValue(row.get("document").toString(),Map.class).equals(actual))valid=false;
                digest.append(id).append(':').append(revision).append(':').append(row.get("deleted")).append('\n');
            }
            // New concurrent commits can appear after the snapshot; they must be real source IDs.
            for(UUID id:documents.keySet())if(db.queryForObject("SELECT count(*) FROM catalog_search_source WHERE sku_id=?",Integer.class,id)==0)valid=false;
            if(!valid){tx.executeWithoutResult(s->SearchTasks.seed(db,job.index(),job.event()));defer(job);return true;}
            tx.executeWithoutResult(s->db.update("UPDATE search_rebuild_job SET validated_count=?,source_digest=? WHERE id=? AND claim_token=?",source.size(),crypto.hash(digest.toString()),job.id(),job.token()));
            if(!renew(job))throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_LEASE_LOST");
            try(var held=coordination.acquire()){
                if(!renew(job))throw new OpenSearchClient.Unavailable("SEARCH_REBUILD_LEASE_LOST");
                aliases.switchTo(job.index());finish(job);
            }
        }catch(Exception e){fail(job,e instanceof OpenSearchClient.Unavailable unavailable?unavailable.code:"SEARCH_REBUILD_FAILURE");}return true;
    }
    private boolean renew(Claim job){return db.update("UPDATE search_rebuild_job SET lease_expires_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE id=? AND status='BUILDING' AND claim_token=? AND lease_expires_at>clock_timestamp()",policy.leaseMs,job.id(),job.token())==1;}
    private void defer(Claim job){tx.executeWithoutResult(s->db.update("UPDATE search_rebuild_job SET status='FAILED_RETRYABLE',attempt_count=greatest(0,attempt_count-1),claim_token=NULL,lease_expires_at=NULL,available_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE id=? AND claim_token=? AND lease_expires_at>clock_timestamp()",policy.baseMs,job.id(),job.token()));}
    private void finish(Claim job) {
        tx.executeWithoutResult(s->{
            var rows=db.queryForList("SELECT id FROM search_rebuild_job WHERE id=? AND status='BUILDING' AND claim_token=? AND lease_expires_at>clock_timestamp() FOR UPDATE",job.id(),job.token());
            if(rows.isEmpty())return;
            db.update("UPDATE search_index_version SET status='RETIRED' WHERE status='ACTIVE' AND index_name<>?",job.index());
            db.update("UPDATE search_index_version SET status='ACTIVE',activated_at=clock_timestamp() WHERE index_name=?",job.index());
            db.update("UPDATE search_rebuild_job SET status='COMPLETED',claim_token=NULL,lease_expires_at=NULL,last_error_code=NULL,completed_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=?",job.id());
            SearchTasks.seed(db,job.index(),job.event());
        });
    }
    private void fail(Claim job,String code) {
        tx.executeWithoutResult(s->{
            boolean dead=job.attempt()>=policy.maxAttempts;
            int changed=db.update("UPDATE search_rebuild_job SET status=?,claim_token=NULL,lease_expires_at=NULL,last_error_code=?,available_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE id=? AND status='BUILDING' AND claim_token=? AND lease_expires_at>clock_timestamp()",dead?"DEAD":"FAILED_RETRYABLE",code,policy.backoff(job.attempt()),job.id(),job.token());
            if(changed==1&&dead&&job.event()!=null)writer.deadLetter(job.event(),"SEARCH_REBUILD",code,generation(job.event()));
        });
    }
    private int generation(UUID event){var rows=db.queryForList("SELECT generation FROM outbox_event WHERE id=?",event);return rows.isEmpty()?0:((Number)rows.getFirst().get("generation")).intValue();}
}
