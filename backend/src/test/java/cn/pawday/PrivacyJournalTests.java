package cn.pawday;

import cn.pawday.privacy.*;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.nio.file.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.*;
import tools.jackson.databind.json.JsonMapper;
import static org.junit.jupiter.api.Assertions.*;

/** Actual PostgreSQL row locks/transactions plus independent filesystem; no MQ mocks. */
class PrivacyJournalTests {
    static EmbeddedPostgres pg;static JdbcTemplate db;static TransactionTemplate tx;
    static final byte[] KEY="TEST_ONLY_M64_PRIVATE_EXPORT_32_BYTES".getBytes(java.nio.charset.StandardCharsets.UTF_8);
    @TempDir Path directory;UUID user,conversation;long initial;
    static class MutableClock extends Clock {Instant instant=Instant.now();public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId zone){return this;}public Instant instant(){return instant;}}
    @BeforeAll static void start()throws Exception {pg=EmbeddedPostgres.builder().setPort(0).start();var ds=new DriverManagerDataSource(pg.getJdbcUrl("postgres","postgres"),"postgres","postgres");db=new JdbcTemplate(ds);tx=new TransactionTemplate(new DataSourceTransactionManager(ds));Flyway.configure().dataSource(ds).load().migrate();}
    @AfterAll static void stop()throws Exception {pg.close();}
    @BeforeEach void seed(){user=UUID.randomUUID();conversation=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",user);db.update("INSERT INTO ai_preferences(user_id,personalization_enabled) VALUES (?,true)",user);db.update("INSERT INTO ai_conversations(id,user_id,expires_at) VALUES (?,?,now()+interval '1 hour')",conversation,user);db.update("UPDATE privacy_export_state SET claim_token=NULL,lease_until=NULL,next_attempt_at=now()-interval '1 day',attempts=0,last_error_code=NULL");initial=count();}
    long count(){return db.queryForObject("SELECT count(*) FROM privacy_journal",Long.class);}
    void remove(){db.update("UPDATE ai_conversations SET status='DELETED' WHERE id=?",conversation);}
    PrivacyExportService service(PrivacyExportProvider p,Clock c,long lease){return new PrivacyExportService(db,tx,p,KEY,c,lease);}
    void due(){db.update("UPDATE privacy_export_state SET next_attempt_at=now()-interval '1 day'");}
    @Test void committedDeleteAndReasonAreCaptured(){remove();assertEquals(initial+1,count());assertEquals("USER_DELETED",db.queryForObject("SELECT reason_code FROM privacy_journal WHERE subject_id=?",String.class,conversation));}
    @Test void rollbackRemovesBusinessFactAndSequence(){long before=db.queryForObject("SELECT last_sequence FROM privacy_journal_head",Long.class);assertThrows(IllegalStateException.class,()->tx.executeWithoutResult(s->{remove();throw new IllegalStateException("TEST_ONLY_ROLLBACK");}));assertEquals(initial,count());assertEquals(before,db.queryForObject("SELECT last_sequence FROM privacy_journal_head",Long.class));assertEquals("ACTIVE",db.queryForObject("SELECT status FROM ai_conversations WHERE id=?",String.class,conversation));}
    @Test void duplicateDeleteProducesOneTombstone(){remove();remove();assertEquals(initial+1,count());}
    @Test void expirationRecordsExistingPolicyFact(){db.update("UPDATE ai_conversations SET status='EXPIRED' WHERE id=?",conversation);assertEquals("RETENTION_EXPIRED",db.queryForObject("SELECT reason_code FROM privacy_journal WHERE subject_id=?",String.class,conversation));assertEquals(db.queryForObject("SELECT expires_at FROM ai_conversations WHERE id=?",Timestamp.class,conversation),db.queryForObject("SELECT retention_deadline FROM privacy_journal WHERE subject_id=?",Timestamp.class,conversation));}
    @Test void everyDistinctConsentRevocationIsCaptured(){db.update("UPDATE ai_preferences SET personalization_enabled=false WHERE user_id=?",user);db.update("UPDATE ai_preferences SET personalization_enabled=false WHERE user_id=?",user);db.update("UPDATE ai_preferences SET personalization_enabled=true WHERE user_id=?",user);db.update("UPDATE ai_preferences SET personalization_enabled=false WHERE user_id=?",user);assertEquals(2,db.queryForObject("SELECT count(*) FROM privacy_journal WHERE subject_id=? AND kind='AI_PERSONALIZATION_REVOKE'",Integer.class,user));}
    @Test void appendOnlyUpdateDeleteAndTruncateAreRejected(){remove();for(String sql:List.of("UPDATE privacy_journal SET reason_code='FORGED'","DELETE FROM privacy_journal","TRUNCATE privacy_journal"))assertThrows(org.springframework.dao.DataAccessException.class,()->db.execute(sql));}
    @Test void concurrentCommitWaitsForEarlierWriterWithoutGap()throws Exception {var entered=new CountDownLatch(1);var release=new CountDownLatch(1);try(var pool=Executors.newVirtualThreadPerTaskExecutor()){var a=pool.submit(()->tx.executeWithoutResult(s->{remove();entered.countDown();try{assertTrue(release.await(10,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}}));assertTrue(entered.await(5,TimeUnit.SECONDS));var b=pool.submit(()->db.update("UPDATE ai_preferences SET personalization_enabled=false WHERE user_id=?",user));Thread.sleep(150);assertFalse(b.isDone());assertEquals(initial,count());release.countDown();a.get(10,TimeUnit.SECONDS);b.get(10,TimeUnit.SECONDS);}assertEquals(initial+2,count());assertEquals(count(),db.queryForObject("SELECT last_sequence FROM privacy_journal_head",Long.class));}
    @Test void exporterWaitsForCommitAndIncludesEntirePrefix()throws Exception {var entered=new CountDownLatch(1);var release=new CountDownLatch(1);var snapshot=new AtomicReference<PrivacyExportService.Checkpoint>();try(var pool=Executors.newVirtualThreadPerTaskExecutor()){var a=pool.submit(()->tx.executeWithoutResult(s->{remove();entered.countDown();try{assertTrue(release.await(10,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}}));assertTrue(entered.await(5,TimeUnit.SECONDS));var b=pool.submit(()->service(snapshot::set,Clock.systemUTC(),60).runOne());Thread.sleep(150);assertFalse(b.isDone());release.countDown();a.get(10,TimeUnit.SECONDS);assertTrue(b.get(10,TimeUnit.SECONDS));}assertEquals(count(),snapshot.get().sequence());}
    @Test void realFilesystemExportIsSignedAndOutsideTransaction()throws Exception {remove();assertTrue(service(new LocalPrivacyExportProvider(directory,KEY),Clock.systemUTC(),60).runOne());var envelope=new JsonMapper().readTree(Files.readAllBytes(directory.resolve("latest.json")));var bytes=Base64.getDecoder().decode(envelope.get("payload").asString());assertEquals(PrivacyExportService.sign(bytes,KEY),envelope.get("signature").asString());assertEquals(count(),new JsonMapper().readTree(bytes).get("last_sequence").asLong());assertEquals(count(),db.queryForObject("SELECT exported_sequence FROM privacy_export_state",Long.class));}
    @Test void unavailableExportDoesNotRollbackBusinessAndRetries()throws Exception {remove();Path file=directory.resolve("unavailable");Files.writeString(file,"TEST_ONLY_NOT_A_DIRECTORY");service(new LocalPrivacyExportProvider(file,KEY),Clock.systemUTC(),60).runOne();assertEquals(initial+1,count());assertEquals("INDEPENDENT_EXPORT_UNAVAILABLE",db.queryForObject("SELECT last_error_code FROM privacy_export_state",String.class));assertFalse(service(new LocalPrivacyExportProvider(directory.resolve("ok"),KEY),Clock.systemUTC(),60).runOne());due();assertTrue(service(new LocalPrivacyExportProvider(directory.resolve("ok"),KEY),Clock.systemUTC(),60).runOne());assertNull(db.queryForObject("SELECT last_error_code FROM privacy_export_state",String.class));}
    @Test void lostAcknowledgementRetriesWithoutDuplicateBusinessResults()throws Exception {remove();var files=new LocalPrivacyExportProvider(directory,KEY);service(c->{files.publish(c);throw new IllegalStateException("TEST_ONLY_ACK_LOSS");},Clock.systemUTC(),60).runOne();assertTrue(Files.exists(directory.resolve("latest.json")));long facts=count();due();service(files,Clock.systemUTC(),60).runOne();assertEquals(facts,count());assertEquals(facts,db.queryForObject("SELECT exported_sequence FROM privacy_export_state",Long.class));}
    @Test void liveLeaseExcludesSecondWorker(){db.update("UPDATE privacy_export_state SET claim_token=?,lease_until=now()+interval '1 hour'",UUID.randomUUID());assertFalse(service(c->fail("LIVE_LEASE_STOLEN"),Clock.systemUTC(),60).runOne());}
    @Test void expiredLeaseIsRecovered(){db.update("UPDATE privacy_export_state SET claim_token=?,lease_until=now()-interval '1 hour'",UUID.randomUUID());assertTrue(service(new LocalPrivacyExportProvider(directory,KEY),Clock.systemUTC(),60).runOne());assertNull(db.queryForObject("SELECT claim_token FROM privacy_export_state",UUID.class));}
    @Test void staleWorkerCannotReplaceNewerHeadOrAcknowledge()throws Exception {remove();var files=new LocalPrivacyExportProvider(directory,KEY);var clock=new MutableClock();var older=new AtomicReference<PrivacyExportService.Checkpoint>();service(c->{older.set(c);clock.instant=clock.instant.plusSeconds(2);db.update("UPDATE ai_preferences SET personalization_enabled=false WHERE user_id=?",user);assertTrue(service(files,clock,1).runOne());files.publish(c);},clock,1).runOne();assertEquals(count(),db.queryForObject("SELECT exported_sequence FROM privacy_export_state",Long.class));var envelope=new JsonMapper().readTree(Files.readAllBytes(directory.resolve("latest.json")));assertTrue(new JsonMapper().readTree(Base64.getDecoder().decode(envelope.get("payload").asString())).get("last_sequence").asLong()>older.get().sequence());}
    @Test void corruptIndependentHeadBlocksOverwrite()throws Exception {Files.writeString(directory.resolve("latest.json"),"{}");remove();service(new LocalPrivacyExportProvider(directory,KEY),Clock.systemUTC(),60).runOne();assertEquals("{}",Files.readString(directory.resolve("latest.json")));assertNotNull(db.queryForObject("SELECT last_error_code FROM privacy_export_state",String.class));}
    @Test void coverageCanAdvanceWithoutInventingPrivacyEvents()throws Exception {long facts=count();service(new LocalPrivacyExportProvider(directory,KEY),Clock.systemUTC(),60).runOne();var old=db.queryForObject("SELECT covered_until FROM privacy_export_state",Timestamp.class);due();service(new LocalPrivacyExportProvider(directory,KEY),Clock.systemUTC(),60).runOne();assertEquals(facts,count());assertFalse(db.queryForObject("SELECT covered_until FROM privacy_export_state",Timestamp.class).before(old));}
    @Test void separateSigningKeyIsMandatory(){assertThrows(IllegalArgumentException.class,()->service(c->{},Clock.systemUTC(),0));assertThrows(IllegalArgumentException.class,()->new PrivacyExportService(db,tx,c->{},new byte[16],Clock.systemUTC(),60));}
    @Test void existingVersionTwentyDatabaseUpgradesWithConservativeBaseline()throws Exception {
        try(var old=EmbeddedPostgres.builder().setPort(0).start()) {
            var ds=new DriverManagerDataSource(old.getJdbcUrl("postgres","postgres"),"postgres","postgres");var jdbc=new JdbcTemplate(ds);
            Flyway.configure().dataSource(ds).target("020").load().migrate();UUID owner=UUID.randomUUID();
            jdbc.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",owner);jdbc.update("INSERT INTO ai_preferences(user_id) VALUES (?)",owner);
            for(String state:List.of("DELETED","EXPIRED"))jdbc.update("INSERT INTO ai_conversations(id,user_id,status,expires_at) VALUES (?,?,?,now()-interval '1 day')",UUID.randomUUID(),owner,state);
            var migration=Flyway.configure().dataSource(ds).load();migration.migrate();
            assertEquals(3,jdbc.queryForObject("SELECT count(*) FROM privacy_journal WHERE reason_code='MIGRATION_BASELINE'",Integer.class));
            assertEquals(3,jdbc.queryForObject("SELECT last_sequence FROM privacy_journal_head",Integer.class));
            migration.migrate();assertEquals(3,jdbc.queryForObject("SELECT count(*) FROM privacy_journal",Integer.class));
        }
    }
    @Test @SuppressWarnings("unchecked") void correctlySignedConflictingPrefixCannotOverwriteIndependentHead()throws Exception {
        remove();var snapshot=new AtomicReference<PrivacyExportService.Checkpoint>();var files=new LocalPrivacyExportProvider(directory,KEY);
        service(c->{snapshot.set(c);files.publish(c);},Clock.systemUTC(),60).runOne();byte[] before=Files.readAllBytes(directory.resolve("latest.json"));
        var mapper=new JsonMapper();var payload=mapper.readValue(snapshot.get().payload(),Map.class);
        ((Map<String,Object>)((List<?>)payload.get("events")).getFirst()).put("kind","MEDIA_DELETE".equals(((Map<?,?>)((List<?>)payload.get("events")).getFirst()).get("kind"))?"AI_CONVERSATION_DELETE":"MEDIA_DELETE");
        byte[] changed=mapper.writeValueAsBytes(payload);var conflict=new PrivacyExportService.Checkpoint(changed,PrivacyExportService.sign(changed,KEY),PrivacyExportService.sha256(changed),snapshot.get().sequence(),snapshot.get().coveredUntil());
        assertThrows(IllegalStateException.class,()->files.publish(conflict));assertArrayEquals(before,Files.readAllBytes(directory.resolve("latest.json")));
    }
}
