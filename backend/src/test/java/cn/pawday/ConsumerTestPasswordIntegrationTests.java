package cn.pawday;
import cn.pawday.identity.*;
import cn.pawday.pilot.*;
import cn.pawday.ai.ExplanationProvider;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.sql.*;
import java.time.*;
import java.util.*;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.JsonNode;

class ConsumerTestPasswordIntegrationTests {
 // Keep the real fixed-minute limiter inside one window. BCrypt/HTTP may otherwise cross a wall-clock minute in CI.
 @org.springframework.boot.test.context.TestConfiguration static class StableRateClock {
  @org.springframework.context.annotation.Bean @org.springframework.context.annotation.Primary Clock consumerPasswordTestClock(){return Clock.fixed(Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MINUTES).plusSeconds(10),ZoneOffset.UTC);}
 }
 static EmbeddedPostgres pg;static ConfigurableApplicationContext app;static JdbcTemplate db;static Crypto crypto;static Path root;static int port;
 static final JsonMapper JSON=JsonMapper.builder().build();static final HttpClient HTTP=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new ArrayList<>();
 @BeforeAll static void start() throws Exception {
  pg=EmbeddedPostgres.builder().setPort(0).start();try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){s.execute("CREATE DATABASE pawday_pilot_password_it");}
  root=Files.createTempDirectory("pawday-pilot-it-");
  app=new SpringApplicationBuilder(PawdayApplication.class,StableRateClock.class).profiles("local","pilot").run(
   "--server.port=0","--spring.datasource.url="+("jdbc:postgresql://127.0.0.1:"+pg.getPort()+"/pawday_pilot_password_it"),"--spring.datasource.username=postgres","--spring.datasource.password=postgres",
   "--pawday.pilot.root="+root,"--pawday.storage.local-root="+root.resolve("media"),"--pawday.auth.local-sms-directory="+root.resolve("sms"),
   "--pawday.auth.secret-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","--spring.data.redis.host=127.0.0.1","--spring.rabbitmq.host=127.0.0.1","--pawday.search.url=http://127.0.0.1:9206",
   "--pawday.auth.consumer-test-enabled=true","--pawday.auth.consumer-test-login=TEST_CONSUMER","--pawday.auth.consumer-test-password=TEST_ONLY_consumer_password",
   "--pawday.demo.enabled=true","--PAWDAY_DEMO_MERCHANT_PASSWORD=TEST_ONLY_pilot_merchant","--PAWDAY_DEMO_ADMIN_PASSWORD=TEST_ONLY_pilot_admin","--pawday.search.enabled=false","--pawday.outbox.workers-enabled=false","--pawday.outbox.consumer-enabled=false","--pawday.ai.worker-enabled=false",
   "--management.health.redis.enabled=false","--management.health.rabbit.enabled=false");
  port=((WebServerApplicationContext)app).getWebServer().getPort();db=app.getBean(JdbcTemplate.class);crypto=app.getBean(Crypto.class);
 }
 @AfterAll static void close() throws Exception {if(app!=null)app.close();if(pg!=null)pg.close();Files.createDirectories(Path.of("target/pilot-evidence"));Files.writeString(Path.of("target/pilot-evidence/consumer-password-http.json"),JSON.writeValueAsString(SAMPLES));}
 @BeforeEach void reset() throws Exception {Files.deleteIfExists(root.resolve("PAUSED"));}
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}}
 Response request(String method,String path,Object body,String token,boolean client){try{
  var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(10));if(client)b.header("X-Pawday-Pilot",PilotPolicy.CLIENT);if(token!=null)b.header("Authorization","Bearer "+token);
  b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body)));if(body!=null)b.header("Content-Type","application/json");
  var r=HTTP.send(b.build(),HttpResponse.BodyHandlers.ofString());assertEquals("SIMULATED_PILOT",r.headers().firstValue("X-Pawday-Environment").orElseThrow());assertEquals("no-store",r.headers().firstValue("Cache-Control").orElseThrow());
  var value=JSON.readTree(r.body());SAMPLES.add(Map.of("method",method.toLowerCase(Locale.ROOT),"path",path,"status",r.statusCode(),"response",JSON.readValue(r.body(),Map.class)));return new Response(r.statusCode(),value);
 }catch(Exception e){throw new AssertionError(e);}}
 String token(String phone){UUID user=UUID.randomUUID(),principal=UUID.randomUUID(),session=UUID.randomUUID();String token=crypto.token();db.update("INSERT INTO app_user(id,status,phone_e164) VALUES (?,'ACTIVE',?) ON CONFLICT(phone_e164) WHERE deleted_at IS NULL AND phone_e164 IS NOT NULL DO NOTHING",user,phone);user=db.queryForObject("SELECT id FROM app_user WHERE phone_e164=? AND deleted_at IS NULL",UUID.class,phone);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?) ON CONFLICT(user_id) DO NOTHING",principal,user);principal=db.queryForObject("SELECT id FROM identity_principal WHERE user_id=?",UUID.class,user);db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'PILOT-IT',?,?,?)",session,principal,crypto.hash(token),Timestamp.from(Instant.now().plusSeconds(900)),Timestamp.from(Instant.now().plusSeconds(3600)),Timestamp.from(Instant.now()));return token;}


 @BeforeEach void clearCounters(){db.update("DELETE FROM auth_rate_bucket");}
 Response login(String name,String password){return request("POST","/consumer/auth/password-login",Map.of("login_name",name,"password",password,"device_id","PASSWORD-IT"),null,true);}
 @Test void passwordLoginPreservesFirstSyntheticUserWithoutOtpOrAccountCreation(){
  long users=db.queryForObject("SELECT count(*) FROM app_user",Long.class),otps=db.queryForObject("SELECT count(*) FROM otp_challenge",Long.class);
  var r=login("TEST_CONSUMER","TEST_ONLY_consumer_password");assertEquals(200,r.status());String token=r.data().get("access_token").asString();
  var me=request("GET","/consumer/me",null,token,true);assertEquals(200,me.status());assertEquals("CONSUMER",me.data().get("realm").asString());
  assertEquals(db.queryForObject("SELECT id::text FROM app_user WHERE phone_e164='+999000000001'",String.class),me.data().get("user_id").asString());
  assertEquals(403,request("GET","/admin/me",null,token,true).status());assertEquals(403,request("GET","/merchant/me",null,token,true).status());
  assertEquals(200,request("POST","/consumer/auth/refresh",Map.of("refresh_token",r.data().get("refresh_token").asString()),null,true).status());
  assertEquals(users,db.queryForObject("SELECT count(*) FROM app_user",Long.class));assertEquals(otps,db.queryForObject("SELECT count(*) FROM otp_challenge",Long.class));
 }
 @Test void incorrectAccountOrPasswordNeverAuthenticates(){assertEquals(401,login("OTHER_TEST_ACCOUNT","TEST_ONLY_consumer_password").status());assertEquals(401,login("TEST_CONSUMER","INCORRECT_PASSWORD").status());assertEquals(401,login("TEST_CONSUMER","x".repeat(73)).status());}
 @Test void onlyOneConsumerAndNoOtpLoginInSingleAccountMode(){assertEquals(401,request("GET","/consumer/me",null,token("+999000000002"),true).status());assertEquals(403,request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+999000000001","purpose","LOGIN"),null,true).status());assertEquals(403,request("POST","/consumer/auth/phone/verify",Map.of("phone_e164","+999000000001","code","123456","device_id","OLD-OTP"),null,true).status());}
 @Test void pauseAndBruteForceLimitRemainEffective() throws Exception {Files.writeString(root.resolve("PAUSED"),"test");assertEquals(503,login("TEST_CONSUMER","TEST_ONLY_consumer_password").status());Files.delete(root.resolve("PAUSED"));for(int n=0;n<10;n++)assertEquals(401,login("TEST_CONSUMER","INCORRECT_PASSWORD").status());assertEquals(429,login("TEST_CONSUMER","INCORRECT_PASSWORD").status());}
 @Test void inactiveSyntheticUserCannotLogin(){db.update("UPDATE app_user SET status='SUSPENDED' WHERE phone_e164='+999000000001'");try{assertEquals(401,login("TEST_CONSUMER","TEST_ONLY_consumer_password").status());}finally{db.update("UPDATE app_user SET status='ACTIVE' WHERE phone_e164='+999000000001'");}}
}
