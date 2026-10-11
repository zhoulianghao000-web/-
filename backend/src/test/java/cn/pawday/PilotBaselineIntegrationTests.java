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

class PilotBaselineIntegrationTests {
 static EmbeddedPostgres pg;static ConfigurableApplicationContext app;static JdbcTemplate db;static Crypto crypto;static Path root;static int port;
 static final JsonMapper JSON=JsonMapper.builder().build();static final HttpClient HTTP=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new ArrayList<>();
 @BeforeAll static void start() throws Exception {
  pg=EmbeddedPostgres.builder().setPort(0).start();try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){s.execute("CREATE DATABASE pawday_pilot_baseline_it");}
  root=Files.createTempDirectory("pawday-pilot-it-");
  app=new SpringApplicationBuilder(PawdayApplication.class).profiles("local","pilot").run(
   "--server.port=0","--spring.datasource.url="+("jdbc:postgresql://127.0.0.1:"+pg.getPort()+"/pawday_pilot_baseline_it"),"--spring.datasource.username=postgres","--spring.datasource.password=postgres",
   "--pawday.pilot.root="+root,"--pawday.storage.local-root="+root.resolve("media"),"--pawday.auth.local-sms-directory="+root.resolve("sms"),
   "--pawday.auth.secret-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","--spring.data.redis.host=127.0.0.1","--spring.rabbitmq.host=127.0.0.1","--pawday.search.url=http://127.0.0.1:9206",
   "--pawday.demo.enabled=true","--PAWDAY_DEMO_MERCHANT_PASSWORD=TEST_ONLY_pilot_merchant","--PAWDAY_DEMO_ADMIN_PASSWORD=TEST_ONLY_pilot_admin","--PAWDAY_DEMO_ADMIN_TOTP_BASE64=MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=","--pawday.search.enabled=false","--pawday.outbox.workers-enabled=false","--pawday.outbox.consumer-enabled=false","--pawday.ai.worker-enabled=false",
   "--management.health.redis.enabled=false","--management.health.rabbit.enabled=false");
  port=((WebServerApplicationContext)app).getWebServer().getPort();db=app.getBean(JdbcTemplate.class);crypto=app.getBean(Crypto.class);
 }
 @AfterAll static void close() throws Exception {if(app!=null)app.close();if(pg!=null)pg.close();Files.createDirectories(Path.of("target/pilot-evidence"));Files.writeString(Path.of("target/pilot-evidence/baseline-http.json"),JSON.writeValueAsString(SAMPLES));}
 @BeforeEach void reset() throws Exception {Files.deleteIfExists(root.resolve("PAUSED"));}
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}}
 Response request(String method,String path,Object body,String token,boolean client){try{
  var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(10));if(client)b.header("X-Pawday-Pilot",PilotPolicy.CLIENT);if(token!=null)b.header("Authorization","Bearer "+token);
  b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body)));if(body!=null)b.header("Content-Type","application/json");
  var r=HTTP.send(b.build(),HttpResponse.BodyHandlers.ofString());assertEquals("SIMULATED_PILOT",r.headers().firstValue("X-Pawday-Environment").orElseThrow());assertEquals("no-store",r.headers().firstValue("Cache-Control").orElseThrow());
  var value=JSON.readTree(r.body());SAMPLES.add(Map.of("method",method.toLowerCase(Locale.ROOT),"path",path,"status",r.statusCode(),"response",JSON.readValue(r.body(),Map.class)));return new Response(r.statusCode(),value);
 }catch(Exception e){throw new AssertionError(e);}}
 String token(String phone){UUID user=UUID.randomUUID(),principal=UUID.randomUUID(),session=UUID.randomUUID();String token=crypto.token();db.update("INSERT INTO app_user(id,status,phone_e164) VALUES (?,'ACTIVE',?) ON CONFLICT(phone_e164) WHERE deleted_at IS NULL AND phone_e164 IS NOT NULL DO NOTHING",user,phone);user=db.queryForObject("SELECT id FROM app_user WHERE phone_e164=? AND deleted_at IS NULL",UUID.class,phone);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?) ON CONFLICT(user_id) DO NOTHING",principal,user);principal=db.queryForObject("SELECT id FROM identity_principal WHERE user_id=?",UUID.class,user);db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'PILOT-IT',?,?,?)",session,principal,crypto.hash(token),Timestamp.from(Instant.now().plusSeconds(900)),Timestamp.from(Instant.now().plusSeconds(3600)),Timestamp.from(Instant.now()));return token;}

 @Test void exactRoundCountsAndAtomicEventFacts(){assertEquals(20,db.queryForObject("SELECT count(*) FROM skus",Integer.class));assertEquals(20,db.queryForObject("SELECT count(*) FROM app_user",Integer.class));assertEquals(2,db.queryForObject("SELECT count(*) FROM merchant_store",Integer.class));assertEquals(20,db.queryForObject("SELECT count(*) FROM inventory_adjustments",Integer.class));assertEquals(20,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='CatalogStandardPublished'",Integer.class));assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='pilot.baseline.initialized'",Integer.class));}
 @Test void baselineSummaryIsPrivateAndContainsNoIdentityList(){assertEquals(401,request("GET","/consumer/pilot/baseline",null,null,true).status());var r=request("GET","/consumer/pilot/baseline",null,token("+999000000001"),true);assertEquals(200,r.status());assertEquals(20,r.data().get("sku_count").asInt());assertFalse(r.data().toString().contains("+999"));}
 @Test void restartNeverReplenishesConsumedStock() throws Exception {UUID offer=PilotMaterials.id("offer-1");long before=db.queryForObject("SELECT on_hand_qty FROM inventory_balances WHERE offer_id=?",Long.class,offer);db.update("UPDATE inventory_balances SET on_hand_qty=on_hand_qty-1 WHERE offer_id=?",offer);app.getBean(PilotBaselineInitializer.class).run(null);assertEquals(before-1,db.queryForObject("SELECT on_hand_qty FROM inventory_balances WHERE offer_id=?",Long.class,offer));db.update("UPDATE inventory_balances SET on_hand_qty=? WHERE offer_id=?",before,offer);}
 @Test void syntheticNoAllergyAndAllergyCasesAreDeterministic(){var ok=request("GET","/consumer/skus/"+PilotMaterials.id("sku-1")+"/fit?pet_id="+PilotMaterials.id("pet-1"),null,token("+999000000001"),true);assertEquals(200,ok.status());assertEquals("SUITABLE",ok.data().get("result").asString());var no=request("GET","/consumer/skus/"+PilotMaterials.id("sku-1")+"/fit?pet_id="+PilotMaterials.id("pet-11"),null,token("+999000000011"),true);assertEquals("NOT_RECOMMENDED",no.data().get("result").asString());}
 @Test void unverifiedWithCategoryConflictStillCannotClaimAnEvidenceConclusion(){var r=request("GET","/consumer/skus/"+PilotMaterials.id("sku-18")+"/fit?pet_id="+PilotMaterials.id("pet-11"),null,token("+999000000011"),true);assertEquals(200,r.status());assertEquals("INSUFFICIENT_DATA",r.data().get("result").asString());assertEquals(0,r.data().get("hard_conflicts").size());assertTrue(r.data().get("uncertainties").toString().contains("PILOT_MATERIAL_UNVERIFIED"));}
 @Test void copiedSourceLabelCannotUpgradeAnotherSnapshot(){var m=app.getBean(PilotMaterials.class).describe(PilotMaterials.id("sku-1"),UUID.randomUUID(),List.of("pawday-pilot:cq-v1:SYNTHETIC:1"));assertEquals("UNVERIFIED",m.get("kind"));assertEquals(false,m.get("generated_fixture"));assertNull(m.get("media_path"));}
 @Test void unknownStandardKeepsEmptyIngredientsAndUnknownAllergens(){var r=request("GET","/public/skus/"+PilotMaterials.id("sku-17"),null,token("+999000000001"),true);assertEquals(200,r.status());assertEquals(0,r.data().get("ingredients").size());assertFalse(r.data().get("allergens_known").asBoolean());assertEquals("UNVERIFIED",r.data().get("pilot_material").get("kind").asString());}
 @Test void petOwnershipIsNotRelaxed(){assertEquals(404,request("GET","/consumer/skus/"+PilotMaterials.id("sku-1")+"/fit?pet_id="+PilotMaterials.id("pet-2"),null,token("+999000000001"),true).status());}
 @Test void invitedMediaIsBinaryAndAnonymousCannotReadIt() throws Exception {String path="/api/v1/consumer/pilot/skus/"+PilotMaterials.id("sku-1")+"/media";var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+path)).header("X-Pawday-Pilot",PilotPolicy.CLIENT);var guest=HTTP.send(b.GET().build(),HttpResponse.BodyHandlers.ofByteArray());assertEquals(401,guest.statusCode());var result=HTTP.send(b.header("Authorization","Bearer "+token("+999000000001")).GET().build(),HttpResponse.BodyHandlers.ofByteArray());assertEquals(200,result.statusCode());assertEquals("image/png",result.headers().firstValue("Content-Type").orElseThrow());assertEquals("no-store",result.headers().firstValue("Cache-Control").orElseThrow());assertArrayEquals(new byte[]{(byte)137,80,78,71},Arrays.copyOf(result.body(),4));Files.createDirectories(Path.of("target/pilot-evidence"));Files.writeString(Path.of("target/pilot-evidence/baseline-binary.json"),JSON.writeValueAsString(List.of(Map.of("path",path.substring("/api/v1".length()),"status",200,"content_type","image/png","bytes",result.body().length))));}

 @Test void publishedMediaReferencesCannotBeDeleted(){UUID asset=PilotMaterials.media(1);var actor=new Actor(PilotMaterials.demo("staff-a"),Actor.Realm.MERCHANT,null,PilotMaterials.demo("merchant-a"),PilotMaterials.id("media-session-a"),Set.of("store.read"),Set.of());var auth=new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(actor,null,List.of());org.springframework.security.core.context.SecurityContextHolder.getContext().setAuthentication(auth);try{var e=assertThrows(cn.pawday.common.Api.Failure.class,()->app.getBean(cn.pawday.storage.MediaService.class).delete(asset,null));assertEquals("MEDIA_IN_USE",e.code);}finally{org.springframework.security.core.context.SecurityContextHolder.clearContext();}}
 @Test void newOrNonPilotSnapshotCannotGainSyntheticApproval(){var env=new org.springframework.core.env.StandardEnvironment();var ordinary=new PilotMaterials(new PilotPolicy(env));assertNull(ordinary.describe(PilotMaterials.id("sku-1"),PilotMaterials.id("standard-1"),List.of("https://example.test/source")));assertThrows(cn.pawday.common.Api.Failure.class,()->ordinary.describe(PilotMaterials.id("sku-1"),PilotMaterials.id("standard-1"),List.of("pawday-pilot:cq-v1:SYNTHETIC:1")));assertThrows(cn.pawday.common.Api.Failure.class,()->ordinary.validateSources(List.of("pawday-pilot:cq-v1:SYNTHETIC:1")));}
 @Test void initialPilotAdmissionWaitsForBaseline(){var env=new org.springframework.mock.env.MockEnvironment().withProperty("pawday.pilot.enabled","true").withProperty("pawday.demo.enabled","true");assertFalse(new PilotPolicy(env).ready());assertTrue(app.getBean(PilotPolicy.class).ready());}
 @Test void retiredStandardCannotExposeItsImage(){UUID standard=PilotMaterials.id("standard-20");db.update("UPDATE sku_standard_versions SET status='RETIRED' WHERE id=?",standard);assertEquals(404,request("GET","/consumer/pilot/skus/"+PilotMaterials.id("sku-20")+"/media",null,token("+999000000001"),true).status());}
}
