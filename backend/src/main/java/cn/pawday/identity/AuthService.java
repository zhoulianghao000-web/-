package cn.pawday.identity;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.beans.factory.annotation.Value;

@Service
public class AuthService {
    public record Tokens(String access_token,String refresh_token,long expires_in,UUID session_id,UUID user_id) {}
    public record Receipt(UUID id,long version,Instant accepted_at) {}
    public record Proof(String reverify_token,String action,Instant expires_at) {}
    private final JdbcTemplate db;
    private final TransactionTemplate tx;
    private final Crypto crypto;
    private final PasswordEncoder passwords;
    private final cn.pawday.outbox.OutboxWriter outbox;
    private final Clock clock;
    private final AuditWriter audit;
    private final long accessSeconds,refreshSeconds,proofSeconds;
    private final String dummyHash;
    public AuthService(JdbcTemplate db,TransactionTemplate tx,Crypto crypto,PasswordEncoder passwords,cn.pawday.outbox.OutboxWriter outbox,Clock clock,AuditWriter audit,
        @Value("${pawday.auth.access-seconds:900}") long accessSeconds,
        @Value("${pawday.auth.refresh-seconds:2592000}") long refreshSeconds,
        @Value("${pawday.auth.reverify-seconds:300}") long proofSeconds) {
        this.db=db;this.tx=tx;this.crypto=crypto;this.passwords=passwords;this.outbox=outbox;this.clock=clock;this.audit=audit;
        this.accessSeconds=accessSeconds;this.refreshSeconds=refreshSeconds;this.proofSeconds=proofSeconds;
        if(accessSeconds<1 || refreshSeconds<accessSeconds || proofSeconds<1) throw new IllegalArgumentException("Invalid auth TTL policy");
        dummyHash=passwords.encode(crypto.token());
    }
    private Timestamp now() {return Timestamp.from(clock.instant());}
    // A separate committed operation: failed authentication must not roll back abuse counters.
    public void rateLimit(String identity) {
        Instant start=Instant.ofEpochSecond(clock.instant().getEpochSecond()/60*60);
        int attempts=db.queryForObject("""
            INSERT INTO auth_rate_bucket(subject_hash,window_start,attempt_count) VALUES (?,?,1)
            ON CONFLICT(subject_hash) DO UPDATE SET
              attempt_count=CASE WHEN auth_rate_bucket.window_start=excluded.window_start THEN auth_rate_bucket.attempt_count+1 ELSE 1 END,
              window_start=excluded.window_start RETURNING attempt_count
            """,Integer.class,crypto.hash(identity),Timestamp.from(start));
        if(attempts>10) throw new Failure(429,"RATE_LIMITED");
    }
    public Receipt requestCode(String phone,String purpose,Actor actor,HttpServletRequest r) {
        rateLimit("sms-ip:"+r.getRemoteAddr());rateLimit("sms-phone:"+phone);
        UUID session=null;
        if(purpose.equals("REVERIFY")) {
            if(actor==null || actor.realm()!=Actor.Realm.CONSUMER) throw new Failure(401,"AUTH_REQUIRED");
            String ownPhone=db.queryForObject("SELECT phone_e164 FROM app_user WHERE id=?",String.class,actor.userId());
            if(!phone.equals(ownPhone)) throw new Failure(403,"PERMISSION_DENIED");
            session=actor.sessionId();
        }
        UUID id=UUID.randomUUID(),boundSession=session;String code=crypto.otp();
        tx.executeWithoutResult(s-> {
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",phone+":"+purpose+":"+boundSession);
            db.update("UPDATE otp_challenge SET consumed_at=? WHERE phone_e164=? AND purpose=? AND consumed_at IS NULL AND session_id IS NOT DISTINCT FROM ?",now(),phone,purpose,boundSession);
            db.update("INSERT INTO otp_challenge(id,phone_e164,purpose,session_id,code_hash,expires_at,created_at) VALUES (?,?,?,?,?,?,?)",id,phone,purpose,boundSession,crypto.otpHash(id.toString(),code),Timestamp.from(clock.instant().plusSeconds(300)),now());
            db.update("UPDATE otp_challenge SET delivery_secret_ciphertext=? WHERE id=?",crypto.encrypt(code.getBytes(java.nio.charset.StandardCharsets.UTF_8)),id);
            outbox.append("OTP_CHALLENGE",id.toString(),"otp.sms.requested",1,Map.of("challenge_id",id.toString()),r==null?null:(String)r.getAttribute("correlation_id"));
            audit.write(actor,"auth.otp.requested","OTP_CHALLENGE",id.toString(),Map.of(),Map.of("purpose",purpose,"phone",phone),r);
        });
        return new Receipt(id,0,clock.instant());
    }
    private boolean consumeOtp(String phone,String purpose,UUID session,String code) {
        var rows=db.queryForList("SELECT * FROM otp_challenge WHERE phone_e164=? AND purpose=? AND session_id IS NOT DISTINCT FROM ? AND consumed_at IS NULL ORDER BY created_at DESC,id DESC LIMIT 1 FOR UPDATE",phone,purpose,session);
        if(rows.isEmpty()) return false;
        var row=rows.getFirst(); UUID id=(UUID)row.get("id");
        if(row.get("consumed_at")!=null || !((Timestamp)row.get("expires_at")).toInstant().isAfter(clock.instant()) || ((Number)row.get("attempts")).intValue()>=5) return false;
        boolean valid=crypto.equal((String)row.get("code_hash"),crypto.otpHash(id.toString(),code));
        db.update("UPDATE otp_challenge SET attempts=attempts+1,consumed_at=? WHERE id=?",valid?now():null,id);
        return valid;
    }
    public Tokens consumerLogin(String phone,String code,String device,HttpServletRequest r) {
        rateLimit("consumer-login:"+phone);rateLimit("login-ip:"+r.getRemoteAddr());
        Tokens result=tx.execute(s-> {
            if(!consumeOtp(phone,"LOGIN",null,code)) {audit.write(null,"auth.login.failed","IDENTITY",null,Map.of(),Map.of("realm","CONSUMER"),r);return null;}
            UUID user=UUID.randomUUID();
            db.update("INSERT INTO app_user(id,status,phone_e164) VALUES (?,'ACTIVE',?) ON CONFLICT(phone_e164) WHERE deleted_at IS NULL AND phone_e164 IS NOT NULL DO NOTHING",user,phone);
            var users=db.queryForList("SELECT id,status FROM app_user WHERE phone_e164=? AND deleted_at IS NULL",phone);
            if(users.isEmpty() || !users.getFirst().get("status").equals("ACTIVE")) return null;
            user=(UUID)users.getFirst().get("id");UUID principal=UUID.randomUUID();
            db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?) ON CONFLICT(user_id) DO NOTHING",principal,user);
            var principals=db.queryForList("SELECT id FROM identity_principal WHERE user_id=? AND status='ACTIVE'",user);
            if(principals.isEmpty()) return null;principal=(UUID)principals.getFirst().get("id");
            Tokens tokens=newSession(principal,user,device);
            audit.write(load(tokens.access_token()).orElseThrow(),"auth.login.succeeded","AUTH_SESSION",tokens.session_id().toString(),Map.of(),Map.of("realm","CONSUMER"),r);return tokens;
        });
        if(result==null) throw new Failure(401,"INVALID_CREDENTIALS");return result;
    }
    private boolean staffCredentials(Map<String,Object> row,String password,String totp) {
        if(password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72) return false;
        boolean matched=passwords.matches(password,row==null?dummyHash:(String)row.get("password_hash"));
        if(row==null || !matched || !row.get("status").equals("ACTIVE")) return false;
        if(row.get("mfa_secret_ciphertext")!=null) {
            long step=crypto.matchTotp((String)row.get("mfa_secret_ciphertext"),totp);
            if(step<0) return false;
            return db.update("UPDATE identity_principal SET last_totp_step=? WHERE id=? AND last_totp_step<?",step,row.get("id"),step)==1;
        }
        return !row.get("realm").equals("ADMIN");
    }
    public Tokens staffLogin(Actor.Realm realm,String login,String password,String totp,String device,HttpServletRequest r) {
        if(realm==Actor.Realm.CONSUMER) throw new Failure(403,"PERMISSION_DENIED");
        rateLimit("staff-login:"+realm+":"+login);rateLimit("login-ip:"+r.getRemoteAddr());
        Tokens tokens=tx.execute(s-> {
            var rows=db.queryForList("SELECT * FROM identity_principal WHERE realm=? AND login_name=? FOR UPDATE",realm.name(),login);
            var row=rows.isEmpty()?null:rows.getFirst();
            if(!staffCredentials(row,password,totp)) {audit.write(null,"auth.login.failed","IDENTITY",null,Map.of(),Map.of("realm",realm.name()),r);return null;}
            if(realm==Actor.Realm.MERCHANT && db.queryForObject("SELECT count(*) FROM merchant WHERE id=? AND status='ACTIVE'",Integer.class,row.get("merchant_id"))==0) return null;
            Tokens value=newSession((UUID)row.get("id"),null,device);
            audit.write(load(value.access_token()).orElseThrow(),"auth.login.succeeded","AUTH_SESSION",value.session_id().toString(),Map.of(),Map.of("realm",realm.name()),r);return value;
        });
        if(tokens==null) throw new Failure(401,"INVALID_CREDENTIALS");return tokens;
    }
    private Tokens newSession(UUID principal,UUID user,String device) {
        UUID id=UUID.randomUUID();String access=crypto.token(),refresh=crypto.token();
        db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,?,?,?,?)",id,principal,crypto.hash(access),device,Timestamp.from(clock.instant().plusSeconds(accessSeconds)),Timestamp.from(clock.instant().plusSeconds(refreshSeconds)),now());
        db.update("INSERT INTO auth_refresh_token(token_hash,session_id,status,created_at) VALUES (?,?,'ACTIVE',?)",crypto.hash(refresh),id,now());
        return new Tokens(access,refresh,accessSeconds,id,user);
    }
    public Optional<Actor> load(String token) {
        if(token==null || token.length()>128) return Optional.empty();
        var rows=db.queryForList("""
            SELECT p.id,p.realm,p.user_id,p.merchant_id,s.id AS session_id FROM auth_session s
            JOIN identity_principal p ON p.id=s.principal_id
            LEFT JOIN app_user u ON u.id=p.user_id LEFT JOIN merchant m ON m.id=p.merchant_id
            WHERE s.access_token_hash=? AND s.revoked_at IS NULL AND s.expires_at>?
              AND p.status='ACTIVE' AND (p.realm<>'CONSUMER' OR (u.status='ACTIVE' AND u.deleted_at IS NULL))
              AND (p.realm<>'MERCHANT' OR m.status='ACTIVE')
            """,crypto.hash(token),now());
        if(rows.isEmpty()) return Optional.empty();var row=rows.getFirst();UUID principal=(UUID)row.get("id");
        Set<String> roles=new HashSet<>(db.queryForList("SELECT r.code FROM principal_role pr JOIN role r ON r.id=pr.role_id AND r.scope_type=pr.realm WHERE pr.principal_id=?",String.class,principal));
        Set<String> permissions=new HashSet<>(db.queryForList("SELECT DISTINCT p.code FROM principal_role pr JOIN role r ON r.id=pr.role_id AND r.scope_type=pr.realm JOIN role_permission rp ON rp.role_id=r.id JOIN permission p ON p.id=rp.permission_id WHERE pr.principal_id=?",String.class,principal));
        return Optional.of(new Actor(principal,Actor.Realm.valueOf((String)row.get("realm")),(UUID)row.get("user_id"),(UUID)row.get("merchant_id"),(UUID)row.get("session_id"),Set.copyOf(permissions),Set.copyOf(roles)));
    }
    public Tokens refresh(Actor.Realm realm,String token,HttpServletRequest r) {
        rateLimit("refresh-ip:"+r.getRemoteAddr());
        Tokens result=tx.execute(s-> {
            var rows=db.queryForList("""
                SELECT t.status AS token_status,s.*,p.realm,p.user_id,p.status AS principal_status,p.merchant_id
                FROM auth_refresh_token t JOIN auth_session s ON s.id=t.session_id JOIN identity_principal p ON p.id=s.principal_id
                WHERE t.token_hash=? FOR UPDATE OF t,s
                """,crypto.hash(token));
            if(rows.isEmpty()) return null;var row=rows.getFirst();
            if(!row.get("realm").equals(realm.name())) return null;
            UUID session=(UUID)row.get("id");
            if(!row.get("token_status").equals("ACTIVE")) {
                db.update("UPDATE auth_session SET revoked_at=? WHERE id=?",now(),session);
                audit.write(null,"auth.refresh.replay","AUTH_SESSION",session.toString(),Map.of(),Map.of("revoked",true),r);return null;
            }
            if(row.get("revoked_at")!=null || !row.get("principal_status").equals("ACTIVE") || !((Timestamp)row.get("refresh_expires_at")).toInstant().isAfter(clock.instant())) return null;
            if(realm==Actor.Realm.CONSUMER && db.queryForObject("SELECT count(*) FROM app_user WHERE id=? AND status='ACTIVE' AND deleted_at IS NULL",Integer.class,row.get("user_id"))==0) return null;
            if(realm==Actor.Realm.MERCHANT && db.queryForObject("SELECT count(*) FROM merchant WHERE id=? AND status='ACTIVE'",Integer.class,row.get("merchant_id"))==0) return null;
            db.update("UPDATE auth_refresh_token SET status='CONSUMED',consumed_at=? WHERE token_hash=?",now(),crypto.hash(token));
            String access=crypto.token(),refresh=crypto.token();
            Instant expiry=clock.instant().plusSeconds(accessSeconds),refreshExpiry=((Timestamp)row.get("refresh_expires_at")).toInstant();
            if(expiry.isAfter(refreshExpiry)) expiry=refreshExpiry;
            db.update("UPDATE auth_session SET access_token_hash=?,expires_at=?,version=version+1 WHERE id=?",crypto.hash(access),Timestamp.from(expiry),session);
            db.update("INSERT INTO auth_refresh_token(token_hash,session_id,status,created_at) VALUES (?,?,'ACTIVE',?)",crypto.hash(refresh),session,now());
            Tokens value=new Tokens(access,refresh,java.time.Duration.between(clock.instant(),expiry).toSeconds(),session,(UUID)row.get("user_id"));
            audit.write(load(access).orElseThrow(),"auth.refresh.rotated","AUTH_SESSION",session.toString(),Map.of(),Map.of("rotated",true),r);return value;
        });
        if(result==null) throw new Failure(401,"INVALID_REFRESH_TOKEN");return result;
    }
    public Proof reverify(Actor actor,String action,String password,String otp,String totp,HttpServletRequest r) {
        if(!Set.of("access.role.write","session.revoke-others","outbox.replay","search.rebuild","search.reconcile","search.retry").contains(action)) throw new Failure(422,"REVERIFY_ACTION_NOT_ALLOWED");
        if(!action.equals("session.revoke-others") && !actor.permissions().contains(action.startsWith("search.")?"search.manage":action)) throw new Failure(403,"PERMISSION_DENIED");
        rateLimit("reverify:"+actor.principalId());
        Proof result=tx.execute(s-> {
            boolean valid;
            if(actor.realm()==Actor.Realm.CONSUMER) {
                String phone=db.queryForObject("SELECT phone_e164 FROM app_user WHERE id=?",String.class,actor.userId());valid=consumeOtp(phone,"REVERIFY",actor.sessionId(),otp==null?"":otp);
            } else {
                var row=db.queryForMap("SELECT * FROM identity_principal WHERE id=? FOR UPDATE",actor.principalId());valid=staffCredentials(row,password==null?"":password,totp);
            }
            if(!valid) {audit.write(actor,"auth.reverify.failed","AUTH_SESSION",actor.sessionId().toString(),Map.of(),Map.of("action",action),r);return null;}
            String proof=crypto.token();Instant expires=clock.instant().plusSeconds(proofSeconds);
            db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(proof),actor.sessionId(),action,Timestamp.from(expires),now());
            audit.write(actor,"auth.reverify.issued","AUTH_SESSION",actor.sessionId().toString(),Map.of(),Map.of("action",action),r);return new Proof(proof,action,expires);
        });
        if(result==null) throw new Failure(401,"INVALID_CREDENTIALS");return result;
    }
    // Invoked inside the same transaction as the protected business mutation; rollback restores the grant.
    public void consumeProof(Actor actor,String action,String proof) {
        if(proof==null || proof.length()>128) throw new Failure(403,"OPERATION_REQUIRES_REVERIFY");
        int changed=db.update("""
            UPDATE reverify_grant g SET used_at=? WHERE token_hash=? AND session_id=? AND action=? AND used_at IS NULL AND expires_at>?
              AND EXISTS(SELECT 1 FROM auth_session s JOIN identity_principal p ON p.id=s.principal_id
                         WHERE s.id=g.session_id AND s.revoked_at IS NULL AND s.expires_at>? AND p.status='ACTIVE')
            """,now(),crypto.hash(proof),actor.sessionId(),action,now(),now());
        if(changed!=1) throw new Failure(403,"OPERATION_REQUIRES_REVERIFY");
    }
    public void revoke(Actor actor,UUID session,HttpServletRequest r) {
        tx.executeWithoutResult(s-> {
            int count=db.update("UPDATE auth_session SET revoked_at=coalesce(revoked_at,?) WHERE id=? AND principal_id=?",now(),session,actor.principalId());
            if(count==0) throw new Failure(404,"RESOURCE_NOT_FOUND");
            db.update("UPDATE auth_refresh_token SET status='REVOKED' WHERE session_id=? AND status='ACTIVE'",session);
            audit.write(actor,"auth.session.revoked","AUTH_SESSION",session.toString(),Map.of(),Map.of("revoked",true),r);
        });
    }
    public void revokeOthers(Actor actor,String proof,HttpServletRequest r) {
        tx.executeWithoutResult(s-> {
            consumeProof(actor,"session.revoke-others",proof);
            db.update("UPDATE auth_session SET revoked_at=coalesce(revoked_at,?) WHERE principal_id=? AND id<>?",now(),actor.principalId(),actor.sessionId());
            audit.write(actor,"auth.sessions.revoked-others","AUTH_SESSION",actor.sessionId().toString(),Map.of(),Map.of("revoked_others",true),r);
        });
    }
}
