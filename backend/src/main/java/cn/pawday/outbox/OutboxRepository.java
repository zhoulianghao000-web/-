package cn.pawday.outbox;

import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Repository
public class OutboxRepository {
    public record Claim(UUID id,UUID token,int attempts,String kind,EventEnvelope envelope) {}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final DeliveryPolicy policy;private final OutboxWriter writer;
    private final JsonMapper json=JsonMapper.builder().build();
    public OutboxRepository(JdbcTemplate db,TransactionTemplate tx,DeliveryPolicy policy,OutboxWriter writer){this.db=db;this.tx=tx;this.policy=policy;this.writer=writer;}
    public Optional<Claim> claim(String worker) {
        return tx.execute(s->{
            // Recover one expired claim per pass, using a row lock and fencing token.
            var expired=db.queryForList("SELECT * FROM outbox_event WHERE status='PUBLISHING' AND lease_expires_at<=clock_timestamp() ORDER BY lease_expires_at FOR UPDATE SKIP LOCKED LIMIT 1");
            if(!expired.isEmpty()) failureLocked(expired.getFirst(),"LEASE_EXPIRED");
            var rows=db.queryForList("""
                SELECT * FROM outbox_event WHERE status IN ('PENDING','FAILED_RETRYABLE') AND available_at<=clock_timestamp()
                ORDER BY available_at,created_at,id FOR UPDATE SKIP LOCKED LIMIT 1
                """);
            if(rows.isEmpty())return Optional.empty();var row=rows.getFirst();UUID id=(UUID)row.get("id"),token=UUID.randomUUID();
            int attempts=((Number)row.get("attempt_count")).intValue()+1;
            db.update("UPDATE outbox_event SET status='PUBLISHING',claim_token=?,claimed_by=?,lease_expires_at=clock_timestamp()+(?*interval '1 millisecond'),attempt_count=?,updated_at=clock_timestamp() WHERE id=?",token,worker,policy.leaseMillis,attempts,id);
            @SuppressWarnings("unchecked") Map<String,Object> payload=json.readValue(row.get("payload").toString(),Map.class);
            return Optional.of(new Claim(id,token,attempts,(String)row.get("transport_kind"),new EventEnvelope((UUID)row.get("root_event_id"),(String)row.get("event_type"),((Number)row.get("event_version")).intValue(),(String)row.get("aggregate_type"),(String)row.get("aggregate_id"),(String)row.get("correlation_id"),((Number)row.get("delivery_attempt")).intValue(),((Number)row.get("generation")).intValue(),payload)));
        });
    }
    public boolean published(Claim claim) {
        return db.update("""
            UPDATE outbox_event SET status='PUBLISHED',published_at=clock_timestamp(),claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL,updated_at=clock_timestamp()
            WHERE id=? AND status='PUBLISHING' AND claim_token=? AND lease_expires_at>clock_timestamp()
            """,claim.id(),claim.token())==1;
    }
    public void failed(Claim claim,String code) {
        tx.executeWithoutResult(s->{var rows=db.queryForList("SELECT * FROM outbox_event WHERE id=? AND status='PUBLISHING' AND claim_token=? FOR UPDATE",claim.id(),claim.token());if(!rows.isEmpty())failureLocked(rows.getFirst(),code);});
    }
    private void failureLocked(Map<String,Object> row,String code) {
        int attempts=((Number)row.get("attempt_count")).intValue();boolean dead=attempts>=policy.maxAttempts;
        db.update("""
            UPDATE outbox_event SET status=?,available_at=clock_timestamp()+(?*interval '1 millisecond'),last_error_code=?,last_error_at=clock_timestamp(),dead_at=CASE WHEN ? THEN clock_timestamp() ELSE NULL END,
              claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL,updated_at=clock_timestamp() WHERE id=?
            """,dead?"DEAD":"FAILED_RETRYABLE",policy.backoff(attempts),code,dead,row.get("id"));
        if(dead && !row.get("transport_kind").equals("DEAD_LETTER"))writer.deadLetter((UUID)row.get("root_event_id"),"PUBLISH",code,((Number)row.get("generation")).intValue());
        if(dead && row.get("transport_kind").equals("RETRY"))db.update("UPDATE processed_event SET status='DEAD',last_error_code='RETRY_PUBLISH_EXHAUSTED',next_attempt_at=NULL,updated_at=clock_timestamp() WHERE event_id=? AND generation=? AND status='FAILED_RETRYABLE'",row.get("root_event_id"),row.get("generation"));
    }
}
