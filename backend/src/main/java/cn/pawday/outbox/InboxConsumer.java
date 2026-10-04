package cn.pawday.outbox;

import cn.pawday.identity.Crypto;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Component
public class InboxConsumer {
    public static final String CONSUMER="otp-sms-v1";
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OutboxWriter writer;private final DeliveryPolicy policy;private final Crypto crypto;
    private final JsonMapper json=JsonMapper.builder().build();
    public InboxConsumer(JdbcTemplate db,TransactionTemplate tx,OutboxWriter writer,DeliveryPolicy policy,Crypto crypto){this.db=db;this.tx=tx;this.writer=writer;this.policy=policy;this.crypto=crypto;}
    public void process(EventEnvelope event) {
        if(event.event_id()==null || event.event_type()==null || event.event_type().isBlank() || event.event_version()<1
            || event.aggregate_type()==null || event.aggregate_id()==null || event.payload()==null || event.delivery_attempt()<1 || event.generation()<0)
            throw new IllegalArgumentException("Invalid envelope");
        String hash=crypto.hash(json.writeValueAsString(List.of(event.event_type(),event.event_version(),new TreeMap<>(event.payload()))));
        tx.executeWithoutResult(status->{
            var roots=db.queryForList("SELECT generation FROM outbox_event WHERE id=?",event.event_id());
            if(!roots.isEmpty() && event.generation()!=((Number)roots.getFirst().get("generation")).intValue())return;
            db.update("INSERT INTO processed_event(consumer,event_id,status,payload_hash,generation) VALUES (?,?,'FAILED_RETRYABLE',?,?) ON CONFLICT DO NOTHING",CONSUMER,event.event_id(),hash,event.generation());
            var row=db.queryForMap("SELECT * FROM processed_event WHERE consumer=? AND event_id=? FOR UPDATE",CONSUMER,event.event_id());
            if(row.get("status").equals("PROCESSED") || row.get("status").equals("DEAD"))return;
            if(!hash.equals(row.get("payload_hash")))throw new IllegalArgumentException("Event identity payload conflict");
            int attempt=((Number)row.get("attempt_count")).intValue()+1;
            if(event.delivery_attempt()!=attempt || event.generation()!=((Number)row.get("generation")).intValue())return;
            Object savepoint=status.createSavepoint();String code=null;
            try {
                if(!event.event_type().equals("otp.sms.requested") || event.event_version()!=1)throw new HandlerFailure("UNSUPPORTED_EVENT_VERSION");
                if(!event.payload().keySet().equals(Set.of("challenge_id")))throw new HandlerFailure("INVALID_EVENT_PAYLOAD");
                UUID challenge=UUID.fromString(String.valueOf(event.payload().get("challenge_id")));
                if(!challenge.toString().equals(event.aggregate_id()) || !event.aggregate_type().equals("OTP_CHALLENGE"))throw new HandlerFailure("INVALID_EVENT_PAYLOAD");
                if(db.queryForObject("SELECT count(*) FROM otp_challenge WHERE id=?",Integer.class,challenge)!=1)throw new HandlerFailure("CHALLENGE_NOT_FOUND");
                db.update("INSERT INTO sms_delivery(id,event_id,challenge_id) VALUES (?,?,?) ON CONFLICT DO NOTHING",challenge,event.event_id(),challenge);
            } catch(Exception e){status.rollbackToSavepoint(savepoint);code=e instanceof HandlerFailure failure?failure.code:"HANDLER_FAILURE";}
            finally{status.releaseSavepoint(savepoint);}
            if(code==null)db.update("UPDATE processed_event SET status='PROCESSED',attempt_count=?,completed_at=clock_timestamp(),next_attempt_at=NULL,last_error_code=NULL,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",attempt,CONSUMER,event.event_id());
            else {
                boolean dead=attempt>=policy.maxAttempts;
                db.update("UPDATE processed_event SET status=?,attempt_count=?,last_error_code=?,next_attempt_at=CASE WHEN ? THEN NULL ELSE clock_timestamp()+(?*interval '1 millisecond') END,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",dead?"DEAD":"FAILED_RETRYABLE",attempt,code,dead,policy.backoff(attempt),CONSUMER,event.event_id());
                if(dead)writer.deadLetter(event.event_id(),"CONSUME",code,event.generation());
                else writer.insert(UUID.randomUUID(),event.event_id(),"RETRY",event.aggregate_type(),event.aggregate_id(),event.event_type(),event.event_version(),event.payload(),event.correlation_id(),attempt+1,event.generation(),policy.backoff(attempt));
            }
        });
    }
    private static class HandlerFailure extends RuntimeException {final String code;HandlerFailure(String code){this.code=code;}}
}
