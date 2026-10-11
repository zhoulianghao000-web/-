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

class PilotBoundaryIntegrationTests {
 static EmbeddedPostgres pg;static ConfigurableApplicationContext app;static JdbcTemplate db;static Crypto crypto;static Path root;static int port;
 static final JsonMapper JSON=JsonMapper.builder().build();static final HttpClient HTTP=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new ArrayList<>();
 @BeforeAll static void start() throws Exception {
  pg=EmbeddedPostgres.builder().setPort(0).start();try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){s.execute("CREATE DATABASE pawday_pilot_it");}
  root=Files.createTempDirectory("pawday-pilot-it-");
  app=new SpringApplicationBuilder(PawdayApplication.class).profiles("local","pilot").run(
   "--server.port=0","--spring.datasource.url="+("jdbc:postgresql://127.0.0.1:"+pg.getPort()+"/pawday_pilot_it"),"--spring.datasource.username=postgres","--spring.datasource.password=postgres",
   "--pawday.pilot.root="+root,"--pawday.storage.local-root="+root.resolve("media"),"--pawday.auth.local-sms-directory="+root.resolve("sms"),
   "--pawday.auth.secret-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","--spring.data.redis.host=127.0.0.1","--spring.rabbitmq.host=127.0.0.1","--pawday.search.url=http://127.0.0.1:9206",
   "--pawday.demo.enabled=false","--pawday.search.enabled=false","--pawday.outbox.workers-enabled=false","--pawday.outbox.consumer-enabled=false","--pawday.ai.worker-enabled=false",
   "--management.health.redis.enabled=false","--management.health.rabbit.enabled=false");
  port=((WebServerApplicationContext)app).getWebServer().getPort();db=app.getBean(JdbcTemplate.class);crypto=app.getBean(Crypto.class);
 }
 @AfterAll static void close() throws Exception {if(app!=null)app.close();if(pg!=null)pg.close();Files.createDirectories(Path.of("target/pilot-evidence"));Files.writeString(Path.of("target/pilot-evidence/http-boundaries.json"),JSON.writeValueAsString(SAMPLES));}
 @BeforeEach void reset() throws Exception {Files.deleteIfExists(root.resolve("PAUSED"));}
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}}
 Response request(String method,String path,Object body,String token,boolean client){try{
  var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(10));if(client)b.header("X-Pawday-Pilot",PilotPolicy.CLIENT);if(token!=null)b.header("Authorization","Bearer "+token);
  b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body)));if(body!=null)b.header("Content-Type","application/json");
  var r=HTTP.send(b.build(),HttpResponse.BodyHandlers.ofString());assertEquals("SIMULATED_PILOT",r.headers().firstValue("X-Pawday-Environment").orElseThrow());assertEquals("no-store",r.headers().firstValue("Cache-Control").orElseThrow());
  var value=JSON.readTree(r.body());SAMPLES.add(Map.of("method",method,"path",path,"status",r.statusCode(),"request_id_present",r.headers().firstValue("X-Request-Id").isPresent()));return new Response(r.statusCode(),value);
 }catch(Exception e){throw new AssertionError(e);}}
 String token(String phone){UUID user=UUID.randomUUID(),principal=UUID.randomUUID(),session=UUID.randomUUID();String token=crypto.token();db.update("INSERT INTO app_user(id,status,phone_e164) VALUES (?,'ACTIVE',?) ON CONFLICT(phone_e164) WHERE deleted_at IS NULL AND phone_e164 IS NOT NULL DO NOTHING",user,phone);user=db.queryForObject("SELECT id FROM app_user WHERE phone_e164=? AND deleted_at IS NULL",UUID.class,phone);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?) ON CONFLICT(user_id) DO NOTHING",principal,user);principal=db.queryForObject("SELECT id FROM identity_principal WHERE user_id=?",UUID.class,user);db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'PILOT-IT',?,?,?)",session,principal,crypto.hash(token),Timestamp.from(Instant.now().plusSeconds(900)),Timestamp.from(Instant.now().plusSeconds(3600)),Timestamp.from(Instant.now()));return token;}
 @Test void ordinaryBuildIsRejectedBeforeOtpCreation(){int before=db.queryForObject("SELECT count(*) FROM otp_challenge",Integer.class);assertEquals(409,request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+999000000001","purpose","LOGIN"),null,false).status());assertEquals(before,db.queryForObject("SELECT count(*) FROM otp_challenge",Integer.class));}
 @Test void uninvitedPhoneCannotRequestCodeOrCreateUser(){String phone="+8613800000000";int before=db.queryForObject("SELECT count(*) FROM outbox_event",Integer.class);assertEquals(403,request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","LOGIN"),null,true).status());assertEquals(403,request("POST","/consumer/auth/phone/verify",Map.of("phone_e164",phone,"code","123456","device_id","TEST"),null,true).status());assertEquals(0,db.queryForObject("SELECT count(*) FROM app_user WHERE phone_e164=?",Integer.class,phone));assertEquals(before,db.queryForObject("SELECT count(*) FROM outbox_event",Integer.class));}
 @Test void invitedOtpAndOutboxCommitTogether(){String phone="+999000000002";var r=request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","LOGIN"),null,true);assertEquals(200,r.status());String id=r.data().get("id").asString();assertEquals(1,db.queryForObject("SELECT count(*) FROM outbox_event WHERE aggregate_id=? AND event_type='otp.sms.requested'",Integer.class,id));assertFalse(Files.exists(root.resolve("sms").resolve(id+".txt")));}
 @Test void invitedLoginAndRefreshKeepRealmAndPilotBoundary(){String phone="+999000000003";var code=request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164",phone,"purpose","LOGIN"),null,true);UUID id=UUID.fromString(code.data().get("id").asString());String otp="123456";db.update("UPDATE otp_challenge SET code_hash=? WHERE id=?",crypto.otpHash(id.toString(),otp),id);var login=request("POST","/consumer/auth/phone/verify",Map.of("phone_e164",phone,"code",otp,"device_id","PILOT-IT"),null,true);assertEquals(200,login.status());String token=login.data().get("access_token").asString();assertEquals(200,request("GET","/consumer/me",null,token,true).status());assertEquals(403,request("GET","/admin/me",null,token,true).status());var refresh=request("POST","/consumer/auth/refresh",Map.of("refresh_token",login.data().get("refresh_token").asString()),null,true);assertEquals(200,refresh.status());assertEquals(401,request("GET","/consumer/me",null,token,true).status());}
 @Test void publicCatalogIsPrivateInPilot(){assertEquals(401,request("GET","/public/pet-taxonomy",null,null,true).status());assertEquals(200,request("GET","/public/pet-taxonomy",null,token("+999000000004"),true).status());}
 @Test void historicalUninvitedSessionCannotEnter(){assertEquals(401,request("GET","/public/pet-taxonomy",null,token("+999000000099"),true).status());}
 @Test void staffLoginIsWhitelistedWithoutRelaxingMfa(){assertEquals(403,request("POST","/admin/auth/login",Map.of("login_name","other-admin","password","wrong","totp_code","123456","device_id","TEST"),null,true).status());assertEquals(401,request("POST","/admin/auth/login",Map.of("login_name","local-admin","password","wrong","totp_code","123456","device_id","TEST"),null,true).status());}
 @Test void pauseFileStopsExistingSessionsAndLogin() throws Exception {String token=token("+999000000005");assertEquals(200,request("GET","/consumer/me",null,token,true).status());Files.writeString(root.resolve("PAUSED"),"TEST");assertEquals(503,request("GET","/consumer/me",null,token,true).status());assertEquals(503,request("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+999000000001","purpose","LOGIN"),null,true).status());Files.delete(root.resolve("PAUSED"));assertEquals(200,request("GET","/consumer/me",null,token,true).status());}
 @Test void pilotUsesOnlyLocalDeterministicAi(){assertInstanceOf(PilotExplanationProvider.class,app.getBean(ExplanationProvider.class));assertTrue(app.getBeansOfType(cn.pawday.ai.DeepSeekExplanationProvider.class).isEmpty());}
 @Test void localSmsIsIdempotentAndStaysInPilotRoot() throws Exception {String id=UUID.randomUUID().toString();var gateway=app.getBean(SmsGateway.class);gateway.send(id,"+999000000001","123456");gateway.send(id,"+999000000001","999999");assertEquals("+999000000001\n123456\n",Files.readString(root.resolve("sms").resolve(id+".txt")));}
}
