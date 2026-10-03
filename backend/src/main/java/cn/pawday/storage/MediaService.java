package cn.pawday.storage;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.io.InputStream;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class MediaService {
    public record Asset(UUID asset_id,UUID owner_id,String realm,String scope,UUID store_id,String storage_provider,
                        String object_key,String mime,long size_bytes,String sha256,String status,String error_code,
                        Instant created_at,Instant updated_at) {}
    public record Grant(UUID asset_id,String upload_token,String upload_url,Instant expires_at,String status) {}
    public record Content(Asset asset,InputStream input) {}
    private record Claim(Map<String,Object> row,UUID token) {}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final AccessGuard guard;private final Crypto crypto;
    private final AuditWriter audit;private final Clock clock;private final ObjectStorageProvider provider;
    private final long maximum,grantSeconds,leaseSeconds;
    public MediaService(JdbcTemplate db,TransactionTemplate tx,AccessGuard guard,Crypto crypto,AuditWriter audit,Clock clock,ObjectStorageProvider provider,
                        @Value("${pawday.storage.max-bytes:5242880}") long maximum,
                        @Value("${pawday.storage.grant-seconds:300}") long grantSeconds,
                        @Value("${pawday.storage.lease-seconds:60}") long leaseSeconds) {
        this.db=db;this.tx=tx;this.guard=guard;this.crypto=crypto;this.audit=audit;this.clock=clock;this.provider=provider;
        if(maximum<1||maximum>5242880||grantSeconds<1||grantSeconds>900||leaseSeconds<1)throw new IllegalArgumentException("Invalid media bounds");
        this.maximum=maximum;this.grantSeconds=grantSeconds;this.leaseSeconds=leaseSeconds;
    }
    public Grant grant(String scope,String mime,long size,String hash,UUID store,HttpServletRequest request) {
        Actor actor=guard.actor();
        Set<String> scopes=switch(actor.realm()){case CONSUMER->Set.of("AVATAR","REVIEW","CHAT");case MERCHANT->Set.of("PRODUCT","CHAT");case ADMIN->Set.of("ARTICLE","CHAT");};
        if(!scopes.contains(scope))throw new Failure(403,"MEDIA_SCOPE_DENIED");
        if(!Set.of("image/png","image/jpeg").contains(mime))throw new Failure(400,"UPLOAD_MIME_NOT_ALLOWED");
        if(size<1||size>maximum)throw new Failure(413,"UPLOAD_TOO_LARGE");
        if(hash==null||!hash.matches("[0-9a-f]{64}"))throw new Failure(400,"VALIDATION_ERROR");
        if(scope.equals("PRODUCT")){if(store==null)throw new Failure(400,"STORE_REQUIRED");guard.store(actor,store);}
        else if(store!=null)throw new Failure(400,"STORE_NOT_ALLOWED");
        UUID id=UUID.randomUUID();String token=crypto.token();Instant now=clock.instant(),expires=now.plusSeconds(grantSeconds);
        String key="media/"+id+(mime.equals("image/png")?".png":".jpg");
        return tx.execute(status->{
            // Bound outstanding grants per principal; advisory locking serializes simultaneous issuances.
            db.queryForObject("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",Object.class,actor.principalId().toString());
            int pending=db.queryForObject("SELECT count(*) FROM media_asset WHERE owner_id=? AND status IN ('UPLOAD_PENDING','UPLOADING') AND upload_expires_at>?",Integer.class,actor.principalId(),Timestamp.from(now));
            if(pending>=20)throw new Failure(429,"UPLOAD_GRANT_LIMIT");
            db.update("""
                INSERT INTO media_asset(id,owner_id,realm,owner_session_id,scope,store_id,storage_provider,object_key,mime,size_bytes,sha256,status,upload_token_hash,upload_expires_at,next_cleanup_at,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,'UPLOAD_PENDING',?,?,?,?,?)
                """,id,actor.principalId(),actor.realm().name(),actor.sessionId(),scope,store,provider.providerId(),key,mime,size,hash,crypto.hash(token),Timestamp.from(expires),Timestamp.from(now),Timestamp.from(now),Timestamp.from(now));
            audit.write(actor,"media.upload-grant","MEDIA_ASSET",id.toString(),Map.of(),Map.of("scope",scope,"mime",mime,"size_bytes",size),request);
            return new Grant(id,token,"/api/v1/media/"+id+"/content",expires,"UPLOAD_PENDING");
        });
    }
    private Map<String,Object> row(UUID id,boolean lock) {
        var rows=db.queryForList("SELECT * FROM media_asset WHERE id=?"+(lock?" FOR UPDATE":""),id);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();
    }
    private void owner(Actor actor,Map<String,Object> row) {
        if(!actor.principalId().equals(row.get("owner_id"))||!actor.realm().name().equals(row.get("realm")))throw new Failure(404,"RESOURCE_NOT_FOUND");
        if(row.get("store_id")!=null)guard.store(actor,(UUID)row.get("store_id"));
        if(!provider.providerId().equals(row.get("storage_provider")))throw new Failure(503,"OBJECT_PROVIDER_UNAVAILABLE");
    }
    private Instant time(Map<String,Object> row,String column){return ((Timestamp)row.get(column)).toInstant();}
    private Asset asset(Map<String,Object> row) {
        return new Asset((UUID)row.get("id"),(UUID)row.get("owner_id"),(String)row.get("realm"),(String)row.get("scope"),(UUID)row.get("store_id"),(String)row.get("storage_provider"),(String)row.get("object_key"),(String)row.get("mime"),((Number)row.get("size_bytes")).longValue(),(String)row.get("sha256"),(String)row.get("status"),(String)row.get("error_code"),time(row,"created_at"),time(row,"updated_at"));
    }
    public Asset metadata(UUID id){var row=row(id,false);owner(guard.actor(),row);return asset(row);}
    public Asset upload(UUID id,String token,String contentType,long contentLength,InputStream input,HttpServletRequest request) {
        Actor actor=guard.actor();Instant now=clock.instant();
        Claim claim=tx.execute(status->{
            var row=row(id,true);owner(actor,row);Instant claimNow=clock.instant();
            if(!actor.sessionId().equals(row.get("owner_session_id")))throw new Failure(403,"UPLOAD_SESSION_MISMATCH");
            if(!"UPLOAD_PENDING".equals(row.get("status")))throw new Failure(409,"UPLOAD_GRANT_CONSUMED");
            if(!time(row,"upload_expires_at").isAfter(claimNow))throw new Failure(403,"UPLOAD_GRANT_EXPIRED");
            if(token==null||!crypto.equal(crypto.hash(token),(String)row.get("upload_token_hash")))throw new Failure(403,"UPLOAD_TOKEN_INVALID");
            UUID fence=UUID.randomUUID();db.update("UPDATE media_asset SET status='UPLOADING',upload_token_hash=NULL,claim_token=?,lease_expires_at=?,updated_at=? WHERE id=?",fence,Timestamp.from(claimNow.plusSeconds(leaseSeconds)),Timestamp.from(claimNow),id);return new Claim(row,fence);
        });
        try {
            if(!Objects.equals(contentType,claim.row().get("mime")))throw new Failure(400,"UPLOAD_MIME_MISMATCH");
            if(contentLength>maximum||contentLength>((Number)claim.row().get("size_bytes")).longValue())throw new Failure(413,"UPLOAD_TOO_LARGE");
            var stored=provider.put(new ObjectStorageProvider.Put((String)claim.row().get("object_key"),(String)claim.row().get("mime"),((Number)claim.row().get("size_bytes")).longValue(),(String)claim.row().get("sha256"),maximum),input);
            boolean finished=finish(id,claim.token(),stored,actor,request,"media.uploaded");
            if(!finished){/* Recovery may already have made the immutable object READY; an old claim must never delete it. */throw new Failure(409,"UPLOAD_LEASE_EXPIRED");}
            return metadata(id);
        } catch(Failure failure) {
            tx.executeWithoutResult(status->db.update("UPDATE media_asset SET status='FAILED',error_code=?,claim_token=NULL,lease_expires_at=NULL,next_cleanup_at=?,updated_at=? WHERE id=? AND status='UPLOADING' AND claim_token=?",failure.code,Timestamp.from(clock.instant()),Timestamp.from(clock.instant()),id,claim.token()));
            throw failure;
        }
        // A DB failure after storage succeeds deliberately leaves UPLOADING; recovery inspects the immutable object.
    }
    private boolean finish(UUID id,UUID fence,ObjectStorageProvider.Metadata stored,Actor actor,HttpServletRequest request,String action) {
        return Boolean.TRUE.equals(tx.execute(status->{
            int changed=db.update("UPDATE media_asset SET status='READY',error_code=NULL,claim_token=NULL,lease_expires_at=NULL,updated_at=? WHERE id=? AND status='UPLOADING' AND claim_token=? AND lease_expires_at>?",Timestamp.from(clock.instant()),id,fence,Timestamp.from(clock.instant()));
            if(changed==1)audit.write(actor,action,"MEDIA_ASSET",id.toString(),Map.of("status","UPLOADING"),Map.of("status","READY","size_bytes",stored.sizeBytes()),request);return changed==1;
        }));
    }
    public Content content(UUID id){Asset asset=metadata(id);if(!asset.status().equals("READY"))throw new Failure(409,"MEDIA_NOT_READY");return new Content(asset,provider.read(asset.object_key()));}
    public Asset delete(UUID id,HttpServletRequest request) {
        Actor actor=guard.actor();boolean work=Boolean.TRUE.equals(tx.execute(status->{
            var row=row(id,true);owner(actor,row);if("DELETED".equals(row.get("status")))return false;
            if("UPLOADING".equals(row.get("status")))throw new Failure(409,"UPLOAD_IN_PROGRESS");
            if(!"DELETE_PENDING".equals(row.get("status"))) {
                db.update("UPDATE media_asset SET status='DELETE_PENDING',upload_token_hash=NULL,error_code=NULL,next_cleanup_at=?,updated_at=? WHERE id=?",Timestamp.from(clock.instant()),Timestamp.from(clock.instant()),id);
                audit.write(actor,"media.delete-requested","MEDIA_ASSET",id.toString(),Map.of("status",row.get("status")),Map.of("status","DELETE_PENDING"),request);
            }return true;
        }));
        if(work)cleanup(id);return metadata(id);
    }
    /** One short DB claim, provider IO, then fenced DB completion. Safe for multiple schedulers. */
    private void cleanup(UUID preferred) {
        UUID token=UUID.randomUUID();Instant now=clock.instant();
        Map<String,Object> claim=tx.execute(status->{
            var rows=db.queryForList("""
                SELECT * FROM media_asset WHERE status IN ('DELETE_PENDING','FAILED','EXPIRED') AND next_cleanup_at<=?
                AND (cleanup_lease_expires_at IS NULL OR cleanup_lease_expires_at<=?)
                """+(preferred==null?"":" AND id=?")+" ORDER BY next_cleanup_at LIMIT 1 FOR UPDATE SKIP LOCKED",preferred==null?new Object[]{Timestamp.from(now),Timestamp.from(now)}:new Object[]{Timestamp.from(now),Timestamp.from(now),preferred});
            if(rows.isEmpty())return null;var row=rows.getFirst();db.update("UPDATE media_asset SET cleanup_claim_token=?,cleanup_lease_expires_at=? WHERE id=?",token,Timestamp.from(now.plusSeconds(leaseSeconds)),row.get("id"));return row;
        });
        if(claim==null)return;String error=null;
        try {if(!provider.providerId().equals(claim.get("storage_provider")))throw new Failure(503,"OBJECT_PROVIDER_UNAVAILABLE");provider.delete((String)claim.get("object_key"));}catch(Failure failure){error=failure.code;}
        String resultError=error;
        tx.executeWithoutResult(status->{
            int attempt=((Number)claim.get("cleanup_attempts")).intValue()+1;long delay=Math.min(3600,30L*(1L<<Math.min(7,attempt-1)));
            db.update("UPDATE media_asset SET status=CASE WHEN status='DELETE_PENDING' AND ?::text IS NULL THEN 'DELETED' ELSE status END,error_code=CASE WHEN ?::text IS NOT NULL THEN ? ELSE error_code END,cleanup_claim_token=NULL,cleanup_lease_expires_at=NULL,cleanup_attempts=?,next_cleanup_at=?,updated_at=? WHERE id=? AND cleanup_claim_token=?",resultError,resultError,resultError,attempt,Timestamp.from(clock.instant().plusSeconds(resultError==null?300:delay)),Timestamp.from(clock.instant()),claim.get("id"),token);
        });
    }
    public void recover() {
        try{provider.reapAbandonedUploads(clock.instant().minusSeconds(86400));}catch(Failure unavailable){/* Durable media records are recovered independently. */}
        Instant now=clock.instant();tx.executeWithoutResult(status->db.update("UPDATE media_asset SET status='EXPIRED',upload_token_hash=NULL,error_code='UPLOAD_GRANT_EXPIRED',next_cleanup_at=?,updated_at=? WHERE status='UPLOAD_PENDING' AND upload_expires_at<=?",Timestamp.from(now),Timestamp.from(now),Timestamp.from(now)));
        for(int i=0;i<16;i++) {
            UUID fence=UUID.randomUUID();Map<String,Object> claim=tx.execute(status->{
                var rows=db.queryForList("SELECT * FROM media_asset WHERE status='UPLOADING' AND lease_expires_at<=? ORDER BY lease_expires_at LIMIT 1 FOR UPDATE SKIP LOCKED",Timestamp.from(clock.instant()));
                if(rows.isEmpty())return null;var row=rows.getFirst();db.update("UPDATE media_asset SET claim_token=?,lease_expires_at=? WHERE id=?",fence,Timestamp.from(clock.instant().plusSeconds(leaseSeconds)),row.get("id"));return row;
            });
            if(claim==null)break;
            try {
                if(!provider.providerId().equals(claim.get("storage_provider")))throw new Failure(503,"OBJECT_PROVIDER_UNAVAILABLE");
                var stored=provider.metadata((String)claim.get("object_key"));
                if(stored.isPresent()&&stored.get().sizeBytes()==((Number)claim.get("size_bytes")).longValue()&&stored.get().sha256().equals(claim.get("sha256"))&&stored.get().mime().equals(claim.get("mime"))) {
                    Actor owner=new Actor((UUID)claim.get("owner_id"),Actor.Realm.valueOf((String)claim.get("realm")),null,null,(UUID)claim.get("owner_session_id"),Set.of(),Set.of());
                    finish((UUID)claim.get("id"),fence,stored.get(),owner,null,"media.upload-recovered");
                } else tx.executeWithoutResult(status->db.update("UPDATE media_asset SET status='FAILED',claim_token=NULL,lease_expires_at=NULL,error_code='UPLOAD_INTERRUPTED',next_cleanup_at=?,updated_at=? WHERE id=? AND claim_token=?",Timestamp.from(clock.instant()),Timestamp.from(clock.instant()),claim.get("id"),fence));
            } catch(Failure unavailable) { /* Retain the claim and recover when storage is healthy again. */ }
        }
        for(int i=0;i<16;i++)cleanup(null);
    }
}
