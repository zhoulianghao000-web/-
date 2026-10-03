package cn.pawday.outbox;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
@Service
public class OutboxOperations {
    public record Replay(UUID event_id,int generation,String status) {}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final AuthService auth;private final AuditWriter audit;private final Crypto crypto;private final Clock clock;private final List<OutboxReplayParticipant> participants;
    public OutboxOperations(JdbcTemplate db,TransactionTemplate tx,AuthService auth,AuditWriter audit,Crypto crypto,Clock clock,List<OutboxReplayParticipant> participants){this.db=db;this.tx=tx;this.auth=auth;this.audit=audit;this.crypto=crypto;this.clock=clock;this.participants=participants;}
    public List<Map<String,Object>> list(int limit){if(limit<1 || limit>100)throw new Failure(400,"VALIDATION_ERROR");return db.queryForList("SELECT id,root_event_id,event_type,event_version,transport_kind,status,attempt_count,available_at,lease_expires_at,last_error_code,dead_at,generation,created_at FROM outbox_event ORDER BY created_at DESC,id LIMIT ?",limit);}
    public Map<String,Object> stats(){var data=new LinkedHashMap<String,Object>();
        data.put("status_counts",db.queryForList("SELECT status,count(*) AS count FROM outbox_event GROUP BY status ORDER BY status"));
        data.put("backlog",count("SELECT count(*) FROM outbox_event WHERE status IN ('PENDING','PUBLISHING','FAILED_RETRYABLE')"));
        data.put("oldest_event_age_seconds",db.queryForObject("SELECT coalesce(greatest(0,extract(epoch FROM clock_timestamp()-min(created_at))),0)::double precision FROM outbox_event WHERE status IN ('PENDING','PUBLISHING','FAILED_RETRYABLE')",Double.class));
        data.put("inbox_dead",count("SELECT count(*) FROM processed_event WHERE status='DEAD'"));data.put("sms_dead",count("SELECT count(*) FROM sms_delivery WHERE status='DEAD'"));return data;
    }
    public long count(String sql){return db.queryForObject(sql,Long.class);}
    public Replay replay(Actor actor,UUID id,int expected,String reason,String proof,String key,HttpServletRequest request) {
        if(key==null || key.length()<16 || key.length()>128)throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");
        String hash=crypto.hash(new JsonMapper().writeValueAsString(List.of(id,expected,reason)));
        return tx.execute(s->{
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.principalId()+":"+key);
            var commands=db.queryForList("SELECT * FROM outbox_replay_command WHERE principal_id=? AND idempotency_key=?",actor.principalId(),key);
            if(!commands.isEmpty()){var prior=commands.getFirst();if(!hash.equals(prior.get("payload_hash")))throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");return new Replay(id,((Number)prior.get("generation")).intValue(),"PENDING");}
            var rows=db.queryForList("SELECT * FROM outbox_event WHERE id=? FOR UPDATE",id);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var root=rows.getFirst();
            boolean metadataOnly=root.get("transport_kind").equals("DEAD_LETTER");
            if(!metadataOnly && !root.get("id").equals(root.get("root_event_id")))throw new Failure(409,"REPLAY_REQUIRES_ROOT_EVENT");
            int old=((Number)root.get("generation")).intValue();if(old!=expected)throw new Failure(409,"VERSION_CONFLICT");
            boolean failed=root.get("status").equals("DEAD") || countFor("SELECT count(*) FROM processed_event WHERE event_id=? AND status='DEAD'",id)>0 || countFor("SELECT count(*) FROM sms_delivery WHERE event_id=? AND status='DEAD'",id)>0;
            failed=failed || participants.stream().anyMatch(p->p.hasFailed(id));
            if(!failed)throw new Failure(409,"EVENT_NOT_REPLAYABLE");
            if(root.get("event_type").equals("otp.sms.requested")) {
                var challenges=db.queryForList("SELECT * FROM otp_challenge WHERE id=?",UUID.fromString(root.get("aggregate_id").toString()));
                if(challenges.isEmpty() || challenges.getFirst().get("consumed_at")!=null || !((Timestamp)challenges.getFirst().get("expires_at")).toInstant().isAfter(clock.instant()))throw new Failure(409,"EVENT_EXPIRED");
            }
            auth.consumeProof(actor,"outbox.replay",proof);int generation=old+1;
            db.update("UPDATE outbox_event SET status='PENDING',attempt_count=0,delivery_attempt=1,generation=?,available_at=clock_timestamp(),published_at=NULL,dead_at=NULL,last_error_code=NULL,claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL,updated_at=clock_timestamp() WHERE id=?",generation,id);
            if(!metadataOnly) {
                participants.forEach(p->p.resetFailed(id,generation));
                db.update("UPDATE processed_event SET status='FAILED_RETRYABLE',attempt_count=0,generation=?,next_attempt_at=NULL,last_error_code=NULL,updated_at=clock_timestamp() WHERE event_id=? AND status='DEAD'",generation,id);
                db.update("UPDATE sms_delivery SET status='PENDING',attempt_count=0,available_at=clock_timestamp(),last_error_code=NULL,dead_at=NULL,updated_at=clock_timestamp() WHERE event_id=? AND status='DEAD'",id);
                db.update("UPDATE outbox_event SET status='DEAD',last_error_code='SUPERSEDED_BY_REPLAY',dead_at=clock_timestamp(),claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL WHERE root_event_id=? AND id<>? AND transport_kind='RETRY' AND status<>'PUBLISHED'",id,id);
            }
            db.update("INSERT INTO outbox_replay_command(principal_id,idempotency_key,event_id,payload_hash,generation) VALUES (?,?,?,?,?)",actor.principalId(),key,id,hash,generation);
            audit.write(actor,"outbox.replay","OUTBOX_EVENT",id.toString(),Map.of("status",root.get("status"),"generation",old),Map.of("status","PENDING","generation",generation,"reason_code",reason),request);
            return new Replay(id,generation,"PENDING");
        });
    }
    private long countFor(String sql,UUID id){return db.queryForObject(sql,Long.class,id);}
}
