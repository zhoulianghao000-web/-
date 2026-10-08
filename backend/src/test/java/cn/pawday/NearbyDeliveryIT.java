package cn.pawday;
import cn.pawday.identity.*;
import cn.pawday.outbox.*;
import java.util.concurrent.TimeUnit;
import com.rabbitmq.client.*;
import static org.awaitility.Awaitility.await;
import org.springframework.amqp.rabbit.core.RabbitAdmin;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.*;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
class NearbyDeliveryIT {
 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.rabbitmq.host",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_HOST","127.0.0.1"));r.add("spring.rabbitmq.port",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PORT","5672"));r.add("spring.rabbitmq.username",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_USER","pawday_it"));r.add("spring.rabbitmq.password",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PASSWORD","TEST_ONLY_m22_broker"));r.add("pawday.outbox.confirm-timeout-ms",()->500);r.add("pawday.outbox.retry-base-ms",()->50);r.add("pawday.outbox.retry-max-ms",()->200);r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);r.add("pawday.membership.worker-enabled",()->false);}
 @Autowired JdbcTemplate db;@Autowired Crypto crypto;@LocalServerPort int port;
 final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new java.util.concurrent.CopyOnWriteArrayList<>();
 String admin,merchant;UUID adminSession,store,merchantId;
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}}
 String key(){return UUID.randomUUID().toString();}
 String identity(String realm,UUID m,List<String> permissions){UUID principal=UUID.randomUUID(),role=UUID.randomUUID();
  if(realm.equals("CONSUMER")){UUID user=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",user);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",principal,user);}
  else db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,?,?,?,?,?)",principal,realm,m,key(),"TEST-ONLY",realm.equals("ADMIN")?crypto.encrypt(new byte[20]):null);
  db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,'Nearby test')",role,realm,key());for(String permission:permissions)db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code=?",role,permission);db.update("INSERT INTO principal_role VALUES (?,?,?)",principal,role,realm);
  UUID session=UUID.randomUUID();String token=crypto.token();Instant now=Instant.now();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'M54-IT',?,?,?)",session,principal,crypto.hash(token),Timestamp.from(now.plusSeconds(86400)),Timestamp.from(now.plusSeconds(86400)),Timestamp.from(now));if(realm.equals("ADMIN"))adminSession=session;if(realm.equals("MERCHANT"))db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",principal,m,store);return token;
 }
 @BeforeEach void setup(){merchantId=UUID.randomUUID();store=UUID.randomUUID();db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE')",merchantId,key());db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST Nearby & Store')",store,merchantId);admin=identity("ADMIN",null,List.of("nearby.read","nearby.moderate"));merchant=identity("MERCHANT",merchantId,List.of("store.read","store.nearby.write"));}
 Response req(String method,String path,Object payload,String token,Map<String,String> headers){try{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path));if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));var result=http.send(b.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(result.body());SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",result.statusCode(),"response",body));return new Response(result.statusCode(),body);}catch(Exception e){throw new AssertionError(e);}}
 Response read(String path,String token){return req("GET",path,null,token,Map.of());}
 Map<String,Object> input(){return new LinkedHashMap<>(Map.of("city","TEST-CITY-"+store,"category","PET_STORE","address","TEST street","phone","13800000000","business_hours","09:00–18:00","longitude",121.5,"latitude",31.2,"coordinate_system","WGS84","services",List.of("SUPPLIES","PET_FRIENDLY")));}
 Response save(Map<String,Object>b,long version,String key){return req("PUT","/merchant/stores/"+store+"/nearby-profile",b,merchant,Map.of("If-Match","\""+version+"\"","Idempotency-Key",key));}
 String proof(){String p=crypto.token();Instant now=Instant.now();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(p),adminSession,"nearby.moderate",Timestamp.from(now.plusSeconds(300)),Timestamp.from(now));return p;}
 Map<String,Object> decision(String status){return Map.of("publication_status",status,"claim_status","VERIFIED","pawday_certified",true,"reason","TEST reviewed ownership and source evidence");}
 Response moderate(String status,long version){return req("POST","/admin/nearby/stores/"+store+"/moderation",decision(status),admin,Map.of("If-Match","\""+version+"\"","Idempotency-Key",key(),"X-Reverify-Token",proof()));}
 void published(){assertEquals(200,save(input(),0,key()).status());assertEquals(200,moderate("PUBLISHED",1).status());}
 String nearby(){return "/public/nearby/places?city=TEST-CITY-"+store;}
 Response nav(String token){return req("POST",token==null?"/public/nearby/navigation-intents":"/consumer/nearby/navigation-intents",Map.of("place_id",store.toString(),"mode","DESTINATION"),token,Map.of());}

 @Autowired OutboxPublisher publisher;@Autowired RabbitAdmin rabbitAdmin;@Autowired CachingConnectionFactory springConnection;
 Connection connection;Channel channel;
 @BeforeEach void brokerSetup()throws Exception{connect();rabbitAdmin.initialize();channel.queuePurge("pawday.business.facts");}
 void connect()throws Exception{var f=new ConnectionFactory();f.setHost(System.getenv().getOrDefault("PAWDAY_IT_RABBIT_HOST","127.0.0.1"));f.setPort(Integer.parseInt(System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PORT","5672")));f.setUsername(System.getenv().getOrDefault("PAWDAY_IT_RABBIT_USER","pawday_it"));f.setPassword(System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PASSWORD","TEST_ONLY_m22_broker"));f.setConnectionTimeout(3000);connection=f.newConnection();channel=connection.createChannel();}
 @AfterEach void closeBroker()throws Exception{if(channel!=null&&channel.isOpen())channel.close();if(connection!=null&&connection.isOpen())connection.close();}
 UUID event(){return db.queryForObject("SELECT id FROM outbox_event WHERE aggregate_id=? AND event_type='NearbyStoreChanged'",UUID.class,store.toString());}
 String state(UUID id){return db.queryForObject("SELECT status FROM outbox_event WHERE id=?",String.class,id);}
 @Test void realConfirmPublishesDurableStoreFactWithoutLocationHistory()throws Exception{assertEquals(200,save(input(),0,key()).status());UUID id=event();publisher.publishOne();assertEquals("PUBLISHED",state(id));var received=channel.basicGet("pawday.business.facts",false);assertNotNull(received);var e=json.readValue(received.getBody(),EventEnvelope.class);assertEquals(id,e.event_id());assertEquals(Set.of("store_id","version"),e.payload().keySet());channel.basicAck(received.getEnvelope().getDeliveryTag(),false);publisher.publishOne();assertNull(channel.basicGet("pawday.business.facts",true));assertEquals(1,read("/merchant/stores/"+store+"/nearby-profile",merchant).data().get("version").asLong());}
 @Test void stoppedBrokerDoesNotRollbackProfileAndRecoveryPublishes()throws Exception{UUID id;brokerControl("stop_app");try{springConnection.resetConnection();channel=null;connection.abort();connection=null;assertEquals(200,save(input(),0,key()).status());id=event();publisher.publishOne();assertEquals("FAILED_RETRYABLE",state(id));assertEquals(200,read("/merchant/stores/"+store+"/nearby-profile",merchant).status());assertEquals(0,read(nearby(),null).data().size());}finally{brokerControl("start_app");springConnection.resetConnection();}connect();rabbitAdmin.initialize();await().atMost(Duration.ofSeconds(12)).until(()->{publisher.publishOne();return state(id).equals("PUBLISHED");});var received=channel.basicGet("pawday.business.facts",false);assertNotNull(received);assertEquals(id,json.readValue(received.getBody(),EventEnvelope.class).event_id());channel.basicAck(received.getEnvelope().getDeliveryTag(),false);assertEquals(1,read("/merchant/stores/"+store+"/nearby-profile",merchant).data().get("version").asLong());}
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

 @AfterAll static void evidence()throws Exception{Files.createDirectories(Path.of("target"));Files.writeString(Path.of("target/m54-delivery-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
}
