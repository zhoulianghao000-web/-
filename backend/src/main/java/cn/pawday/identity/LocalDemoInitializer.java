package cn.pawday.identity;

import cn.pawday.audit.AuditWriter;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/** Explicit local-only fixtures. Credentials never have defaults or appear in logs. */
@Component
@Profile("local & !production")
@ConditionalOnProperty(name="pawday.demo.enabled",havingValue="true")
public class LocalDemoInitializer implements ApplicationRunner {
    private final JdbcTemplate db;private final TransactionTemplate tx;private final Environment env;
    private final PasswordEncoder encoder;private final Crypto crypto;private final AuditWriter audit;
    public LocalDemoInitializer(JdbcTemplate db,TransactionTemplate tx,Environment env,PasswordEncoder encoder,Crypto crypto,AuditWriter audit) {
        this.db=db;this.tx=tx;this.env=env;this.encoder=encoder;this.crypto=crypto;this.audit=audit;
    }
    @Override public void run(ApplicationArguments args) {
        String merchantPassword=password("PAWDAY_DEMO_MERCHANT_PASSWORD"),adminPassword=password("PAWDAY_DEMO_ADMIN_PASSWORD");
        byte[] secret=Base64.getDecoder().decode(env.getRequiredProperty("PAWDAY_DEMO_ADMIN_TOTP_BASE64"));
        if(secret.length<20) throw new IllegalArgumentException("Local demo TOTP requires at least 20 bytes");
        tx.executeWithoutResult(status->{
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended('pawday-local-demo',0))");
            UUID merchantRole=role("MERCHANT","LOCAL_STORE_READER",List.of("store.read"));
            UUID adminRole=role("ADMIN","LOCAL_PLATFORM_ADMIN",List.of("store.read","access.role.read","access.role.write","audit.read","outbox.read","outbox.replay","search.read","search.manage","pet.taxonomy.read","pet.taxonomy.write"));
            for(String label:List.of("a","b")) {
                UUID merchant=id("merchant-"+label),store=id("store-"+label),principal=id("staff-"+label);
                db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE') ON CONFLICT(id) DO NOTHING",merchant,"LOCAL DEMO Merchant "+label);
                db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,?) ON CONFLICT(id) DO NOTHING",store,merchant,"LOCAL DEMO Store "+label);
                db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash) VALUES (?,'MERCHANT',?,?,?) ON CONFLICT(id) DO NOTHING",principal,merchant,"local-staff-"+label,encoder.encode(merchantPassword));
                db.update("INSERT INTO principal_role(principal_id,role_id,realm) VALUES (?,?,'MERCHANT') ON CONFLICT DO NOTHING",principal,merchantRole);
                db.update("INSERT INTO principal_store_scope(principal_id,merchant_id,store_id) VALUES (?,?,?) ON CONFLICT DO NOTHING",principal,merchant,store);
            }
            UUID admin=id("admin");
            db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,'ADMIN','local-admin',?,?) ON CONFLICT(id) DO NOTHING",admin,encoder.encode(adminPassword),crypto.encrypt(secret));
            db.update("INSERT INTO principal_role(principal_id,role_id,realm) VALUES (?,?,'ADMIN') ON CONFLICT DO NOTHING",admin,adminRole);
            audit.write(null,"local.demo.ensure","LOCAL_FIXTURE",null,Map.of(),Map.of("fixture_version","M2.1"),null);
        });
    }
    private String password(String key) {
        String value=env.getRequiredProperty(key);
        if(value.length()<12 || value.getBytes(StandardCharsets.UTF_8).length>72) throw new IllegalArgumentException("Local demo password must be 12+ characters and at most 72 UTF-8 bytes");
        return value;
    }
    private UUID role(String realm,String code,List<String> permissions) {
        UUID id=id(code);
        db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,?) ON CONFLICT(id) DO NOTHING",id,realm,code,"LOCAL DEMO "+code);
        for(String permission:permissions) db.update("INSERT INTO role_permission(role_id,permission_id) SELECT ?,id FROM permission WHERE code=? ON CONFLICT DO NOTHING",id,permission);
        return id;
    }
    private static UUID id(String name) {return UUID.nameUUIDFromBytes(("pawday-local-demo:"+name).getBytes(StandardCharsets.UTF_8));}
}
