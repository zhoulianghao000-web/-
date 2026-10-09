package cn.pawday;

import cn.pawday.identity.*;
import cn.pawday.operations.DataKeyAvailabilityCheck;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;
import tools.jackson.databind.json.JsonMapper;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
class OperationsIntegrationTests {
    static final String TOKEN="TEST_ONLY_M62_"+"X".repeat(40);
    static final EmbeddedPostgres PG;
    static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->DataEncryptionKeyRingTests.key(0));r.add("pawday.operations.scrape-token",()->TOKEN);r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);r.add("pawday.membership.worker-enabled",()->false);r.add("pawday.ai.worker-enabled",()->false);}
    @Autowired JdbcTemplate db;@Autowired Crypto crypto;@LocalServerPort int port;
    final HttpClient http=HttpClient.newHttpClient();
    HttpResponse<String> get(String path,String token)throws Exception{var b=HttpRequest.newBuilder(URI.create("http://localhost:"+port+path)).GET();if(token!=null)b.header("Authorization","Bearer "+token);return http.send(b.build(),HttpResponse.BodyHandlers.ofString());}
    @Test void realPrometheusScrapeRequiresCredential()throws Exception{assertEquals(401,get("/actuator/prometheus",null).statusCode());assertEquals(401,get("/actuator/prometheus","wrong").statusCode());var r=get("/actuator/prometheus",TOKEN);assertEquals(200,r.statusCode());assertTrue(r.body().contains("pawday_operations_db_available 1.0"));assertTrue(r.body().contains("pawday_payment_unknown"));assertFalse(r.body().contains(TOKEN));}
    @Test void scraperCannotReadAdminConsumerOrGenericMetrics()throws Exception{for(String path:List.of("/api/v1/admin/outbox","/api/v1/consumer/pets","/actuator/metrics"))assertEquals(401,get(path,TOKEN).statusCode());}
    @Test void metricsReflectDatabaseFactsAndRecovery()throws Exception{UUID m=UUID.randomUUID(),s=UUID.randomUUID();db.update("INSERT INTO merchant VALUES (?,'TEST_ONLY_M62','ACTIVE')",m);db.update("INSERT INTO settlements(id,settlement_no,merchant_id,status,amount_fen,entry_count) VALUES (?,?,?,'FAILED_RETRYABLE',50,1)",s,s.toString(),m);assertTrue(get("/actuator/prometheus",TOKEN).body().contains("pawday_settlement_retryable 1.0"));db.update("UPDATE settlements SET status='PROCESSING' WHERE id=?",s);assertTrue(get("/actuator/prometheus",TOKEN).body().contains("pawday_settlement_retryable 0.0"));}
    @Test void removalOfReferencedDataKeyIsRejectedWithoutMutatingFacts(){UUID id=UUID.randomUUID();String cipher=DataEncryptionKeyRingTests.key(1);String encoded=new DataEncryptionKeyRing("old","old:"+cipher).encrypt(new byte[20],new byte[32]);db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,'ADMIN',?,'TEST_ONLY',?)",id,id.toString(),encoded);try{var e=assertThrows(IllegalStateException.class,()->new DataKeyAvailabilityCheck(db,new DataEncryptionKeyRing("legacy","")).afterPropertiesSet());assertEquals("DATA_KEY_STILL_REQUIRED",e.getMessage());assertEquals(encoded,db.queryForObject("SELECT mfa_secret_ciphertext FROM identity_principal WHERE id=?",String.class,id));assertDoesNotThrow(()->new DataKeyAvailabilityCheck(db,new DataEncryptionKeyRing("old","old:"+cipher)).afterPropertiesSet());}finally{db.update("DELETE FROM identity_principal WHERE id=?",id);}}
    @Test void restoredVersionedTotpRemainsUsableAfterChangingActiveKey()throws Exception{byte[] secret=new byte[20];var old=new Crypto(DataEncryptionKeyRingTests.key(0),java.time.Clock.systemUTC(),new DataEncryptionKeyRing("old","old:"+DataEncryptionKeyRingTests.key(1)));var next=new Crypto(DataEncryptionKeyRingTests.key(0),java.time.Clock.systemUTC(),new DataEncryptionKeyRing("new","old:"+DataEncryptionKeyRingTests.key(1)+",new:"+DataEncryptionKeyRingTests.key(2)));String cipher=old.encrypt(secret);long step=java.time.Instant.now().getEpochSecond()/30;assertEquals(step,next.matchTotp(cipher,next.totp(secret,step)));Path fixture=Path.of("target/m62-test-ciphertexts.json");Files.createDirectories(fixture.getParent());Files.writeString(fixture,JsonMapper.builder().build().writeValueAsString(Map.of("test_only",true,"legacy",crypto.encrypt(secret),"old",cipher,"current",next.encrypt(secret),"key_references",List.of("secrets://pawday/test-only/auth","secrets://pawday/test-only/data-old","secrets://pawday/test-only/data-new"))));}
}
