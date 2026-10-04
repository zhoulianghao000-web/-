package cn.pawday.outbox;

import cn.pawday.identity.*;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Clock;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

@Component
public class SmsDeliveryWorker {
    private record Claim(UUID id,UUID event,UUID token,int attempts,String phone,String ciphertext) {}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final DeliveryPolicy policy;private final OutboxWriter writer;
    private final SmsGateway sms;private final Crypto crypto;private final Clock clock;private final String worker="sms-"+UUID.randomUUID();
    public SmsDeliveryWorker(JdbcTemplate db,TransactionTemplate tx,DeliveryPolicy policy,OutboxWriter writer,SmsGateway sms,Crypto crypto,Clock clock){this.db=db;this.tx=tx;this.policy=policy;this.writer=writer;this.sms=sms;this.crypto=crypto;this.clock=clock;}
    public boolean sendOne() {
        Claim claim=tx.execute(s->{
            var expired=db.queryForList("SELECT * FROM sms_delivery WHERE status='SENDING' AND lease_expires_at<=clock_timestamp() FOR UPDATE SKIP LOCKED LIMIT 1");
            if(!expired.isEmpty())failedLocked(expired.getFirst(),"LEASE_EXPIRED");
            var rows=db.queryForList("SELECT * FROM sms_delivery WHERE status IN ('PENDING','FAILED_RETRYABLE') AND available_at<=clock_timestamp() ORDER BY available_at,id FOR UPDATE SKIP LOCKED LIMIT 1");
            if(rows.isEmpty())return null;var row=rows.getFirst();var challenge=db.queryForMap("SELECT * FROM otp_challenge WHERE id=?",row.get("challenge_id"));
            if(challenge.get("consumed_at")!=null || !((Timestamp)challenge.get("expires_at")).toInstant().isAfter(clock.instant()) || challenge.get("delivery_secret_ciphertext")==null) {
                db.update("UPDATE sms_delivery SET status='SKIPPED',last_error_code='OTP_EXPIRED_OR_SUPERSEDED',updated_at=clock_timestamp() WHERE id=?",row.get("id"));
                db.update("UPDATE otp_challenge SET delivery_secret_ciphertext=NULL WHERE id=?",row.get("challenge_id"));return new Claim(null,null,null,0,null,null);
            }
            UUID token=UUID.randomUUID();int attempts=((Number)row.get("attempt_count")).intValue()+1;
            db.update("UPDATE sms_delivery SET status='SENDING',attempt_count=?,claim_token=?,claimed_by=?,lease_expires_at=clock_timestamp()+(?*interval '1 millisecond'),updated_at=clock_timestamp() WHERE id=?",attempts,token,worker,Math.max(60000,policy.leaseMillis),row.get("id"));
            return new Claim((UUID)row.get("id"),(UUID)row.get("event_id"),token,attempts,(String)challenge.get("phone_e164"),(String)challenge.get("delivery_secret_ciphertext"));
        });
        if(claim==null)return false;if(claim.id()==null)return true;
        try {
            // No PostgreSQL transaction or row lock is held during the external provider call.
            sms.send(claim.id().toString(),claim.phone(),new String(crypto.decrypt(claim.ciphertext()),StandardCharsets.UTF_8));
            tx.executeWithoutResult(s->{int changed=db.update("UPDATE sms_delivery SET status='DELIVERED',delivered_at=clock_timestamp(),claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL,updated_at=clock_timestamp() WHERE id=? AND status='SENDING' AND claim_token=?",claim.id(),claim.token());if(changed==1)db.update("UPDATE otp_challenge SET delivery_secret_ciphertext=NULL WHERE id=?",claim.id());});
        } catch(Exception failed){
            String code=failed instanceof cn.pawday.common.Api.Failure failure && Set.of("SMS_PROVIDER_NOT_CONFIGURED","SMS_DELIVERY_UNAVAILABLE","RATE_LIMITED").contains(failure.code)?failure.code:"SMS_PROVIDER_UNAVAILABLE";
            tx.executeWithoutResult(s->{var rows=db.queryForList("SELECT * FROM sms_delivery WHERE id=? AND status='SENDING' AND claim_token=? FOR UPDATE",claim.id(),claim.token());if(!rows.isEmpty())failedLocked(rows.getFirst(),code);});
        }return true;
    }
    private void failedLocked(Map<String,Object> row,String code) {
        int attempts=((Number)row.get("attempt_count")).intValue();boolean dead=attempts>=policy.maxAttempts;
        db.update("UPDATE sms_delivery SET status=?,last_error_code=?,available_at=clock_timestamp()+(?*interval '1 millisecond'),dead_at=CASE WHEN ? THEN clock_timestamp() ELSE NULL END,claim_token=NULL,claimed_by=NULL,lease_expires_at=NULL,updated_at=clock_timestamp() WHERE id=?",dead?"DEAD":"FAILED_RETRYABLE",code,policy.backoff(attempts),dead,row.get("id"));
        if(dead)writer.deadLetter((UUID)row.get("event_id"),"SMS",code,db.queryForObject("SELECT generation FROM outbox_event WHERE id=?",Integer.class,row.get("event_id")));
    }
    public int expireSecrets(){return db.update("UPDATE otp_challenge SET delivery_secret_ciphertext=NULL WHERE delivery_secret_ciphertext IS NOT NULL AND (expires_at<=? OR consumed_at IS NOT NULL)",Timestamp.from(clock.instant()));}
}
