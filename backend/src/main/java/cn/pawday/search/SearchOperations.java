package cn.pawday.search;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import cn.pawday.outbox.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Service @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchOperations implements OutboxReplayParticipant {
    public record Receipt(UUID request_id,String kind,String status,long affected_count){}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final AuthService auth;private final AuditWriter audit;
    private final Crypto crypto;private final OutboxWriter writer;private final OpenSearchClient client;private final AliasManager aliases;
    private final JsonMapper json=JsonMapper.builder().build();
    public SearchOperations(JdbcTemplate db,TransactionTemplate tx,AuthService auth,AuditWriter audit,Crypto crypto,OutboxWriter writer,OpenSearchClient client,AliasManager aliases){this.db=db;this.tx=tx;this.auth=auth;this.audit=audit;this.crypto=crypto;this.writer=writer;this.client=client;this.aliases=aliases;}
    public Map<String,Object> status(){
        var result=new LinkedHashMap<String,Object>();result.put("schema_version",IndexVersion.SCHEMA);
        var active=db.queryForList("SELECT index_name FROM search_index_version WHERE status='ACTIVE'");result.put("active_index",active.isEmpty()?null:active.getFirst().get("index_name"));
        result.put("versions",db.queryForList("SELECT index_name,schema_version,status,created_at,activated_at FROM search_index_version ORDER BY created_at DESC LIMIT 100"));
        result.put("task_counts",db.queryForList("SELECT status,count(*) AS count FROM search_sync_task GROUP BY status ORDER BY status"));
        result.put("rebuild_jobs",db.queryForList("SELECT id,event_id,target_index,status,attempt_count,last_error_code,validated_count,source_digest,completed_at,created_at FROM search_rebuild_job ORDER BY created_at DESC LIMIT 100"));return result;
    }
    private void validate(String reason,String key){if(reason==null||!reason.matches("[A-Z0-9_]{4,80}"))throw new Failure(400,"VALIDATION_ERROR");if(key==null||key.length()<16||key.length()>128)throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");}
    private String hash(String action,String reason){return crypto.hash(json.writeValueAsString(List.of(action,reason)));}
    private Receipt prior(Actor actor,String key,String hash){var prior=db.queryForList("SELECT payload_hash,result_json::text AS result FROM search_admin_command WHERE principal_id=? AND idempotency_key=?",actor.principalId(),key);if(prior.isEmpty())return null;if(!hash.equals(prior.getFirst().get("payload_hash")))throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");return json.readValue(prior.getFirst().get("result").toString(),Receipt.class);}
    private Receipt command(Actor actor,String action,String reason,String proof,String key,HttpServletRequest r,Supplier<Receipt> mutation){
        validate(reason,key);String hash=hash(action,reason);
        return tx.execute(s->{
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.principalId()+":"+key);Receipt prior=prior(actor,key,hash);if(prior!=null)return prior;
            auth.consumeProof(actor,action,proof);Receipt result=mutation.get();
            db.update("INSERT INTO search_admin_command(principal_id,idempotency_key,action,payload_hash,result_json) VALUES (?,?,?,?,?::jsonb)",actor.principalId(),key,action,hash,json.writeValueAsString(result));
            audit.write(actor,action,"SEARCH_PROJECTION",result.request_id().toString(),Map.of(),Map.of("reason_code",reason,"kind",result.kind(),"affected_count",result.affected_count()),r);return result;
        });
    }
    private UUID requestRebuild(String correlation){
        // Shared lock serializes request creation; one unfinished request avoids poison from duplicate rebuild jobs.
        db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended('pawday-search-rebuild-request',0))");
        long active=db.queryForObject("SELECT count(*) FROM outbox_event e WHERE e.event_type='SearchReindexRequested' AND e.transport_kind='EVENT' AND e.status<>'DEAD' AND NOT EXISTS(SELECT 1 FROM search_rebuild_job j WHERE j.event_id=e.id AND j.status IN ('COMPLETED','DEAD'))",Long.class);
        if(active>0)throw new Failure(409,"SEARCH_REBUILD_ALREADY_PENDING");
        UUID id=UUID.randomUUID();writer.insert(id,id,"EVENT","SEARCH_REBUILD",id.toString(),"SearchReindexRequested",1,Map.of("request_id",id.toString()),correlation,1,0,0);return id;
    }
    public Receipt rebuild(Actor actor,String reason,String proof,String key,HttpServletRequest r){return command(actor,"search.rebuild",reason,proof,key,r,()->new Receipt(requestRebuild(correlation(r)),"FULL_REBUILD","PENDING",0));}
    @SuppressWarnings("unchecked") public Receipt reconcile(Actor actor,String reason,String proof,String key,HttpServletRequest r){
        validate(reason,key);Receipt cached=prior(actor,key,hash("search.reconcile",reason));if(cached!=null)return cached;
        String target=aliases.current();if(target==null)throw new Failure(503,"SEARCH_NOT_INITIALIZED");client.refresh(target);var actual=client.documents(target);
        var sources=db.queryForList("SELECT sku_id,revision,document::text AS document FROM catalog_search_source");var repairs=new ArrayList<UUID>();var known=new HashSet<UUID>();
        for(var source:sources){UUID id=(UUID)source.get("sku_id");known.add(id);var expected=json.readValue(source.get("document").toString(),Map.class);if(!expected.equals(actual.get(id)))repairs.add(id);}
        boolean orphan=actual.keySet().stream().anyMatch(id->!known.contains(id));
        return command(actor,"search.reconcile",reason,proof,key,r,()->{
            // External drift can include a deleted document whose engine version is newer than PostgreSQL.
            // Repair through a fresh validated index instead of bypassing authoritative external version fencing.
            UUID request=UUID.randomUUID();boolean needsRebuild=orphan||!repairs.isEmpty();
            if(needsRebuild)request=requestRebuild(correlation(r));
            return new Receipt(request,needsRebuild?"RECONCILIATION_REBUILD":"RECONCILIATION","PENDING",repairs.size());
        });
    }
    public Receipt retry(Actor actor,String reason,String proof,String key,HttpServletRequest r){return command(actor,"search.retry",reason,proof,key,r,()->{
        long count=db.update("UPDATE search_sync_task t SET status='PENDING',attempt_count=0,last_error_code=NULL,available_at=clock_timestamp() FROM search_index_version i WHERE i.index_name=t.target_index AND i.status IN ('ACTIVE','BUILDING') AND t.status='DEAD'");
        if(db.queryForObject("SELECT count(*) FROM search_rebuild_job WHERE status IN ('PENDING','BUILDING','FAILED_RETRYABLE')",Long.class)==0){var dead=db.queryForList("SELECT id FROM search_rebuild_job WHERE status='DEAD' ORDER BY created_at DESC LIMIT 1");if(!dead.isEmpty())count+=db.update("UPDATE search_rebuild_job SET status='PENDING',attempt_count=0,last_error_code=NULL,available_at=clock_timestamp() WHERE id=?",dead.getFirst().get("id"));}
        return new Receipt(UUID.randomUUID(),"FAILED_ITEM_RETRY","PENDING",count);
    });}
    private String correlation(HttpServletRequest r){return r==null?null:String.valueOf(r.getAttribute("correlation_id"));}
    public boolean hasFailed(UUID event){return db.queryForObject("SELECT (SELECT count(*) FROM search_sync_task WHERE event_id=? AND status='DEAD')+(SELECT count(*) FROM search_rebuild_job WHERE event_id=? AND status='DEAD')",Long.class,event,event)>0;}
    public void resetFailed(UUID event,int generation){
        if(db.queryForObject("SELECT count(*) FROM search_rebuild_job WHERE event_id=? AND status='DEAD'",Long.class,event)>0&&db.queryForObject("SELECT count(*) FROM search_rebuild_job WHERE status IN ('PENDING','BUILDING','FAILED_RETRYABLE')",Long.class)>0)throw new Failure(409,"SEARCH_REBUILD_ALREADY_PENDING");
        db.update("UPDATE search_sync_task SET status='PENDING',attempt_count=0,last_error_code=NULL,available_at=clock_timestamp() WHERE event_id=? AND status='DEAD'",event);
        db.update("UPDATE search_rebuild_job SET status='PENDING',attempt_count=0,last_error_code=NULL,available_at=clock_timestamp() WHERE event_id=? AND status='DEAD'",event);
    }
}
