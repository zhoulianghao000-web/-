package cn.pawday;

import cn.pawday.outbox.*;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import com.rabbitmq.client.*;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.awaitility.Awaitility.await;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.*;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.*;
import org.springframework.test.context.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.amqp.rabbit.core.*;
import org.springframework.amqp.core.Message;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(RabbitOutboxIT.FixtureBeans.class)
class RabbitOutboxIT {
    static final EmbeddedPostgres PG;
    static {try {PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    static String env(String name,String fallback){return System.getenv().getOrDefault(name,fallback);}
    static final String HOST=env("PAWDAY_IT_RABBIT_HOST","127.0.0.1"),USER=env("PAWDAY_IT_RABBIT_USER","pawday_it"),PASSWORD=env("PAWDAY_IT_RABBIT_PASSWORD","TEST_ONLY_m22_broker");
    static final int PORT=Integer.parseInt(env("PAWDAY_IT_RABBIT_PORT","5672"));
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){
        r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");
        r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("spring.rabbitmq.host",()->HOST);r.add("spring.rabbitmq.port",()->PORT);r.add("spring.rabbitmq.username",()->USER);r.add("spring.rabbitmq.password",()->PASSWORD);
        r.add("pawday.search.enabled",()->false);r.add("management.health.redis.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);
        r.add("pawday.outbox.max-attempts",()->3);r.add("pawday.outbox.retry-base-ms",()->50);r.add("pawday.outbox.retry-max-ms",()->200);r.add("pawday.outbox.confirm-timeout-ms",()->500);r.add("pawday.outbox.lease-ms",()->2000);
    }
    static final List<Map<String,Object>> SAMPLES=new CopyOnWriteArrayList<>();
    @AfterAll static void finish() throws Exception {java.nio.file.Files.writeString(java.nio.file.Path.of("target/m22-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
    static class TestClock extends Clock {volatile Instant time=Instant.now();public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId z){return this;}public Instant instant(){return time;}}
    static class Provider implements SmsGateway {
        final Map<String,String> deliveries=new ConcurrentHashMap<>();final AtomicInteger calls=new AtomicInteger();volatile boolean fail;volatile boolean ambiguous;
        public void send(String id,String phone,String code){assertFalse(TransactionSynchronizationManager.isActualTransactionActive(),"External SMS must run after transaction commit");calls.incrementAndGet();if(fail)throw new IllegalStateException("TEST provider failure");deliveries.putIfAbsent(id,code);if(ambiguous){ambiguous=false;throw new IllegalStateException("TEST receipt lost after provider success");}}
        void reset(){deliveries.clear();calls.set(0);fail=false;ambiguous=false;}
    }
    @TestConfiguration static class FixtureBeans {@Bean @Primary Provider provider(){return new Provider();}@Bean @Primary TestClock testClock(){return new TestClock();}}
    @Autowired JdbcTemplate db;@Autowired TransactionTemplate tx;@Autowired OutboxWriter writer;@Autowired OutboxRepository repo;@Autowired RabbitPublisher rabbitPublisher;@Autowired OutboxPublisher publisher;@Autowired InboxConsumer consumer;@Autowired RabbitInboxListener listener;@Autowired SmsDeliveryWorker sms;
    @Autowired DeliveryPolicy policy;@Autowired Crypto crypto;@Autowired Provider provider;@Autowired AuthService auth;@Autowired AuditWriter audit;@Autowired PasswordEncoder passwords;@Autowired TestClock clock;@Autowired RabbitAdmin admin;@Autowired CachingConnectionFactory springConnection;
    @LocalServerPort int httpPort;final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newHttpClient();
    Connection connection;Channel channel;UUID adminId;static String passwordHash;static final String STAFF_PASSWORD="TEST_ONLY_M22_admin_password";static final byte[] MFA="12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    @BeforeEach void setup() throws Exception {
        // No assumption/skip and no mock: a missing real broker fails this mandatory profile.
        var factory=new com.rabbitmq.client.ConnectionFactory();factory.setHost(HOST);factory.setPort(PORT);factory.setUsername(USER);factory.setPassword(PASSWORD);factory.setConnectionTimeout(3000);connection=factory.newConnection();channel=connection.createChannel();admin.initialize();channel.queuePurge(RabbitTopology.QUEUE);channel.queuePurge(RabbitTopology.DLQ);
        db.execute("ALTER TABLE audit_event DISABLE TRIGGER audit_event_no_truncate");
        try {db.execute("TRUNCATE outbox_replay_command,processed_event,sms_delivery,outbox_event,identity_command,reverify_grant,auth_refresh_token,auth_session,otp_challenge,auth_rate_bucket,principal_store_scope,principal_role,identity_principal,merchant_store,merchant,app_user,role_permission,role,audit_event CASCADE");}finally{db.execute("ALTER TABLE audit_event ENABLE TRIGGER audit_event_no_truncate");}
        provider.reset();clock.time=Instant.now();adminId=UUID.randomUUID();UUID role=UUID.randomUUID();if(passwordHash==null)passwordHash=passwords.encode(STAFF_PASSWORD);
        db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,'ADMIN','test-m22-admin',?,?)",adminId,passwordHash,crypto.encrypt(MFA));
        db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,'ADMIN','TEST M22','TEST M22 admin')",role);db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code IN ('outbox.read','outbox.replay','audit.read')",role);db.update("INSERT INTO principal_role VALUES (?,?,'ADMIN')",adminId,role);
    }
    @AfterEach void cleanup() throws Exception {if(channel!=null && channel.isOpen())channel.close();if(connection!=null && connection.isOpen())connection.close();}
    UUID event(int version) {
        return tx.execute(s->{UUID id=UUID.randomUUID();String code=crypto.otp();db.update("INSERT INTO otp_challenge(id,phone_e164,purpose,code_hash,expires_at,created_at,delivery_secret_ciphertext) VALUES (?,'+8613800000001','LOGIN',?,?,?,?)",id,crypto.otpHash(id.toString(),code),Timestamp.from(clock.instant().plusSeconds(600)),Timestamp.from(clock.instant()),crypto.encrypt(code.getBytes(StandardCharsets.UTF_8)));return writer.append("OTP_CHALLENGE",id.toString(),"otp.sms.requested",version,Map.of("challenge_id",id.toString()),UUID.randomUUID().toString());});
    }
    long count(String table){return db.queryForObject("SELECT count(*) FROM "+table,Long.class);}
    String state(UUID id){return db.queryForObject("SELECT status FROM outbox_event WHERE id=?",String.class,id);}
    GetResponse next(String queue) {var result=new AtomicReference<GetResponse>();await().atMost(Duration.ofSeconds(5)).pollInterval(Duration.ofMillis(20)).until(()->{result.set(channel.basicGet(queue,false));return result.get()!=null;});return result.get();}
    void receive() throws Exception {var delivery=next(RabbitTopology.QUEUE);var props=new org.springframework.amqp.core.MessageProperties();props.setDeliveryTag(delivery.getEnvelope().getDeliveryTag());props.setMessageId(delivery.getProps().getMessageId());listener.receive(new Message(delivery.getBody(),props),channel);}
    void pump(){publisher.publishOne();try{var message=channel.basicGet(RabbitTopology.QUEUE,false);if(message!=null){var props=new org.springframework.amqp.core.MessageProperties();props.setDeliveryTag(message.getEnvelope().getDeliveryTag());props.setMessageId(message.getProps().getMessageId());listener.receive(new Message(message.getBody(),props),channel);}}catch(Exception e){throw new AssertionError(e);}}
    @Test void transactionalWriterRequiresTransactionAndRollsBackWithBusiness() {
        assertThrows(IllegalStateException.class,()->writer.append("TEST","1","test",1,Map.of(),null));
        var unrelated=new org.springframework.transaction.support.AbstractPlatformTransactionManager(){
            protected Object doGetTransaction(){return new Object();}
            protected void doBegin(Object transaction,org.springframework.transaction.TransactionDefinition definition){}
            protected void doCommit(org.springframework.transaction.support.DefaultTransactionStatus status){}
            protected void doRollback(org.springframework.transaction.support.DefaultTransactionStatus status){}
        };
        assertThrows(IllegalStateException.class,()->new TransactionTemplate(unrelated).executeWithoutResult(s->writer.append("TEST","1","test",1,Map.of(),null)));
        assertThrows(IllegalStateException.class,()->tx.executeWithoutResult(s->{event(1);throw new IllegalStateException("TEST rollback");}));
        assertEquals(0,count("otp_challenge"));assertEquals(0,count("outbox_event"));assertEquals(0,provider.calls.get());
    }
    @Test void actualOtpRequestCommitsBeforeAnySmsOrBrokerPublication() throws Exception {
        var request=new org.springframework.mock.web.MockHttpServletRequest();request.setRemoteAddr("127.0.0.1");
        var receipt=auth.requestCode("+8613800000001","LOGIN",null,request);assertEquals(1,count("otp_challenge"));assertEquals(1,count("outbox_event"));assertEquals(0,provider.calls.get());
        String payload=db.queryForObject("SELECT payload::text FROM outbox_event",String.class);assertFalse(payload.contains("phone"));assertFalse(payload.contains("code"));
        assertTrue(publisher.publishOne());receive();assertTrue(sms.sendOne());assertEquals(1,provider.deliveries.size());assertTrue(provider.deliveries.containsKey(receipt.id().toString()));
    }
    @Test void brokerConfirmIsRequiredAndDuplicateDeliveryDoesNotDuplicateBusiness() throws Exception {
        UUID id=event(1);var claim=repo.claim("TEST").orElseThrow();assertEquals("PUBLISHING",state(id));rabbitPublisher.publish(claim);assertTrue(repo.published(claim));assertEquals("PUBLISHED",state(id));receive();
        rabbitPublisher.publish(claim);receive();assertEquals(1,count("processed_event"));assertEquals(1,count("sms_delivery"));assertTrue(sms.sendOne());assertFalse(sms.sendOne());assertEquals(1,provider.deliveries.size());
    }
    @Test void successfulConsumerCommitSurvivesCrashBeforeAck() throws Exception {
        event(1);publisher.publishOne();var first=next(RabbitTopology.QUEUE);consumer.process(json.readValue(first.getBody(),EventEnvelope.class));assertEquals(1,count("sms_delivery"));channel.close();channel=connection.createChannel();var redelivered=next(RabbitTopology.QUEUE);assertTrue(redelivered.getEnvelope().isRedeliver());consumer.process(json.readValue(redelivered.getBody(),EventEnvelope.class));channel.basicAck(redelivered.getEnvelope().getDeliveryTag(),false);assertEquals(1,count("sms_delivery"));sms.sendOne();assertEquals(1,provider.deliveries.size());
    }
    @Test void twoPublishersActuallySendDistinctClaimsToBroker() throws Exception {
        for(int i=0;i<12;i++)event(1);var second=new OutboxPublisher(repo,rabbitPublisher);
        try(var pool=Executors.newFixedThreadPool(2)){var a=pool.submit(()->{while(publisher.publishOne()) {}});var b=pool.submit(()->{while(second.publishOne()) {}});a.get(15,TimeUnit.SECONDS);b.get(15,TimeUnit.SECONDS);}
        assertEquals(12,db.queryForObject("SELECT count(*) FROM outbox_event WHERE status='PUBLISHED' AND attempt_count=1",Integer.class));Set<String> ids=new HashSet<>();for(int i=0;i<12;i++){var delivery=next(RabbitTopology.QUEUE);ids.add(delivery.getProps().getMessageId());channel.basicAck(delivery.getEnvelope().getDeliveryTag(),false);}assertEquals(12,ids.size());
    }
    @Test void lostBrokerConfirmCausesSafeRetryAgainstRealQueue() throws Exception {
        UUID id=event(1);var claim=repo.claim("TEST-confirm-loss").orElseThrow();
        try(var proxy=new ConfirmDroppingProxy(HOST,PORT)) {
            var cf=new CachingConnectionFactory("127.0.0.1",proxy.port());cf.setUsername(USER);cf.setPassword(PASSWORD);cf.setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED);cf.setPublisherReturns(true);var template=new RabbitTemplate(cf);template.setMandatory(true);
            try {var failure=assertThrows(RabbitPublisher.PublishFailure.class,()->new RabbitPublisher(template,policy).publish(claim));assertEquals("CONFIRM_TIMEOUT",failure.code);assertTrue(proxy.discarded.get()>0);repo.failed(claim,failure.code);}finally{cf.destroy();}
        }
        // Closing the fault-injected connection can produce an expected background channel-close exception.
        // State, real queue redelivery and side effects remain explicit assertions below.
        assertEquals("FAILED_RETRYABLE",state(id));receive();await().dontCatchUncaughtExceptions().atMost(Duration.ofSeconds(5)).until(()->{publisher.publishOne();return state(id).equals("PUBLISHED");});receive();assertEquals(1,count("sms_delivery"));sms.sendOne();assertEquals(1,provider.deliveries.size());
    }
    @Test void expiredLeaseFencesOldWorkerAndRedeliveryIsDeduplicated() throws Exception {
        UUID id=event(1);var old=repo.claim("OLD").orElseThrow();db.update("UPDATE outbox_event SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE id=?",id);
        repo.claim("RECOVER");await().atMost(Duration.ofSeconds(2)).until(()->repo.claim("NEW").map(fresh->{rabbitPublisher.publish(old);assertFalse(repo.published(old));rabbitPublisher.publish(fresh);assertTrue(repo.published(fresh));return true;}).orElse(false));
        receive();receive();assertEquals(1,count("sms_delivery"));assertEquals("PUBLISHED",state(id));
    }
    @Test void unsupportedVersionRetriesThenDeadLettersViaRealBroker() throws Exception {
        UUID id=event(99);await().atMost(Duration.ofSeconds(8)).pollInterval(Duration.ofMillis(30)).until(()->{pump();return db.queryForObject("SELECT count(*) FROM processed_event WHERE event_id=? AND status='DEAD'",Integer.class,id)==1;});
        assertEquals(3,db.queryForObject("SELECT attempt_count FROM processed_event WHERE event_id=?",Integer.class,id));assertEquals(0,count("sms_delivery"));await().atMost(Duration.ofSeconds(5)).until(()->{publisher.publishOne();return channel.queueDeclarePassive(RabbitTopology.DLQ).getMessageCount()>0;});var dead=next(RabbitTopology.DLQ);assertTrue(new String(dead.getBody(),StandardCharsets.UTF_8).contains("UNSUPPORTED_EVENT_VERSION"));channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);
    }
    @Test void malformedPoisonMessageUsesBrokerDeadLetterPath() throws Exception {
        channel.confirmSelect();channel.basicPublish(RabbitTopology.EXCHANGE,"otp.sms.requested",new AMQP.BasicProperties.Builder().messageId(UUID.randomUUID().toString()).deliveryMode(2).build(),"{INVALID JSON".getBytes(StandardCharsets.UTF_8));channel.waitForConfirmsOrDie(3000);receive();var dead=next(RabbitTopology.DLQ);assertEquals("{INVALID JSON",new String(dead.getBody(),StandardCharsets.UTF_8));channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);assertEquals(0,count("sms_delivery"));
        UUID malformed=UUID.randomUUID();channel.basicPublish(RabbitTopology.EXCHANGE,"otp.sms.requested",new AMQP.BasicProperties.Builder().messageId(malformed.toString()).deliveryMode(2).build(),json.writeValueAsBytes(new EventEnvelope(malformed,null,1,"OTP_CHALLENGE",malformed.toString(),null,1,0,Map.of())));channel.waitForConfirmsOrDie(3000);receive();var missing=next(RabbitTopology.DLQ);assertTrue(new String(missing.getBody(),StandardCharsets.UTF_8).contains("\"event_type\":null"));channel.basicAck(missing.getEnvelope().getDeliveryTag(),false);assertEquals(0,count("processed_event"));
    }
    @Test void ambiguousProviderReceiptReusesSameIdempotencyKey() throws Exception {
        event(1);publisher.publishOne();receive();provider.ambiguous=true;sms.sendOne();assertEquals(1,provider.deliveries.size());assertEquals("FAILED_RETRYABLE",db.queryForObject("SELECT status FROM sms_delivery",String.class));await().atMost(Duration.ofSeconds(3)).until(()->sms.sendOne());assertEquals(2,provider.calls.get());assertEquals(1,provider.deliveries.size());assertEquals("DELIVERED",db.queryForObject("SELECT status FROM sms_delivery",String.class));
    }
    void brokerControl(String action) throws Exception {
        List<String> command;
        String container=System.getenv("PAWDAY_IT_RABBIT_CONTAINER"),ctl=System.getenv("PAWDAY_RABBITMQ_CTL");
        if(container!=null){if(!container.matches("[A-Za-z0-9_.-]+"))throw new IllegalArgumentException("Invalid test container");command=List.of("docker","exec",container,"rabbitmqctl",action);}
        else if(ctl!=null)command=List.of("cmd.exe","/c",ctl,action);
        else throw new IllegalStateException("Real broker lifecycle control is mandatory: PAWDAY_IT_RABBIT_CONTAINER or PAWDAY_RABBITMQ_CTL required");
        var file=java.nio.file.Files.createTempFile(java.nio.file.Path.of("target"),"broker-control-",".log");
        var process=new ProcessBuilder(command).redirectErrorStream(true).redirectOutput(file.toFile()).start();
        if(!process.waitFor(30,TimeUnit.SECONDS)){process.destroyForcibly();throw new AssertionError("Broker lifecycle command timed out");}
        assertEquals(0,process.exitValue(),()->"Broker control failed: "+file);
    }
    @Test void stoppedRealBrokerRetainsCommittedEventAndRecoversAfterRestart() throws Exception {
        brokerControl("stop_app");
        UUID id;
        try {springConnection.resetConnection();channel=null;connection.abort();connection=null;id=event(1);assertTrue(publisher.publishOne());assertEquals("FAILED_RETRYABLE",state(id));assertEquals(1,count("otp_challenge"));assertEquals(0,provider.calls.get());}
        finally {brokerControl("start_app");springConnection.resetConnection();}
        var factory=new com.rabbitmq.client.ConnectionFactory();factory.setHost(HOST);factory.setPort(PORT);factory.setUsername(USER);factory.setPassword(PASSWORD);connection=factory.newConnection();channel=connection.createChannel();admin.initialize();
        await().atMost(Duration.ofSeconds(5)).until(()->{publisher.publishOne();return state(id).equals("PUBLISHED");});receive();sms.sendOne();assertEquals(1,provider.deliveries.size());
    }
    @Test void skipLockedDoesNotWaitBehindAnotherWorker() throws Exception {
        UUID locked=event(1),other=event(1);var acquired=new CountDownLatch(1);var release=new CountDownLatch(1);
        try(var pool=Executors.newSingleThreadExecutor()) {
            var holder=pool.submit(()->tx.executeWithoutResult(s->{db.queryForMap("SELECT * FROM outbox_event WHERE id=? FOR UPDATE",locked);acquired.countDown();try{assertTrue(release.await(5,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}}));
            try {assertTrue(acquired.await(3,TimeUnit.SECONDS));var claim=assertTimeoutPreemptively(Duration.ofSeconds(2),()->repo.claim("SKIP-LOCKED").orElseThrow());assertEquals(other,claim.id());rabbitPublisher.publish(claim);repo.published(claim);}finally{release.countDown();}holder.get(5,TimeUnit.SECONDS);
        }
        assertEquals("PENDING",state(locked));assertEquals("PUBLISHED",state(other));
    }
    UUID failToDead() throws Exception {
        UUID id=event(1);channel.queueUnbind(RabbitTopology.QUEUE,RabbitTopology.EXCHANGE,"otp.sms.requested");
        try {await().atMost(Duration.ofSeconds(5)).pollInterval(Duration.ofMillis(20)).until(()->{publisher.publishOne();return state(id).equals("DEAD");});}
        finally {channel.queueBind(RabbitTopology.QUEUE,RabbitTopology.EXCHANGE,"otp.sms.requested");}
        assertEquals("UNROUTABLE_MESSAGE",db.queryForObject("SELECT last_error_code FROM outbox_event WHERE id=?",String.class,id));assertNull(db.queryForObject("SELECT published_at FROM outbox_event WHERE id=?",Timestamp.class,id));assertEquals(3,db.queryForObject("SELECT attempt_count FROM outbox_event WHERE id=?",Integer.class,id));return id;
    }
    record HttpResult(int status,JsonNode body){JsonNode data(){return body.get("data");}}
    HttpResult api(String method,String path,Object body,String token,Map<String,String> headers) throws Exception {
        var builder=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+httpPort+"/api/v1"+path)).timeout(Duration.ofSeconds(10));if(token!=null)builder.header("Authorization","Bearer "+token);headers.forEach(builder::header);
        if(body==null)builder.method(method,HttpRequest.BodyPublishers.noBody());else builder.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
        var response=http.send(builder.build(),HttpResponse.BodyHandlers.ofString());var parsed=json.readTree(response.body());var safe=json.readTree(response.body());
        if(safe.get("data")!=null && safe.get("data").isObject()){var data=(tools.jackson.databind.node.ObjectNode)safe.get("data");for(String key:List.of("access_token","refresh_token","reverify_token"))if(data.has(key))data.put(key,"A".repeat(43));}
        SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",safe));return new HttpResult(response.statusCode(),parsed);
    }
    String login() throws Exception {var response=api("POST","/admin/auth/login",Map.of("login_name","test-m22-admin","password",STAFF_PASSWORD,"device_id","TEST-IT","totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),null,Map.of());assertEquals(200,response.status());return response.data().get("access_token").asString();}
    String proof(String token,String action) throws Exception {clock.time=clock.time.plusSeconds(60);var response=api("POST","/admin/auth/reverify",Map.of("action",action,"password",STAFF_PASSWORD,"totp_code",crypto.totp(MFA,clock.instant().getEpochSecond()/30)),token,Map.of());assertEquals(200,response.status());return response.data().get("reverify_token").asString();}
    @Test void deadPublisherEventIsInDlqAndAdminCanSafelyReplay() throws Exception {
        UUID id=failToDead();publisher.publishOne();var dead=next(RabbitTopology.DLQ);channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);
        String token=login(),grant=proof(token,"outbox.replay");String path="/admin/operations/outbox/"+id+"/replay";var body=Map.of("expected_generation",0,"reason_code","TEST_BROKER_RESTORED");var headers=Map.of("X-Reverify-Token",grant,"Idempotency-Key","test-replay-command-0001");
        assertEquals(200,api("POST",path,body,token,headers).status());assertEquals("PENDING",state(id));assertEquals(200,api("POST",path,body,token,headers).status());assertEquals(1,count("outbox_replay_command"));
        assertEquals(409,api("POST",path,Map.of("expected_generation",0,"reason_code","DIFFERENT_REASON"),token,headers).status());
        String auditJson=db.queryForObject("SELECT after_json::text FROM audit_event WHERE action='outbox.replay'",String.class);assertTrue(auditJson.contains("TEST_BROKER_RESTORED"));
        publisher.publishOne();receive();sms.sendOne();assertEquals("PUBLISHED",state(id));assertEquals(1,provider.deliveries.size());
    }
    @Test void replayRequiresRbacCorrectActionAndSingleUseProof() throws Exception {
        UUID first=failToDead();String token=login(),path="/admin/operations/outbox/"+first+"/replay";var body=Map.of("expected_generation",0,"reason_code","TEST_RETRY");
        assertEquals(403,api("POST",path,body,token,Map.of("Idempotency-Key","test-replay-command-0001")).status());
        String wrong=proof(token,"session.revoke-others");assertEquals(403,api("POST",path,body,token,Map.of("Idempotency-Key","test-replay-command-0001","X-Reverify-Token",wrong)).status());
        String grant=proof(token,"outbox.replay");assertEquals(200,api("POST",path,body,token,Map.of("Idempotency-Key","test-replay-command-0001","X-Reverify-Token",grant)).status());
        // A different dead root verifies the used proof cannot authorize a second mutation.
        UUID second=event(1);db.update("UPDATE outbox_event SET status='DEAD',dead_at=clock_timestamp() WHERE id=?",second);
        assertEquals(403,api("POST","/admin/operations/outbox/"+second+"/replay",body,token,Map.of("Idempotency-Key","test-replay-command-0002","X-Reverify-Token",grant)).status());
        db.update("DELETE FROM role_permission WHERE permission_id=(SELECT id FROM permission WHERE code='outbox.replay')");assertEquals(403,api("POST",path,body,token,Map.of("Idempotency-Key","test-replay-command-0001","X-Reverify-Token",grant)).status());
    }
    @Test void replayAuditFailureRollsBackGenerationAndProofConsumption() throws Exception {
        UUID id=failToDead();String token=login(),grant=proof(token,"outbox.replay");var headers=Map.of("Idempotency-Key","test-replay-command-0001","X-Reverify-Token",grant);var body=Map.of("expected_generation",0,"reason_code","TEST_AUDIT_RECOVERY");String path="/admin/operations/outbox/"+id+"/replay";
        db.execute("CREATE FUNCTION test_replay_audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='outbox.replay' THEN RAISE EXCEPTION 'TEST audit unavailable'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER test_replay_audit_fail BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION test_replay_audit_fail()");
        try {assertEquals(503,api("POST",path,body,token,headers).status());assertEquals("DEAD",state(id));assertEquals(0,count("outbox_replay_command"));}
        finally {db.execute("DROP TRIGGER test_replay_audit_fail ON audit_event");db.execute("DROP FUNCTION test_replay_audit_fail()");}
        assertEquals(200,api("POST",path,body,token,headers).status());
    }
    @Test void providerExhaustionIsDurableDeadAndProducesDlq() throws Exception {
        UUID id=event(1);publisher.publishOne();receive();provider.fail=true;
        await().atMost(Duration.ofSeconds(5)).pollInterval(Duration.ofMillis(20)).until(()->{sms.sendOne();return db.queryForObject("SELECT status FROM sms_delivery",String.class).equals("DEAD");});assertEquals(3,provider.calls.get());assertEquals(0,provider.deliveries.size());publisher.publishOne();var dead=next(RabbitTopology.DLQ);assertTrue(new String(dead.getBody(),StandardCharsets.UTF_8).contains("SMS_PROVIDER_UNAVAILABLE"));channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);
        provider.fail=false;String token=login(),grant=proof(token,"outbox.replay");assertEquals(200,api("POST","/admin/operations/outbox/"+id+"/replay",Map.of("expected_generation",0,"reason_code","TEST_PROVIDER_RECOVERED"),token,Map.of("X-Reverify-Token",grant,"Idempotency-Key","test-replay-command-0001")).status());publisher.publishOne();receive();assertEquals(1,count("sms_delivery"));sms.sendOne();assertEquals(1,provider.deliveries.size());
    }
    @Test void expiredOtpIsSkippedAndCannotBeReactivatedByReplay() throws Exception {
        UUID id=event(1);publisher.publishOne();receive();clock.time=clock.time.plusSeconds(601);sms.sendOne();assertEquals("SKIPPED",db.queryForObject("SELECT status FROM sms_delivery",String.class));assertEquals(0,provider.calls.get());db.update("UPDATE outbox_event SET status='DEAD',dead_at=clock_timestamp() WHERE id=?",id);
        String token=login(),grant=proof(token,"outbox.replay");assertEquals(409,api("POST","/admin/operations/outbox/"+id+"/replay",Map.of("expected_generation",0,"reason_code","TEST_EXPIRED_REPLAY"),token,Map.of("X-Reverify-Token",grant,"Idempotency-Key","test-replay-command-0001")).status());
    }
    @Test void metricsArePresentAndRestrictedToPermissionedAdmin() throws Exception {
        UUID id=event(1);db.update("UPDATE outbox_event SET created_at=clock_timestamp()-interval '30 seconds' WHERE id=?",id);
        assertEquals(401,api("GET","/admin/operations/outbox/stats",null,null,Map.of()).status());String token=login();var response=api("GET","/admin/operations/outbox/stats",null,token,Map.of());assertEquals(200,response.status());assertEquals(1,response.data().get("backlog").asInt());assertTrue(response.data().get("oldest_event_age_seconds").asDouble()>=30);assertEquals(200,api("GET","/admin/operations/outbox",null,token,Map.of()).status());
        var scrape=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+httpPort+"/actuator/prometheus")).header("Authorization","Bearer "+token).GET().build(),HttpResponse.BodyHandlers.ofString());assertEquals(200,scrape.statusCode());assertTrue(scrape.body().contains("pawday_outbox_backlog"));assertTrue(scrape.body().contains("pawday_outbox_oldest_age_seconds"));
        db.update("DELETE FROM role_permission WHERE permission_id=(SELECT id FROM permission WHERE code='outbox.read')");assertEquals(403,api("GET","/admin/operations/outbox/stats",null,token,Map.of()).status());
    }
    @Test void explicitAuditDenylistPreservesBusinessCodes(){
        String data=json.writeValueAsString(audit.redact(Map.of("code","PRICING_V1_1","reason_code","BROKER_NACK","rule_code","COUPON_A","otp_code","123456","totp_code","654321","access_token","TEST_SECRET")));
        assertTrue(data.contains("PRICING_V1_1"));assertTrue(data.contains("BROKER_NACK"));assertTrue(data.contains("COUPON_A"));assertFalse(data.contains("123456"));assertFalse(data.contains("654321"));assertFalse(data.contains("TEST_SECRET"));
    }
    @Test void failedRetryTransportMakesOriginalInboxReplayable() throws Exception {
        UUID id=event(99);publisher.publishOne();receive();assertEquals("FAILED_RETRYABLE",db.queryForObject("SELECT status FROM processed_event WHERE event_id=?",String.class,id));
        channel.queueUnbind(RabbitTopology.QUEUE,RabbitTopology.EXCHANGE,"otp.sms.requested");
        try {await().atMost(Duration.ofSeconds(5)).pollInterval(Duration.ofMillis(20)).until(()->{publisher.publishOne();return db.queryForObject("SELECT status FROM processed_event WHERE event_id=?",String.class,id).equals("DEAD");});}
        finally {channel.queueBind(RabbitTopology.QUEUE,RabbitTopology.EXCHANGE,"otp.sms.requested");}
        assertEquals("PUBLISHED",state(id));String token=login(),grant=proof(token,"outbox.replay");assertEquals(200,api("POST","/admin/operations/outbox/"+id+"/replay",Map.of("expected_generation",0,"reason_code","TEST_RETRY_TRANSPORT_FIXED"),token,Map.of("X-Reverify-Token",grant,"Idempotency-Key","test-replay-command-0001")).status());assertEquals("PENDING",state(id));
    }
    @Test void failedDlqTransportCanReplayMetadataWithoutReplayingBusiness() throws Exception {
        UUID root=failToDead();UUID transport=db.queryForObject("SELECT id FROM outbox_event WHERE transport_kind='DEAD_LETTER'",UUID.class);
        channel.queueUnbind(RabbitTopology.DLQ,RabbitTopology.DLX,"dead");
        try {await().atMost(Duration.ofSeconds(5)).pollInterval(Duration.ofMillis(20)).until(()->{publisher.publishOne();return state(transport).equals("DEAD");});}
        finally {channel.queueBind(RabbitTopology.DLQ,RabbitTopology.DLX,"dead");}
        clock.time=clock.time.plusSeconds(1000);String token=login(),grant=proof(token,"outbox.replay");
        assertEquals(200,api("POST","/admin/operations/outbox/"+transport+"/replay",Map.of("expected_generation",0,"reason_code","TEST_DLQ_RESTORED"),token,Map.of("X-Reverify-Token",grant,"Idempotency-Key","test-replay-command-0001")).status());assertEquals("DEAD",state(root));assertEquals(0,count("sms_delivery"));publisher.publishOne();var dead=next(RabbitTopology.DLQ);channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);assertEquals("PUBLISHED",state(transport));
    }
    @Test void otpAuditRollbackCannotSendAnUncommittedChallenge() throws Exception {
        db.execute("CREATE FUNCTION test_otp_rollback() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='auth.otp.requested' THEN RAISE EXCEPTION 'TEST OTP rollback'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER test_otp_rollback BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION test_otp_rollback()");
        try {assertEquals(503,api("POST","/consumer/auth/phone/request-code",Map.of("phone_e164","+8613800000001","purpose","LOGIN"),null,Map.of()).status());assertEquals(0,count("otp_challenge"));assertEquals(0,count("outbox_event"));assertEquals(0,provider.calls.get());}
        finally {db.execute("DROP TRIGGER test_otp_rollback ON audit_event");db.execute("DROP FUNCTION test_otp_rollback()");}
    }
    @Test void inboxCommitFailureRollsBackBusinessAndRealBrokerRedelivers() throws Exception {
        event(1);publisher.publishOne();db.execute("CREATE FUNCTION test_inbox_rollback() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status='PROCESSED' THEN RAISE EXCEPTION 'TEST inbox rollback'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER test_inbox_rollback BEFORE UPDATE ON processed_event FOR EACH ROW EXECUTE FUNCTION test_inbox_rollback()");
        try {receive();assertEquals(0,count("processed_event"));assertEquals(0,count("sms_delivery"));assertEquals(0,provider.calls.get());}
        finally {db.execute("DROP TRIGGER test_inbox_rollback ON processed_event");db.execute("DROP FUNCTION test_inbox_rollback()");}
        receive();sms.sendOne();assertEquals(1,count("processed_event"));assertEquals(1,provider.deliveries.size());
    }
    @Test void missingReplayGenerationIsRejectedAndBackoffIsCapped() throws Exception {
        UUID id=event(1);String token=login();assertEquals(400,api("POST","/admin/operations/outbox/"+id+"/replay",Map.of("reason_code","TEST_MISSING_VERSION"),token,Map.of()).status());
        assertEquals(50,policy.backoff(1));assertEquals(100,policy.backoff(2));assertEquals(200,policy.backoff(3));assertEquals(200,policy.backoff(20));
        var claim=repo.claim("BACKOFF").orElseThrow();repo.failed(claim,"TEST_FAILURE");var row=db.queryForMap("SELECT last_error_at,available_at FROM outbox_event WHERE id=?",id);assertTrue(Duration.between(((Timestamp)row.get("last_error_at")).toInstant(),((Timestamp)row.get("available_at")).toInstant()).toMillis()>=48);
    }
    @Test void expiredSendMaterialIsRemovedEvenWhenEventRemainsDead(){UUID id=event(1);db.update("UPDATE outbox_event SET status='DEAD',dead_at=clock_timestamp() WHERE id=?",id);clock.time=clock.time.plusSeconds(601);assertEquals(1,sms.expireSecrets());assertNull(db.queryForObject("SELECT delivery_secret_ciphertext FROM otp_challenge",String.class));assertEquals("DEAD",state(id));}
    @Test void actualSpringWorkersAndListenerRunOtpPipelineWithoutManualPump() throws Exception {
        // A separate application instance uses the production scheduling/listener defaults.
        try(var live=new org.springframework.boot.builder.SpringApplicationBuilder(PawdayApplication.class,FixtureBeans.class).run(
            "--server.port=0","--spring.datasource.url="+PG.getJdbcUrl("postgres","postgres"),"--spring.datasource.username=postgres","--spring.datasource.password=postgres",
            "--pawday.auth.secret-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","--spring.rabbitmq.host="+HOST,"--spring.rabbitmq.port="+PORT,"--spring.rabbitmq.username="+USER,"--spring.rabbitmq.password="+PASSWORD,
            "--management.health.redis.enabled=false","--pawday.search.enabled=false","--pawday.outbox.workers-enabled=true","--pawday.outbox.consumer-enabled=true","--pawday.outbox.poll-ms=50")) {
            int livePort=((org.springframework.boot.web.server.servlet.context.ServletWebServerApplicationContext)live).getWebServer().getPort();
            var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+livePort+"/api/v1/consumer/auth/phone/request-code")).header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(Map.of("phone_e164","+8613800000002","purpose","LOGIN")))).build(),HttpResponse.BodyHandlers.ofString());
            assertEquals(200,response.statusCode());UUID challenge=UUID.fromString(json.readTree(response.body()).get("data").get("id").asString());var liveProvider=live.getBean(Provider.class);
            await().atMost(Duration.ofSeconds(10)).until(()->liveProvider.deliveries.containsKey(challenge.toString())
                && db.queryForObject("SELECT count(*) FROM sms_delivery WHERE id=? AND status='DELIVERED'",Integer.class,challenge)==1
                && db.queryForObject("SELECT count(*) FROM outbox_event WHERE aggregate_id=? AND status='PUBLISHED'",Integer.class,challenge.toString())==1);
            assertEquals("PUBLISHED",db.queryForObject("SELECT status FROM outbox_event WHERE aggregate_id=?",String.class,challenge.toString()));assertEquals("PROCESSED",db.queryForObject("SELECT status FROM processed_event",String.class));
            assertEquals("DELIVERED",db.queryForObject("SELECT status FROM sms_delivery",String.class));assertEquals(1,liveProvider.calls.get());assertEquals(0,provider.calls.get());
        }
    }
}
