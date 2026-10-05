package cn.pawday;

import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.mock.env.MockEnvironment;
import java.time.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(IdentitySecurityIntegrationTests.FixtureBeans.class)
class IdentitySecurityIntegrationTests {
    static final EmbeddedPostgres PG;
    static {try {PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");
        r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
        r.add("pawday.search.enabled",()->false);r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);
        r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);
    }
    static final List<Map<String,Object>> SAMPLES=new CopyOnWriteArrayList<>();
    @AfterAll static void closeDatabase() throws Exception {
        java.nio.file.Files.writeString(java.nio.file.Path.of("target/contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();
    }
    static class MutableClock extends Clock {
        volatile Instant current=Instant.parse("2026-10-03T00:00:00Z");
        void advance(long seconds){current=current.plusSeconds(seconds);}
        @Override public ZoneId getZone(){return ZoneOffset.UTC;}
        @Override public Clock withZone(ZoneId zone){return this;}
        @Override public Instant instant(){return current;}
    }
    static class Inbox implements SmsGateway {
        final Map<String,String> codes=new ConcurrentHashMap<>();
        public void send(String id,String phone,String code){codes.put(phone,code);}
    }
    @TestConfiguration static class FixtureBeans {
        @Bean @Primary MutableClock testClock(){return new MutableClock();}
        @Bean @Primary Inbox testSms(){return new Inbox();}
    }
    @LocalServerPort int port;
    @Autowired JdbcTemplate db;@Autowired Crypto crypto;@Autowired PasswordEncoder passwords;
    @Autowired MutableClock clock;@Autowired Inbox inbox;@Autowired AuditWriter audit;@Autowired AuthService auth;
    @Autowired cn.pawday.outbox.InboxConsumer eventConsumer;@Autowired cn.pawday.outbox.SmsDeliveryWorker smsWorker;
    static String fixtureHash;
    static final String PASSWORD="TEST-ONLY-strong-password-21";
    static final byte[] MFA="12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    UUID merchantA,merchantB,storeA,storeAOther,storeB,staffA,staffB,admin,reader,merchantRole,adminRole;
    final JsonMapper json=JsonMapper.builder().build();
    final HttpClient client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    record Response(int status,JsonNode body) {JsonNode data(){return body.get("data");}String token(){return data().get("access_token").asString();}}
    Response call(String method,String path,Object payload,String token,Map<String,String> headers) {
        try {
            var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));
            if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);
            if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));
            var r=client.send(b.build(),HttpResponse.BodyHandlers.ofString());var parsed=json.readTree(r.body());
            var safe=json.readTree(r.body());if(safe.get("data")!=null && safe.get("data").isObject()) {
                var data=(tools.jackson.databind.node.ObjectNode)safe.get("data");
                for(String field:List.of("access_token","refresh_token","reverify_token"))if(data.has(field))data.put(field,"A".repeat(43));
            }
            SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",r.statusCode(),"response",safe));
            // Identity-only regression fixture. The separate RabbitOutboxIT suite exercises the real AMQP path.
            if(path.equals("/consumer/auth/phone/request-code") && r.statusCode()==200) {
                var events=db.queryForList("SELECT * FROM outbox_event WHERE status='PENDING' AND transport_kind='EVENT'");
                for(var event:events)eventConsumer.process(new cn.pawday.outbox.EventEnvelope((UUID)event.get("id"),"otp.sms.requested",1,"OTP_CHALLENGE",event.get("aggregate_id").toString(),null,1,0,Map.of("challenge_id",event.get("aggregate_id").toString())));
                while(smsWorker.sendOne()) {}
            }
            return new Response(r.statusCode(),parsed);
        } catch(Exception ex){throw new AssertionError("HTTP call failed: "+path,ex);}
    }
    Response call(String method,String path,Object body,String token){return call(method,path,body,token,Map.of());}
    Response consumer(String phone){assertEquals(200,call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","LOGIN"),null).status());var r=call("POST","/consumer/auth/phone/verify",Map.of("phone_e164",phone,"code",inbox.codes.get(phone),"device_id","TEST-DEVICE"),null);assertEquals(200,r.status());return r;}
    Response staff(String realm,String login){Map<String,Object> body=new HashMap<>(Map.of("login_name",login,"password",PASSWORD,"device_id","TEST-DEVICE"));if(realm.equals("admin"))body.put("totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30));var r=call("POST","/"+realm+"/auth/login",body,null);assertEquals(200,r.status());return r;}
    String proof(Response adminSession,String action){clock.advance(60);var r=call("POST","/admin/auth/reverify",Map.of("action",action,"password",PASSWORD,"totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),adminSession.token());assertEquals(200,r.status());return r.data().get("reverify_token").asString();}
    Map<String,Object> roleBody(String name){return Map.of("name",name,"permission_codes",List.of("access.role.read"));}
    Map<String,String> writeHeaders(String proof,String key){return proof==null?Map.of("Idempotency-Key",key):Map.of("X-Reverify-Token",proof,"Idempotency-Key",key);}
    @BeforeEach void fixture(){
        clock.current=Instant.parse("2026-10-03T00:00:00Z");inbox.codes.clear();
        db.execute("ALTER TABLE audit_event DISABLE TRIGGER audit_event_no_truncate");db.execute("ALTER TABLE inventory_adjustments DISABLE TRIGGER inventory_adjustment_no_truncate");
        try {db.execute("TRUNCATE outbox_replay_command,processed_event,sms_delivery,outbox_event,identity_command,reverify_grant,auth_refresh_token,auth_session,otp_challenge,auth_rate_bucket,principal_store_scope,principal_role,identity_principal,merchant_store,merchant,app_user,role_permission,role,audit_event CASCADE");}
        finally {db.execute("ALTER TABLE audit_event ENABLE TRIGGER audit_event_no_truncate");db.execute("ALTER TABLE inventory_adjustments ENABLE TRIGGER inventory_adjustment_no_truncate");}
        if(fixtureHash==null) fixtureHash=passwords.encode(PASSWORD);
        merchantA=UUID.randomUUID();merchantB=UUID.randomUUID();storeA=UUID.randomUUID();storeAOther=UUID.randomUUID();storeB=UUID.randomUUID();staffA=UUID.randomUUID();staffB=UUID.randomUUID();admin=UUID.randomUUID();reader=UUID.randomUUID();merchantRole=UUID.randomUUID();adminRole=UUID.randomUUID();
        db.update("INSERT INTO merchant(id,name,status) VALUES (?,'TEST merchant A','ACTIVE'),(?,'TEST merchant B','ACTIVE')",merchantA,merchantB);
        db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST A'),(?,?,'TEST A unassigned'),(?,?,'TEST B')",storeA,merchantA,storeAOther,merchantA,storeB,merchantB);
        db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash) VALUES (?,'MERCHANT',?,'test-merchant-a',?),(?,'MERCHANT',?,'test-merchant-b',?)",staffA,merchantA,fixtureHash,staffB,merchantB,fixtureHash);
        db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,'ADMIN','test-admin',?,?),(?,'ADMIN','test-reader',?,?)",admin,fixtureHash,crypto.encrypt(MFA),reader,fixtureHash,crypto.encrypt(MFA));
        db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,'MERCHANT','test-store-read','TEST store reader'),(?,'ADMIN','test-admin','TEST admin')",merchantRole,adminRole);
        db.update("INSERT INTO role_permission(role_id,permission_id) SELECT ?,id FROM permission WHERE code='store.read'",merchantRole);
        db.update("INSERT INTO role_permission(role_id,permission_id) SELECT ?,id FROM permission WHERE code IN ('access.role.read','access.role.write','audit.read')",adminRole);
        db.update("INSERT INTO principal_role(principal_id,role_id,realm) VALUES (?,?,'MERCHANT'),(?,?,'MERCHANT'),(?,?,'ADMIN')",staffA,merchantRole,staffB,merchantRole,admin,adminRole);
        db.update("INSERT INTO principal_store_scope(principal_id,merchant_id,store_id) VALUES (?,?,?),(?,?,?)",staffA,merchantA,storeA,staffB,merchantB,storeB);
    }
    @Test void migrationsAndHealthAreReal() throws Exception {
        assertEquals(12,db.queryForObject("SELECT count(*) FROM flyway_schema_history WHERE success",Integer.class));
        var r=client.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/actuator/health")).GET().build(),HttpResponse.BodyHandlers.ofString());assertEquals(200,r.statusCode());assertEquals("UP",json.readTree(r.body()).get("status").asString());
    }
    @Test void anonymousCannotUseAnyPrivateRealm(){for(String realm:List.of("consumer","merchant","admin"))assertEquals(401,call("GET","/"+realm+"/me",null,null).status());}
    @Test void tokensCannotCrossAnyIdentityBoundary(){var c=consumer("+8613800000001");var m=staff("merchant","test-merchant-a");var a=staff("admin","test-admin");for(var source:Map.of("consumer",c,"merchant",m,"admin",a).entrySet())for(String target:List.of("consumer","merchant","admin"))assertEquals(source.getKey().equals(target)?200:403,call("GET","/"+target+"/me",null,source.getValue().token()).status());}
    @Test void defaultBasicAuthIsDisabled(){assertEquals(401,call("GET","/consumer/me",null,null,Map.of("Authorization","Basic "+Base64.getEncoder().encodeToString("user:password".getBytes(StandardCharsets.UTF_8)))).status());}
    @Test void unknownFieldsCannotInjectMerchantIdentity(){assertEquals(400,call("POST","/merchant/auth/login",Map.of("login_name","test-merchant-a","password",PASSWORD,"device_id","TEST","merchant_id",merchantB.toString()),null).status());}
    @Test void consumerCannotRevokeAnotherOwnersDevice(){var a=consumer("+8613800000001");var b=consumer("+8613800000002");assertEquals(404,call("DELETE","/consumer/auth/sessions/"+b.data().get("session_id").asString(),null,a.token()).status());assertEquals(200,call("GET","/consumer/me",null,b.token()).status());}
    @Test void merchantScopeIncludesStoreIntersection(){var a=staff("merchant","test-merchant-a");assertEquals(200,call("GET","/merchant/stores/"+storeA,null,a.token()).status());assertEquals(404,call("GET","/merchant/stores/"+storeAOther,null,a.token()).status());assertEquals(404,call("GET","/merchant/stores/"+storeB,null,a.token()).status());assertEquals(1,call("GET","/merchant/stores",null,a.token()).data().size());}
    @Test void permissionUnionIsReadFromDbOnEveryRequest(){var m=staff("merchant","test-merchant-a");db.update("DELETE FROM role_permission WHERE role_id=?",merchantRole);assertEquals(403,call("GET","/merchant/stores",null,m.token()).status());var extra=UUID.randomUUID();db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,'MERCHANT','extra','TEST extra')",extra);db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code='store.read'",extra);db.update("INSERT INTO principal_role VALUES (?,?,'MERCHANT')",staffA,extra);assertEquals(200,call("GET","/merchant/stores",null,m.token()).status());assertEquals(404,call("GET","/merchant/stores/"+storeB,null,m.token()).status());}
    @Test void crossRealmRoleGrantFailsAtDatabaseBoundary(){assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->db.update("INSERT INTO principal_role VALUES (?,?,'MERCHANT')",staffA,adminRole));}
    @Test void suspendedMerchantAndDisabledConsumerLoseAccess(){var m=staff("merchant","test-merchant-a");db.update("UPDATE merchant SET status='SUSPENDED' WHERE id=?",merchantA);assertEquals(401,call("GET","/merchant/me",null,m.token()).status());var c=consumer("+8613800000001");db.update("UPDATE app_user SET status='LOCKED' WHERE id=?",UUID.fromString(c.data().get("user_id").asString()));assertEquals(401,call("GET","/consumer/me",null,c.token()).status());}
    @Test void logoutRevokesAccessAndRefresh(){var c=consumer("+8613800000001");assertEquals(200,call("POST","/consumer/auth/logout",Map.of(),c.token()).status());assertEquals(401,call("GET","/consumer/me",null,c.token()).status());assertEquals(401,call("POST","/consumer/auth/refresh",Map.of("refresh_token",c.data().get("refresh_token").asString()),null).status());}
    @Test void refreshRotatesAndReplayRevokesSession(){var c=consumer("+8613800000001");String original=c.data().get("refresh_token").asString();var rotated=call("POST","/consumer/auth/refresh",Map.of("refresh_token",original),null);assertEquals(200,rotated.status());assertEquals(401,call("GET","/consumer/me",null,c.token()).status());assertEquals(200,call("GET","/consumer/me",null,rotated.token()).status());assertEquals(401,call("POST","/consumer/auth/refresh",Map.of("refresh_token",original),null).status());assertEquals(401,call("GET","/consumer/me",null,rotated.token()).status());}
    @Test void refreshCannotChangeRealm(){var c=consumer("+8613800000001");assertEquals(401,call("POST","/admin/auth/refresh",Map.of("refresh_token",c.data().get("refresh_token").asString()),null).status());assertEquals(200,call("GET","/consumer/me",null,c.token()).status());}
    @Test void expiredAccessCanRefreshButExpiredRefreshCannot(){var c=consumer("+8613800000001");clock.advance(901);assertEquals(401,call("GET","/consumer/me",null,c.token()).status());var refresh=call("POST","/consumer/auth/refresh",Map.of("refresh_token",c.data().get("refresh_token").asString()),null);assertEquals(200,refresh.status());clock.advance(2592001);assertEquals(401,call("POST","/consumer/auth/refresh",Map.of("refresh_token",refresh.data().get("refresh_token").asString()),null).status());}
    @Test void otpCannotReplayOrSurviveFiveWrongAttempts(){var c=consumer("+8613800000001");String correct=inbox.codes.get("+8613800000001");assertEquals(401,call("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+8613800000001","code",correct,"device_id","TEST"),null).status());call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000002","purpose","LOGIN"),null);String wrong=inbox.codes.get("+8613800000002").equals("000000")?"111111":"000000";for(int i=0;i<5;i++)assertEquals(401,call("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+8613800000002","code",wrong,"device_id","TEST"),null).status());assertEquals(401,call("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+8613800000002","code",inbox.codes.get("+8613800000002"),"device_id","TEST"),null).status());}
    @Test void otpExpiresAndReverifyPurposeCannotAuthenticate(){call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000001","purpose","LOGIN"),null);clock.advance(301);assertEquals(401,call("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+8613800000001","code",inbox.codes.get("+8613800000001"),"device_id","TEST"),null).status());var c=consumer("+8613800000002");assertEquals(200,call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000002","purpose","REVERIFY"),c.token()).status());assertEquals(401,call("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+8613800000002","code",inbox.codes.get("+8613800000002"),"device_id","TEST"),null).status());}
    @Test void smsIsRateLimitedWithoutLoggingCodes(){for(int i=0;i<10;i++)assertEquals(200,call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000001","purpose","LOGIN"),null).status());assertEquals(429,call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000001","purpose","LOGIN"),null).status());}
    @Test void adminRequiresMfaAndRejectsTotpReplay(){var body=Map.of("login_name","test-admin","password",PASSWORD,"device_id","TEST");assertEquals(401,call("POST","/admin/auth/login",body,null).status());staff("admin","test-admin");assertEquals(401,call("POST","/admin/auth/login",Map.of("login_name","test-admin","password",PASSWORD,"device_id","TEST","totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),null).status());}
    @Test void totpMatchesRfc6238Vector(){assertEquals("287082",crypto.totp(MFA,1));}
    @Test void credentialSecretsNeverPersistInPlaintext(){var c=consumer("+8613800000001");assertNotEquals(c.token(),db.queryForObject("SELECT access_token_hash FROM auth_session",String.class));assertNotEquals(inbox.codes.get("+8613800000001"),db.queryForObject("SELECT code_hash FROM otp_challenge",String.class));assertNotEquals(Base64.getEncoder().encodeToString(MFA),db.queryForObject("SELECT mfa_secret_ciphertext FROM identity_principal WHERE id=?",String.class,admin));}
    @Test void roleWriteRequiresPermissionBeforeReverify(){var readerSession=staff("admin","test-reader");assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST denied"),readerSession.token(),writeHeaders(null,"test-idempotency-0001")).status());assertEquals(403,call("GET","/admin/audit",null,readerSession.token()).status());}
    @Test void missingWrongActionAndExpiredProofAreRejected(){var a=staff("admin","test-admin");assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST denied"),a.token(),writeHeaders(null,"test-idempotency-0001")).status());String wrong=proof(a,"session.revoke-others");assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST denied"),a.token(),writeHeaders(wrong,"test-idempotency-0002")).status());String expired=proof(a,"access.role.write");clock.advance(301);assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST denied"),a.token(),writeHeaders(expired,"test-idempotency-0003")).status());}
    @Test void proofCannotMoveToAnotherSession(){var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");clock.advance(60);var b=staff("admin","test-admin");assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST denied"),b.token(),writeHeaders(grant,"test-idempotency-0001")).status());}
    @Test void proofIsOneUseButOriginalIdempotencyKeyCanReplay(){var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");var headers=writeHeaders(grant,"test-idempotency-0001");var first=call("POST","/admin/access/roles",roleBody("TEST new role"),a.token(),headers);assertEquals(201,first.status());var retry=call("POST","/admin/access/roles",roleBody("TEST new role"),a.token(),headers);assertEquals(first.data().get("id"),retry.data().get("id"));assertEquals(409,call("POST","/admin/access/roles",roleBody("TEST changed"),a.token(),headers).status());assertEquals(403,call("POST","/admin/access/roles",roleBody("TEST second"),a.token(),writeHeaders(grant,"test-idempotency-0002")).status());}
    @Test void roleWriterCannotGrantPermissionsTheyDoNotHave(){var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");assertEquals(403,call("POST","/admin/access/roles",Map.of("name","TEST escalation","permission_codes",List.of("finance.commission.write")),a.token(),writeHeaders(grant,"test-idempotency-0001")).status());}
    @Test void versionConflictRollsBackGrantConsumption(){var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");var headers=new HashMap<>(writeHeaders(grant,"test-idempotency-0001"));headers.put("If-Match","\"99\"");assertEquals(409,call("PATCH","/admin/access/roles/"+adminRole,roleBody("TEST stale"),a.token(),headers).status());assertEquals(201,call("POST","/admin/access/roles",roleBody("TEST proof still usable"),a.token(),writeHeaders(grant,"test-idempotency-0002")).status());}
    @Test void auditInsertFailureRollsBackMutationAndProof(){var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");int before=db.queryForObject("SELECT count(*) FROM role",Integer.class);db.execute("CREATE FUNCTION test_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='access.role.write' THEN RAISE EXCEPTION 'TEST simulated audit failure'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER test_audit_failure BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION test_fail_audit()");try {assertEquals(503,call("POST","/admin/access/roles",roleBody("TEST rolled back"),a.token(),writeHeaders(grant,"test-idempotency-0001")).status());assertEquals(before,db.queryForObject("SELECT count(*) FROM role",Integer.class));}finally {db.execute("DROP TRIGGER test_audit_failure ON audit_event");db.execute("DROP FUNCTION test_fail_audit()");}assertEquals(201,call("POST","/admin/access/roles",roleBody("TEST rolled back"),a.token(),writeHeaders(grant,"test-idempotency-0001")).status());}
    @Test void auditIsRedactedImmutableAndCorrelated(){var a=staff("admin","test-admin");Actor actor=auth.load(a.token()).orElseThrow();audit.write(actor,"TEST.redaction","TEST",null,Map.of("password","SENSITIVE-ONE","nested",List.of(Map.of("refresh_token","SENSITIVE-TWO","phone_e164","+8613800001234","otp_code","123456"))),Map.of("Authorization","SENSITIVE-THREE"),null);String stored=db.queryForObject("SELECT before_json::text || after_json::text FROM audit_event WHERE action='TEST.redaction'",String.class);assertFalse(stored.contains("SENSITIVE"));assertFalse(stored.contains("123456"));assertFalse(stored.contains("+8613800001234"));assertTrue(stored.contains("***1234"));assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("UPDATE audit_event SET action='tampered'"));String grant=proof(a,"access.role.write");var response=call("POST","/admin/access/roles",roleBody("TEST audit"),a.token(),writeHeaders(grant,"test-idempotency-0001"));assertEquals(201,response.status());assertEquals(response.body().get("meta").get("request_id").asString(),db.queryForObject("SELECT request_id FROM audit_event WHERE action='access.role.write'",String.class));assertEquals(200,call("GET","/admin/audit",null,a.token()).status());}
    @Test void concurrentProofHasOnlyOneWinner() throws Exception {var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");try(var pool=Executors.newFixedThreadPool(2)){var x=pool.submit(()->call("POST","/admin/access/roles",roleBody("TEST race A"),a.token(),writeHeaders(grant,"test-idempotency-0001")).status());var y=pool.submit(()->call("POST","/admin/access/roles",roleBody("TEST race B"),a.token(),writeHeaders(grant,"test-idempotency-0002")).status());assertEquals(Set.of(201,403),Set.of(x.get(),y.get()));}}
    @Test void concurrentOtpHasOnlyOneSuccessfulLogin() throws Exception {String phone="+8613800000001";call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","LOGIN"),null);var body=Map.of("phone_e164",phone,"code",inbox.codes.get(phone),"device_id","TEST");try(var pool=Executors.newFixedThreadPool(2)){var x=pool.submit(()->call("POST","/consumer/auth/phone/verify",body,null).status());var y=pool.submit(()->call("POST","/consumer/auth/phone/verify",body,null).status());assertEquals(Set.of(200,401),Set.of(x.get(),y.get()));}}
    @Test void consumerReverificationCanRevokeOtherDevices(){String phone="+8613800000001";var first=consumer(phone);var second=consumer(phone);assertEquals(200,call("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","REVERIFY"),first.token()).status());var p=call("POST","/consumer/auth/reverify",Map.of("action","session.revoke-others","otp_code",inbox.codes.get(phone)),first.token());assertEquals(200,p.status());assertEquals(200,call("POST","/consumer/auth/sessions/revoke-others",Map.of(),first.token(),Map.of("X-Reverify-Token",p.data().get("reverify_token").asString())).status());assertEquals(401,call("GET","/consumer/me",null,second.token()).status());assertEquals(200,call("GET","/consumer/me",null,first.token()).status());}
    @Test void productionCannotEnableLocalSmsSink(){var env=new MockEnvironment().withProperty("pawday.auth.local-sms-enabled","true");env.setActiveProfiles("local","production");var gateway=new AuthInfrastructure().smsGateway(env);var error=assertThrows(Api.Failure.class,()->gateway.send("TEST","+8613800000001","123456"));assertEquals(503,error.status);}
    @Test void adminRoleReadAndSessionListHaveContractShape(){var a=staff("admin","test-admin");var roles=call("GET","/admin/access/roles",null,a.token());assertEquals(200,roles.status());assertTrue(roles.body().has("page"));assertEquals(200,call("GET","/admin/auth/sessions",null,a.token()).status());}
    @Test void auditCannotBeDeletedOrTruncated(){staff("admin","test-admin");assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("DELETE FROM audit_event"));assertThrows(org.springframework.dao.DataAccessException.class,()->db.execute("TRUNCATE audit_event"));}
    @Test void roleUpdatePersistsVersionAndSupportsIdempotentRetry(){
        UUID target=UUID.randomUUID();db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,'ADMIN','TEST update target','TEST update target')",target);
        var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");
        var headers=new HashMap<>(writeHeaders(grant,"test-role-update-0001"));headers.put("If-Match","\"0\"");
        var result=call("PATCH","/admin/access/roles/"+target,roleBody("TEST updated"),a.token(),headers);
        assertEquals(200,result.status());assertEquals(1,result.data().get("version").asInt());
        assertEquals(result.data(),call("PATCH","/admin/access/roles/"+target,roleBody("TEST updated"),a.token(),headers).data());
        assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='access.role.write'",Integer.class));
    }
    @Test void editingOwnRoleImmediatelyRemovesRevokedAuthority(){
        var a=staff("admin","test-admin");String grant=proof(a,"access.role.write");var headers=new HashMap<>(writeHeaders(grant,"test-own-role-update-0001"));headers.put("If-Match","\"0\"");
        assertEquals(200,call("PATCH","/admin/access/roles/"+adminRole,roleBody("TEST read only now"),a.token(),headers).status());
        assertEquals(403,call("PATCH","/admin/access/roles/"+adminRole,roleBody("TEST read only now"),a.token(),headers).status());
        assertEquals(403,call("GET","/admin/audit",null,a.token()).status());
        assertEquals(200,call("GET","/admin/access/roles",null,a.token()).status());
    }
    @Test void merchantMfaRefreshReverifyAndLogoutUseMerchantBoundary(){
        db.update("UPDATE identity_principal SET mfa_secret_ciphertext=? WHERE id=?",crypto.encrypt(MFA),staffA);
        assertEquals(401,call("POST","/merchant/auth/login",Map.of("login_name","test-merchant-a","password",PASSWORD,"device_id","TEST"),null).status());
        var login=call("POST","/merchant/auth/login",Map.of("login_name","test-merchant-a","password",PASSWORD,"device_id","TEST","totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),null);assertEquals(200,login.status());
        var rotated=call("POST","/merchant/auth/refresh",Map.of("refresh_token",login.data().get("refresh_token").asString()),null);assertEquals(200,rotated.status());
        clock.advance(60);
        var p=call("POST","/merchant/auth/reverify",Map.of("action","session.revoke-others","password",PASSWORD,"totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),rotated.token());assertEquals(200,p.status());
        assertEquals(200,call("POST","/merchant/auth/sessions/revoke-others",null,rotated.token(),Map.of("X-Reverify-Token",p.data().get("reverify_token").asString())).status());
        assertEquals(200,call("GET","/merchant/auth/sessions",null,rotated.token()).status());
        assertEquals(200,call("POST","/merchant/auth/logout",null,rotated.token()).status());
        assertEquals(401,call("GET","/merchant/me",null,rotated.token()).status());
    }
    @Test void localFixturesAreExplicitIdempotentAndCanActuallyLogin(){
        var tx=new org.springframework.transaction.support.TransactionTemplate(new org.springframework.jdbc.datasource.DataSourceTransactionManager(db.getDataSource()));
        var env=new MockEnvironment().withProperty("pawday.demo.enabled","true").withProperty("PAWDAY_DEMO_MERCHANT_PASSWORD",PASSWORD).withProperty("PAWDAY_DEMO_ADMIN_PASSWORD",PASSWORD).withProperty("PAWDAY_DEMO_ADMIN_TOTP_BASE64",Base64.getEncoder().encodeToString(MFA));
        for(String[] profiles:List.of(new String[]{},new String[]{"local","production"},new String[]{"local"})) {
            env.setActiveProfiles(profiles);
            try(var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext()) {
                context.setEnvironment(env);context.registerBean(JdbcTemplate.class,()->db);context.registerBean(org.springframework.transaction.support.TransactionTemplate.class,()->tx);context.registerBean(PasswordEncoder.class,()->passwords);context.registerBean(Crypto.class,()->crypto);context.registerBean(AuditWriter.class,()->audit);context.register(LocalDemoInitializer.class);context.refresh();
                boolean allowed=profiles.length==1;assertEquals(allowed,!context.getBeansOfType(LocalDemoInitializer.class).isEmpty());
                if(allowed){var initializer=context.getBean(LocalDemoInitializer.class);initializer.run(null);long before=db.queryForObject("SELECT count(*) FROM identity_principal",Long.class);initializer.run(null);assertEquals(before,db.queryForObject("SELECT count(*) FROM identity_principal",Long.class));}
            }
        }
        var merchant=staff("merchant","local-staff-a");assertEquals(200,call("GET","/merchant/stores",null,merchant.token()).status());
        var platform=staff("admin","local-admin");assertEquals(200,call("GET","/admin/access/roles",null,platform.token()).status());
    }
    @Test void consumerSessionInventoryAndLogoutWork(){var c=consumer("+8613800000001");assertEquals(200,call("GET","/consumer/auth/sessions",null,c.token()).status());assertEquals(200,call("POST","/consumer/auth/logout",null,c.token()).status());assertEquals(401,call("GET","/consumer/me",null,c.token()).status());}
    @Test void denialAuditFailureStillFailsClosedWithStructuredResponse(){
        var a=staff("merchant","test-merchant-a");
        db.execute("CREATE FUNCTION test_fail_denial() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='security.denied' THEN RAISE EXCEPTION 'TEST audit unavailable'; END IF; RETURN NEW; END $$");
        db.execute("CREATE TRIGGER test_fail_denial BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION test_fail_denial()");
        try {assertEquals(503,call("GET","/admin/me",null,null).status());assertEquals(503,call("GET","/merchant/stores/"+storeB,null,a.token()).status());}
        finally {db.execute("DROP TRIGGER test_fail_denial ON audit_event");db.execute("DROP FUNCTION test_fail_denial()");}
    }
}

