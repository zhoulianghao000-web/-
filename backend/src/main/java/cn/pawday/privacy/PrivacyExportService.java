package cn.pawday.privacy;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** Claim + committed prefix snapshot, independent IO, fenced acknowledgement.
 * No provider IO while holding a business transaction. Lost acknowledgements are
 * retried with full prefixes. A lease loser cannot replace a newer checkpoint.
 */
public final class PrivacyExportService {
    public record Checkpoint(byte[] payload,String signature,String sha256,long sequence,Instant coveredUntil) {
        public Checkpoint {payload=payload.clone();}
        @Override public byte[] payload(){return payload.clone();}
    }
    private record Claim(UUID token,Checkpoint checkpoint) {}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final PrivacyExportProvider provider;
    private final byte[] key;private final Clock clock;private final long leaseSeconds;
    private final JsonMapper json=JsonMapper.builder().build();
    public PrivacyExportService(JdbcTemplate db,TransactionTemplate tx,PrivacyExportProvider provider,byte[] key,Clock clock,long leaseSeconds) {
        if(key.length<32||leaseSeconds<1)throw new IllegalArgumentException("PRIVACY_EXPORT_CONFIGURATION_INVALID");
        this.db=db;this.tx=tx;this.provider=provider;this.key=key.clone();this.clock=clock;this.leaseSeconds=leaseSeconds;
    }
    public static String sha256(byte[] data){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));}catch(GeneralSecurityException e){throw new IllegalStateException("HASH_UNAVAILABLE");}}
    public static String sign(byte[] data,byte[] key){try{var mac=Mac.getInstance("HmacSHA256");mac.init(new SecretKeySpec(key,"HmacSHA256"));return HexFormat.of().formatHex(mac.doFinal(data));}catch(GeneralSecurityException e){throw new IllegalStateException("SIGNATURE_UNAVAILABLE");}}
    public boolean runOne() {
        Claim claim=tx.execute(s->{
            var rows=db.queryForList("SELECT * FROM privacy_export_state WHERE singleton AND next_attempt_at<=? AND (lease_until IS NULL OR lease_until<=?) FOR UPDATE SKIP LOCKED",Timestamp.from(clock.instant()),Timestamp.from(clock.instant()));
            if(rows.isEmpty())return null;
            // READ COMMITTED + counter lock: all prefix writers have committed or
            // rolled back before this barrier; later writers wait until snapshot.
            var head=db.queryForMap("SELECT * FROM privacy_journal_head WHERE singleton FOR UPDATE");
            long sequence=((Number)head.get("last_sequence")).longValue();
            if(sequence>10000)throw new IllegalStateException("PRIVACY_EXPORT_CAPACITY_REVIEW_REQUIRED");
            Instant covered=db.queryForObject("SELECT clock_timestamp()",Timestamp.class).toInstant();
            var events=new ArrayList<Map<String,Object>>();
            for(var row:db.queryForList("SELECT * FROM privacy_journal ORDER BY sequence"))events.add(Map.of("sequence",row.get("sequence"),"kind",row.get("kind"),"subject_id",row.get("subject_id").toString(),"effective_at",((Timestamp)row.get("effective_at")).toInstant().toString()));
            if(events.size()!=sequence)throw new IllegalStateException("PRIVACY_EXPORT_SEQUENCE_GAP");
            String system=db.queryForObject("SELECT system_identifier::text FROM pg_control_system()",String.class);
            byte[] data=json.writeValueAsString(Map.of("schema_version","pawday-privacy-export/v1","system_id",system,"journal_id",head.get("journal_id").toString(),"installed_at",((Timestamp)head.get("installed_at")).toInstant().toString(),"covered_until",covered.toString(),"last_sequence",sequence,"events",events)).getBytes(StandardCharsets.UTF_8);
            if(data.length>1048576)throw new IllegalStateException("PRIVACY_EXPORT_CAPACITY_REVIEW_REQUIRED");
            UUID token=UUID.randomUUID();
            db.update("UPDATE privacy_export_state SET claim_token=?,lease_until=?,updated_at=? WHERE singleton",token,Timestamp.from(clock.instant().plusSeconds(leaseSeconds)),Timestamp.from(clock.instant()));
            return new Claim(token,new Checkpoint(data,sign(data,key),sha256(data),sequence,covered));
        });
        if(claim==null)return false;
        try {
            provider.publish(claim.checkpoint());
            tx.executeWithoutResult(s->db.update("UPDATE privacy_export_state SET exported_sequence=?,covered_until=?,checkpoint_sha256=?,claim_token=NULL,lease_until=NULL,attempts=0,last_error_code=NULL,next_attempt_at=?,updated_at=? WHERE singleton AND claim_token=?",claim.checkpoint().sequence(),Timestamp.from(claim.checkpoint().coveredUntil()),claim.checkpoint().sha256(),Timestamp.from(clock.instant().plusSeconds(30)),Timestamp.from(clock.instant()),claim.token()));
        }catch(RuntimeException unavailable){
            // Persist only a bounded code, never provider exception text or paths.
            tx.executeWithoutResult(s->db.update("UPDATE privacy_export_state SET attempts=attempts+1,last_error_code='INDEPENDENT_EXPORT_UNAVAILABLE',claim_token=NULL,lease_until=NULL,next_attempt_at=?::timestamptz+(least(3600,power(2,least(attempts,11)))*interval '1 second'),updated_at=? WHERE singleton AND claim_token=?",Timestamp.from(clock.instant()),Timestamp.from(clock.instant()),claim.token()));
        }
        return true;
    }
}
