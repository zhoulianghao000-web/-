package cn.pawday;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.awaitility.Awaitility.await;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT)
class RedisInfrastructureIT {
    static final EmbeddedPostgres PG;static final TcpAvailabilityProxy PROXY;
    static final String REDIS_HOST=System.getenv().getOrDefault("PAWDAY_IT_REDIS_HOST","127.0.0.1");
    static final int REDIS_PORT=Integer.parseInt(System.getenv().getOrDefault("PAWDAY_IT_REDIS_PORT","6379"));
    static {try{PG=EmbeddedPostgres.builder().setPort(0).start();PROXY=new TcpAvailabilityProxy(REDIS_HOST,REDIS_PORT);}catch(Exception e){throw new ExceptionInInitializerError(e);}}
    @DynamicPropertySource static void config(DynamicPropertyRegistry r){
        r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");
        r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");
        r.add("spring.data.redis.host",()->"127.0.0.1");r.add("spring.data.redis.port",PROXY::port);r.add("spring.data.redis.connect-timeout",()->"500ms");r.add("spring.data.redis.timeout",()->"500ms");
        r.add("spring.rabbitmq.host",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_HOST","127.0.0.1"));r.add("spring.rabbitmq.port",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PORT","5672"));r.add("spring.rabbitmq.username",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_USER","pawday_it"));r.add("spring.rabbitmq.password",()->System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PASSWORD","TEST_ONLY_m22_broker"));
        r.add("pawday.search.url",()->System.getenv().getOrDefault("PAWDAY_IT_OPENSEARCH_URL","http://127.0.0.1:9200"));
        r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.consumers-enabled",()->false);r.add("pawday.search.workers-enabled",()->false);
        r.add("management.endpoint.health.show-details",()->"always");
    }
    @LocalServerPort int port;@Autowired StringRedisTemplate redis;
    final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();final JsonMapper json=JsonMapper.builder().build();
    static final List<Map<String,Object>> EVIDENCE=new CopyOnWriteArrayList<>();
    @BeforeEach void restore(){PROXY.recover();await().atMost(Duration.ofSeconds(10)).ignoreExceptions().until(()->"PONG".equals(redis.execute((org.springframework.data.redis.core.RedisCallback<String>)c->c.ping())));}
    @AfterEach void cleanup(){PROXY.recover();}
    @AfterAll static void done() throws Exception {Files.writeString(Path.of("target/m23-infrastructure-evidence.json"),JsonMapper.builder().build().writeValueAsString(EVIDENCE));PROXY.close();PG.close();}
    @Test void realRedisPingRoundtripAndTtl(){
        String key="pawday:m23-it:"+UUID.randomUUID();redis.opsForValue().set(key,"real-redis-value",Duration.ofSeconds(1));assertEquals("real-redis-value",redis.opsForValue().get(key));
        Long ttl=redis.getExpire(key);assertNotNull(ttl);assertTrue(ttl>=0 && ttl<=1);await().atMost(Duration.ofSeconds(4)).until(()->redis.opsForValue().get(key)==null);
        EVIDENCE.add(Map.of("case","redis-ttl","result","PASS","real_endpoint",REDIS_HOST+":"+REDIS_PORT));
    }
    @Test void realRedisUnavailableHealthDownThenRecovers() throws Exception {
        PROXY.unavailable();assertThrows(org.springframework.dao.DataAccessException.class,()->redis.opsForValue().get("pawday:m23-it:unavailable"));
        var down=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/actuator/health/redis")).timeout(Duration.ofSeconds(5)).GET().build(),HttpResponse.BodyHandlers.ofString());assertEquals(503,down.statusCode());assertEquals("DOWN",json.readTree(down.body()).get("status").asString());
        PROXY.recover();await().atMost(Duration.ofSeconds(10)).ignoreExceptions().until(()->"PONG".equals(redis.execute((org.springframework.data.redis.core.RedisCallback<String>)c->c.ping())));
        var up=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/actuator/health/redis")).timeout(Duration.ofSeconds(5)).GET().build(),HttpResponse.BodyHandlers.ofString());assertEquals(200,up.statusCode());assertEquals("UP",json.readTree(up.body()).get("status").asString());
        EVIDENCE.add(Map.of("case","redis-real-network-outage-recovery","down_http_status",down.statusCode(),"up_http_status",up.statusCode()));
    }
    @Test void completeFourServiceDevelopmentEnvironmentIsActuallyHealthy() throws Exception {
        var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/actuator/health")).timeout(Duration.ofSeconds(15)).GET().build(),HttpResponse.BodyHandlers.ofString());
        var body=json.readTree(response.body());assertEquals(200,response.statusCode(),response.body());assertEquals("UP",body.get("status").asString());
        var components=body.get("components");for(String expected:List.of("db","rabbit","redis","search"))assertEquals("UP",components.get(expected).get("status").asString(),expected);
        EVIDENCE.add(Map.of("case","all-four-real-services-health","response",body));
    }
}
