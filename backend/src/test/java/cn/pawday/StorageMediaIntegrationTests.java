package cn.pawday;

import cn.pawday.audit.AuditWriter;
import cn.pawday.identity.*;
import cn.pawday.storage.*;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.awt.image.BufferedImage;
import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Real HTTP + PostgreSQL + filesystem. No in-memory or mocked object provider. */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(StorageMediaIntegrationTests.Fixtures.class)
class StorageMediaIntegrationTests {
    static final EmbeddedPostgres PG;static final Path ROOT;
    static {try{PG=EmbeddedPostgres.builder().setPort(0).start();ROOT=Files.createTempDirectory("pawday-media-it-");}catch(Exception ex){throw new ExceptionInInitializerError(ex);}}
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");
        r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
        r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);
        r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);
        r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.storage.local-root",ROOT::toString);
    }
    static class MutableClock extends Clock {
        volatile Instant value=Instant.parse("2026-10-03T00:00:00Z");void advance(long seconds){value=value.plusSeconds(seconds);}
        public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId zone){return this;}public Instant instant(){return value;}
    }
    static class CheckedLocal extends LocalObjectStorageProvider {
        volatile Runnable afterPut;
        CheckedLocal(){super(ROOT);}
        @Override public Metadata put(Put p,InputStream content){assertFalse(TransactionSynchronizationManager.isActualTransactionActive(),"upload provider IO must follow DB commit");var metadata=super.put(p,content);if(afterPut!=null)afterPut.run();return metadata;}
        @Override public Optional<Metadata> metadata(String key){assertFalse(TransactionSynchronizationManager.isActualTransactionActive(),"recovery provider IO must run outside DB transaction");return super.metadata(key);}
        @Override public InputStream read(String key){assertFalse(TransactionSynchronizationManager.isActualTransactionActive());return super.read(key);}
        @Override public void delete(String key){assertFalse(TransactionSynchronizationManager.isActualTransactionActive(),"delete provider IO must run outside DB transaction");super.delete(key);}
    }
    @TestConfiguration static class Fixtures {
        @Bean @Primary MutableClock mediaClock(){return new MutableClock();}
        @Bean @Primary ObjectStorageProvider actualLocalFiles(){return new CheckedLocal();}
    }
    @Autowired JdbcTemplate db;@Autowired Crypto crypto;@Autowired MutableClock clock;@Autowired MediaService service;@Autowired ObjectStorageProvider provider;@Autowired AuditWriter audit;
    @LocalServerPort int port;
    final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    static final List<Map<String,Object>> SAMPLES=new CopyOnWriteArrayList<>();
    byte[] png;String tokenA,tokenB;UUID principalA,principalB,sessionA;
    record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}String code(){return body.get("error").get("code").asString();}}
    String hash(byte[] b){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}catch(Exception ex){throw new AssertionError(ex);}}
    String session(UUID principal){UUID id=UUID.randomUUID();String token=crypto.token();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'MEDIA-TEST',?,?,?)",id,principal,crypto.hash(token),Timestamp.from(clock.instant().plusSeconds(900)),Timestamp.from(clock.instant().plusSeconds(2592000)),Timestamp.from(clock.instant()));return token;}
    UUID consumer(){UUID principal=UUID.randomUUID(),user=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",user);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",principal,user);return principal;}
    @BeforeEach void setup() throws Exception {
        clock.value=Instant.parse("2026-10-03T00:00:00Z");db.execute("TRUNCATE media_asset_usage,media_asset");
        try(var files=Files.walk(ROOT)){for(var path:files.sorted(Comparator.reverseOrder()).toList())if(!path.equals(ROOT))Files.delete(path);}
        Files.createDirectories(ROOT.resolve("media"));Files.createDirectories(ROOT.resolve(".incoming"));
        var image=new BufferedImage(2,2,BufferedImage.TYPE_INT_RGB);image.setRGB(0,0,0xff33cc);try(var out=new ByteArrayOutputStream()){assertTrue(ImageIO.write(image,"png",out));png=out.toByteArray();}
        principalA=consumer();principalB=consumer();tokenA=session(principalA);tokenB=session(principalB);sessionA=db.queryForObject("SELECT id FROM auth_session WHERE access_token_hash=?",UUID.class,crypto.hash(tokenA));
    }
    Response request(String method,String path,Object payload,String token,Map<String,String> headers) {
        try {var builder=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));if(token!=null)builder.header("Authorization","Bearer "+token);headers.forEach(builder::header);
            if(payload instanceof byte[] bytes)builder.method(method,HttpRequest.BodyPublishers.ofByteArray(bytes));
            else if(payload==null)builder.method(method,HttpRequest.BodyPublishers.noBody());
            else builder.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));
            var response=http.send(builder.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());
            var safe=json.readTree(response.body());if(safe.has("data")&&safe.get("data").has("upload_token"))((tools.jackson.databind.node.ObjectNode)safe.get("data")).put("upload_token","A".repeat(43));
            SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",safe));return new Response(response.statusCode(),body);
        }catch(Exception ex){throw new AssertionError(path,ex);}
    }
    Response request(String method,String path,Object payload,String token){return request(method,path,payload,token,Map.of());}
    Response grant(byte[] content,String mime,String scope,String token){return request("POST","/media/upload-grants",Map.of("scope",scope,"mime",mime,"size_bytes",content.length,"sha256",hash(content)),token);}
    Response upload(Response grant,byte[] content,String mime,String token){return request("PUT","/media/"+grant.data().get("asset_id").asString()+"/content",content,token,Map.of("X-Upload-Token",grant.data().get("upload_token").asString(),"Content-Type",mime));}
    Path object(Response grant){return ROOT.resolve("media/"+grant.data().get("asset_id").asString()+".png");}
    @AfterAll static void close() throws Exception {Files.createDirectories(Path.of("target"));Files.writeString(Path.of("target/m23-storage-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();try(var paths=Files.walk(ROOT)){for(var p:paths.sorted(Comparator.reverseOrder()).toList())Files.delete(p);}}

    @Test void realUploadMetadataReadDeleteAndDatabaseContainsOnlyReferences() throws Exception {
        var grant=grant(png,"image/png","AVATAR",tokenA);assertEquals(201,grant.status());assertFalse(db.queryForObject("SELECT upload_token_hash FROM media_asset",String.class).equals(grant.data().get("upload_token").asString()));
        var uploaded=upload(grant,png,"image/png",tokenA);assertEquals(200,uploaded.status());assertEquals("READY",uploaded.data().get("status").asString());assertArrayEquals(png,Files.readAllBytes(object(grant)));
        String id=grant.data().get("asset_id").asString();assertEquals(200,request("GET","/media/"+id,null,tokenA).status());
        var bytes=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1/media/"+id+"/content")).header("Authorization","Bearer "+tokenA).GET().build(),HttpResponse.BodyHandlers.ofByteArray());assertEquals(200,bytes.statusCode());assertArrayEquals(png,bytes.body());assertEquals("nosniff",bytes.headers().firstValue("X-Content-Type-Options").orElseThrow());assertTrue(bytes.headers().firstValue("Cache-Control").orElseThrow().contains("no-store"));
        assertEquals(0,db.queryForObject("SELECT count(*) FROM information_schema.columns WHERE table_name='media_asset' AND data_type IN ('bytea','oid')",Integer.class));
        var deleted=request("DELETE","/media/"+id,null,tokenA);assertEquals(202,deleted.status());assertEquals("DELETED",deleted.data().get("status").asString());assertEquals(1,db.queryForObject("SELECT count(*) FROM privacy_journal WHERE kind='MEDIA_DELETE' AND subject_id=?",Integer.class,UUID.fromString(id)));assertFalse(Files.exists(object(grant)));assertEquals(202,request("DELETE","/media/"+id,null,tokenA).status());assertEquals(409,request("GET","/media/"+id+"/content",null,tokenA).status());
    }
    @Test void clientCannotChooseProviderBucketOrKey(){for(String field:List.of("bucket","object_key","storage_provider")){var body=new HashMap<String,Object>(Map.of("scope","AVATAR","mime","image/png","size_bytes",png.length,"sha256",hash(png)));body.put(field,"attacker");assertEquals(400,request("POST","/media/upload-grants",body,tokenA).status());}assertEquals(0,db.queryForObject("SELECT count(*) FROM media_asset",Integer.class));}
    @Test void illegalMimeAndDeclaredOversizeAreRejected(){assertEquals(400,grant(png,"image/svg+xml","AVATAR",tokenA).status());assertEquals(413,request("POST","/media/upload-grants",Map.of("scope","AVATAR","mime","image/png","size_bytes",5242881,"sha256",hash(png)),tokenA).status());assertEquals(0,db.queryForObject("SELECT count(*) FROM media_asset",Integer.class));}
    @Test void expirationIsEnforcedAndExpiredCredentialCannotCreateAFile(){var g=grant(png,"image/png","AVATAR",tokenA);clock.advance(301);var rejected=upload(g,png,"image/png",tokenA);assertEquals(403,rejected.status());assertEquals("UPLOAD_GRANT_EXPIRED",rejected.code());service.recover();assertEquals("EXPIRED",db.queryForObject("SELECT status FROM media_asset",String.class));assertFalse(Files.exists(object(g)));}
    @Test void ownershipSessionAndUploadTokenAreIndependentBoundaries(){var g=grant(png,"image/png","AVATAR",tokenA);String path="/media/"+g.data().get("asset_id").asString();for(String method:List.of("GET","DELETE"))assertEquals(404,request(method,path,null,tokenB).status());assertEquals(404,upload(g,png,"image/png",tokenB).status());assertEquals(403,upload(g,png,"image/png",session(principalA)).status());assertEquals(403,request("PUT",path+"/content",png,tokenA,Map.of("Content-Type","image/png","X-Upload-Token","wrong")).status());assertEquals(200,upload(g,png,"image/png",tokenA).status());}
    @Test void anonymousAndInvalidUUIDCannotReadAnAsset(){assertEquals(401,request("GET","/media/"+UUID.randomUUID(),null,null).status());assertEquals(404,request("GET","/media/not-an-id",null,tokenA).status());assertEquals(404,request("GET","/media/"+UUID.randomUUID(),null,tokenA).status());}
    @Test void simultaneousSingleUseUploadsHaveExactlyOneWinner() throws Exception {var g=grant(png,"image/png","AVATAR",tokenA);try(var pool=Executors.newFixedThreadPool(2)){var a=pool.submit(()->upload(g,png,"image/png",tokenA).status());var b=pool.submit(()->upload(g,png,"image/png",tokenA).status());assertEquals(Set.of(200,409),Set.of(a.get(),b.get()));}assertEquals(409,upload(g,png,"image/png",tokenA).status());assertArrayEquals(png,Files.readAllBytes(object(g)));assertNull(db.queryForObject("SELECT upload_token_hash FROM media_asset",String.class));}
    @Test void headerMimeAndMagicMustMatchAndCredentialIsConsumedOnFailure(){var g=grant(png,"image/png","AVATAR",tokenA);assertEquals(400,upload(g,png,"image/jpeg",tokenA).status());assertEquals(409,upload(g,png,"image/png",tokenA).status());byte[] svg="<svg xmlns='http://www.w3.org/2000/svg'/>".getBytes();var spoof=grant(svg,"image/png","REVIEW",tokenA);assertEquals(400,upload(spoof,svg,"image/png",tokenA).status());assertFalse(Files.exists(object(spoof)));}
    @Test void sizeAndHashAreVerifiedAgainstActualStream(){var g=grant(png,"image/png","AVATAR",tokenA);byte[] enlarged=Arrays.copyOf(png,png.length+1);assertEquals(413,upload(g,enlarged,"image/png",tokenA).status());var h=grant(png,"image/png","AVATAR",tokenA);byte[] changed=png.clone();changed[changed.length-1]^=1;assertEquals("UPLOAD_HASH_MISMATCH",upload(h,changed,"image/png",tokenA).code());assertFalse(Files.exists(object(h)));var shortGrant=grant(png,"image/png","AVATAR",tokenA);assertEquals("UPLOAD_SIZE_MISMATCH",upload(shortGrant,Arrays.copyOf(png,png.length-1),"image/png",tokenA).code());}
    @Test void truncatedImageAndUnsafeDimensionsAreRejected(){byte[] fake=new byte[]{(byte)137,80,78,71,13,10,26,10,0,0,0,0};var g=grant(fake,"image/png","AVATAR",tokenA);assertEquals(400,upload(g,fake,"image/png",tokenA).status());byte[] large=png.clone();java.nio.ByteBuffer.wrap(large,16,4).putInt(100000);var h=grant(large,"image/png","AVATAR",tokenA);assertEquals(400,upload(h,large,"image/png",tokenA).status());}
    @Test void realJPEGAlsoRoundTrips() throws Exception {byte[] jpeg;try(var out=new ByteArrayOutputStream()){assertTrue(ImageIO.write(new BufferedImage(3,3,BufferedImage.TYPE_INT_RGB),"jpeg",out));jpeg=out.toByteArray();}var g=grant(jpeg,"image/jpeg","REVIEW",tokenA);assertEquals(200,upload(g,jpeg,"image/jpeg",tokenA).status());try(var in=provider.read("media/"+g.data().get("asset_id").asString()+".jpg")){assertArrayEquals(jpeg,in.readAllBytes());}}
    @Test void merchantProductRequiresCurrentStoreIntersectionAndCorrectRealm() {
        assertEquals(403,grant(png,"image/png","PRODUCT",tokenA).status());UUID merchant=UUID.randomUUID(),store=UUID.randomUUID(),other=UUID.randomUUID(),staff=UUID.randomUUID();
        db.update("INSERT INTO merchant(id,name,status) VALUES (?,'MEDIA TEST','ACTIVE')",merchant);db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'assigned'),(?,?,'unassigned')",store,merchant,other,merchant);db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash) VALUES (?,'MERCHANT',?,?,'TEST-HASH')",staff,merchant,staff.toString());db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",staff,merchant,store);String merchantToken=session(staff);
        assertEquals(400,grant(png,"image/png","PRODUCT",merchantToken).status());
        var body=new HashMap<String,Object>(Map.of("scope","PRODUCT","mime","image/png","size_bytes",png.length,"sha256",hash(png),"store_id",other.toString()));assertEquals(404,request("POST","/media/upload-grants",body,merchantToken).status());body.put("store_id",store.toString());var g=request("POST","/media/upload-grants",body,merchantToken);assertEquals(201,g.status());db.update("DELETE FROM principal_store_scope WHERE principal_id=?",staff);assertEquals(404,upload(g,png,"image/png",merchantToken).status());
        assertEquals(403,grant(png,"image/png","ARTICLE",merchantToken).status());
    }
    @Test void auditFailureRollsBackGrantAndCommittedFileIsRecoveredAfterFinalizeFailure(){
        db.execute("CREATE FUNCTION media_test_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action IN ('media.upload-grant','media.uploaded') THEN RAISE EXCEPTION 'TEST audit unavailable'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER media_test_audit BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION media_test_fail_audit()");
        try{assertEquals(503,grant(png,"image/png","AVATAR",tokenA).status());assertEquals(0,db.queryForObject("SELECT count(*) FROM media_asset",Integer.class));}finally{db.execute("DROP TRIGGER media_test_audit ON audit_event");}
        var g=grant(png,"image/png","AVATAR",tokenA);db.execute("CREATE TRIGGER media_test_audit BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION media_test_fail_audit()");try{assertEquals(503,upload(g,png,"image/png",tokenA).status());assertEquals("UPLOADING",db.queryForObject("SELECT status FROM media_asset",String.class));assertTrue(Files.exists(object(g)));}finally{db.execute("DROP TRIGGER media_test_audit ON audit_event");db.execute("DROP FUNCTION media_test_fail_audit()");}
        clock.advance(61);service.recover();assertEquals("READY",db.queryForObject("SELECT status FROM media_asset",String.class));assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='media.upload-recovered' AND object_id=?",Integer.class,g.data().get("asset_id").asString()));
    }
    @Test void interruptedUploadRecoversToFailedAndRemovesItsOrphan(){var g=grant(png,"image/png","AVATAR",tokenA);UUID id=UUID.fromString(g.data().get("asset_id").asString());db.update("UPDATE media_asset SET status='UPLOADING',upload_token_hash=NULL,claim_token=?,lease_expires_at=? WHERE id=?",UUID.randomUUID(),Timestamp.from(clock.instant().minusSeconds(1)),id);service.recover();assertEquals("FAILED",db.queryForObject("SELECT status FROM media_asset",String.class));assertEquals(409,upload(g,png,"image/png",tokenA).status());}
    @Test void storageDeletionFailureRemainsDurableAndRecoveryCompletes() throws Exception {var g=grant(png,"image/png","AVATAR",tokenA);assertEquals(200,upload(g,png,"image/png",tokenA).status());Path saved=ROOT.resolve("media-saved");Files.move(ROOT.resolve("media"),saved);Files.writeString(ROOT.resolve("media"),"TEST temporarily unavailable directory");try{var r=request("DELETE","/media/"+g.data().get("asset_id").asString(),null,tokenA);assertEquals(202,r.status());assertEquals("DELETE_PENDING",r.data().get("status").asString());}finally{Files.delete(ROOT.resolve("media"));Files.move(saved,ROOT.resolve("media"));}clock.advance(31);service.recover();assertEquals("DELETED",db.queryForObject("SELECT status FROM media_asset",String.class));assertFalse(Files.exists(object(g)));}
    @Test void arbitraryPathsAndSymlinksAreRejectedWithoutTouchingTarget() throws Exception {assertThrows(cn.pawday.common.Api.Failure.class,()->provider.delete("../victim"));Path victim=Files.createTempFile("pawday-media-victim-",".txt");Files.writeString(victim,"DO NOT REMOVE");Path link=ROOT.resolve("media/"+UUID.randomUUID()+".png");try{try{Files.createSymbolicLink(link,victim);}catch(UnsupportedOperationException|IOException noSymlinkPrivilege){return;}assertThrows(cn.pawday.common.Api.Failure.class,()->provider.delete("media/"+link.getFileName()));assertThrows(cn.pawday.common.Api.Failure.class,()->provider.read("media/"+link.getFileName()));assertEquals("DO NOT REMOVE",Files.readString(victim));}finally{Files.deleteIfExists(link);Files.deleteIfExists(victim);}}
    @Test void recoveredReadyObjectSurvivesAnExpiredUploadWorker(){
        var g=grant(png,"image/png","AVATAR",tokenA);var actual=(CheckedLocal)provider;
        actual.afterPut=()->{clock.advance(61);service.recover();};
        try{assertEquals(409,upload(g,png,"image/png",tokenA).status());assertEquals("READY",db.queryForObject("SELECT status FROM media_asset",String.class));assertTrue(Files.exists(object(g)));}
        finally{actual.afterPut=null;}
    }
    @Test void abandonedStagingFileIsReapedWithoutDeletingRecentUploads() throws Exception {
        Path old=ROOT.resolve(".incoming/upload-abandoned.tmp"),recent=ROOT.resolve(".incoming/upload-current.tmp");Files.write(old,png);Files.write(recent,png);
        Files.setLastModifiedTime(old,java.nio.file.attribute.FileTime.from(clock.instant().minusSeconds(172800)));service.recover();assertFalse(Files.exists(old));assertTrue(Files.exists(recent));
    }
    @Test void deleteAuditFailureRollsBackPrivacyTombstone() {
        var g=grant(png,"image/png","AVATAR",tokenA);assertEquals(200,upload(g,png,"image/png",tokenA).status());UUID id=UUID.fromString(g.data().get("asset_id").asString());
        db.execute("CREATE FUNCTION privacy_media_audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='media.delete-requested' THEN RAISE EXCEPTION 'TEST_ONLY_AUDIT_FAILURE'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER privacy_media_audit_fail BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION privacy_media_audit_fail()");
        try{assertEquals(503,request("DELETE","/media/"+id,null,tokenA).status());assertEquals("READY",db.queryForObject("SELECT status FROM media_asset WHERE id=?",String.class,id));assertEquals(0,db.queryForObject("SELECT count(*) FROM privacy_journal WHERE subject_id=?",Integer.class,id));assertTrue(Files.exists(object(g)));}
        finally{db.execute("DROP TRIGGER privacy_media_audit_fail ON audit_event");db.execute("DROP FUNCTION privacy_media_audit_fail()");}
    }
    @Test void uploadTokenIsRedactedButBusinessCodeRemains(){@SuppressWarnings("unchecked")var redacted=(Map<String,Object>)audit.redact(Map.of("upload_token","DO-NOT-LOG","code","MEDIA_READY","reason_code","OWNER_DELETE"));assertEquals("[REDACTED]",redacted.get("upload_token"));assertEquals("MEDIA_READY",redacted.get("code"));assertEquals("OWNER_DELETE",redacted.get("reason_code"));}
}
