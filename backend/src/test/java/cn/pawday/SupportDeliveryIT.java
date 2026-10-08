package cn.pawday;
import cn.pawday.identity.*;
import cn.pawday.outbox.*;
import com.rabbitmq.client.*;
import static org.awaitility.Awaitility.await;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.amqp.rabbit.core.*;
import org.springframework.amqp.core.Message;
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
class SupportDeliveryIT {
 static final String HOST=System.getenv().getOrDefault("PAWDAY_IT_RABBIT_HOST","127.0.0.1"),USER=System.getenv().getOrDefault("PAWDAY_IT_RABBIT_USER","pawday_it"),PASSWORD=System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PASSWORD","TEST_ONLY_m22_broker");
 static final int PORT=Integer.parseInt(System.getenv().getOrDefault("PAWDAY_IT_RABBIT_PORT","5672"));
 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.rabbitmq.host",()->HOST);r.add("spring.rabbitmq.port",()->PORT);r.add("spring.rabbitmq.username",()->USER);r.add("spring.rabbitmq.password",()->PASSWORD);r.add("pawday.outbox.max-attempts",()->3);r.add("pawday.outbox.retry-base-ms",()->50);r.add("pawday.outbox.retry-max-ms",()->200);r.add("pawday.outbox.confirm-timeout-ms",()->500);r.add("pawday.outbox.lease-ms",()->2000);r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("pawday.storage.local-root",()->System.getProperty("java.io.tmpdir")+"/pawday-m53-delivery-"+PG.getPort());r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.simulation-enabled",()->true);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);r.add("pawday.membership.worker-enabled",()->false);}
 @Autowired JdbcTemplate db;@Autowired Crypto crypto;@Autowired MutableClock clock;@LocalServerPort int port;
 @Autowired cn.pawday.membership.MembershipService memberships;
 static class MutableClock extends Clock {
  volatile Instant current=Instant.parse("2026-10-07T00:00:00Z");
  void advance(long seconds){current=current.plusSeconds(seconds);}
  @Override public ZoneId getZone(){return ZoneOffset.UTC;}
  @Override public Clock withZone(ZoneId zone){return this;}
  @Override public Instant instant(){return current;}
 }
 @org.springframework.boot.test.context.TestConfiguration static class FixtureBeans {
  @org.springframework.context.annotation.Bean @org.springframework.context.annotation.Primary MutableClock testClock(){return new MutableClock();}
 }
 final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new java.util.concurrent.CopyOnWriteArrayList<>();
 String admin,merchant;UUID adminSession,adminPrincipal,merchantId,store;String sku;
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}String id(){return data().get("id").asString();}}

 boolean multi;
 String key(){return UUID.randomUUID().toString();}
 String identity(String realm,UUID m,List<String> permissions){UUID p=UUID.randomUUID(),role=UUID.randomUUID();if(realm.equals("CONSUMER")){UUID u=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",u);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",p,u);}else db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,?,?,?,?,?)",p,realm,m,key(),"TEST-ONLY",realm.equals("ADMIN")?crypto.encrypt(new byte[20]):null);
  db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,'Membership test')",role,realm,key());for(String permission:permissions)db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code=?",role,permission);db.update("INSERT INTO principal_role VALUES (?,?,?)",p,role,realm);UUID session=UUID.randomUUID();String t=crypto.token();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'M51-IT',?,?,?)",session,p,crypto.hash(t),Timestamp.from(clock.instant().plusSeconds(86400*40)),Timestamp.from(clock.instant().plusSeconds(86400*40)),Timestamp.from(clock.instant()));if(realm.equals("ADMIN")){adminSession=session;adminPrincipal=p;}if(realm.equals("MERCHANT"))db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",p,m,store);return t;
 }
 @BeforeEach void setup(){multi=false;merchantId=UUID.randomUUID();store=UUID.randomUUID();db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE')",merchantId,key());db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST scope')",store,merchantId);
  admin=identity("ADMIN",null,List.of("offer.admin.manage","order.admin.read","payment.read","membership.plan.manage","points.policy.manage","points.reward.manage","points.adjust","points.read","review.read","review.moderate","review.policy.manage","content.read","content.write","content.moderate","aftersale.arbitrate","support.read","support.reply","support.assign","outbox.replay"));merchant=identity("MERCHANT",merchantId,List.of("offer.read","offer.write","inventory.adjust","order.read","order.default-scope","order.ship","aftersale.handle","review.merchant.read","support.read","support.reply","support.assign"));
  UUID brand=UUID.randomUUID(),spu=UUID.randomUUID(),k=UUID.randomUUID();sku=k.toString();db.update("INSERT INTO brands(id,name,source_ref) VALUES (?,?,'TEST-ONLY')",brand,key());db.update("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES (?,?,'TEST-ONLY','CAT','DRY_FOOD')",spu,brand);db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES (?,?,?,1000,'BAG')",k,spu,key());db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) VALUES (?,?,1,'PUBLISHED','[\"TEST-ONLY\"]','[]',false,'[]','[\"TEST-ONLY source\"]','2026-10-01',?,clock_timestamp())",UUID.randomUUID(),k,adminPrincipal);
 }
 Response req(String method,String path,Object payload,String token,Map<String,String> headers){try{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));var response=http.send(b.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",body));return new Response(response.statusCode(),body);}catch(Exception e){throw new AssertionError(e);}}
 Response read(String path,String token){return req("GET",path,null,token,Map.of());}
 String consumer(){return identity("CONSUMER",null,List.of());}
 String proof(String action){String p=crypto.token();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(p),adminSession,action,Timestamp.from(clock.instant().plusSeconds(300)),Timestamp.from(clock.instant()));return p;}
 @BeforeEach void reviewPolicyFixture(){int v=db.queryForObject("SELECT coalesce(max(policy_version),0)+1 FROM review_reward_policies",Integer.class);db.update("INSERT INTO review_reward_policies(id,policy_version,base_points,media_bonus_points,refund_strategy) VALUES (?,?,10,5,'PROPORTIONAL_GOODS')",UUID.randomUUID(),v);}
 String userIdOf(String token){return read("/consumer/me",token).data().get("user_id").asString();}

 record GoodsFixture(String payment,String subId,String itemId,long payable){}
 GoodsFixture paidGoods(String u,int qty){return paidGoods(u,qty,1000,List.of());}
 GoodsFixture paidGoods(String u,int qty,long price,List<String> coupons){return paidGoods(u,qty,price,coupons,()->{},200);}
 GoodsFixture paidGoods(String u,int qty,long price,List<String> coupons,Runnable beforeConfirm,int expectedStatus){
  var offer=req("POST","/merchant/offers",new LinkedHashMap<String,Object>(Map.of("sku_id",sku,"sale_price_fen",price,"member_price_fen",Math.min(price,900),"fulfillment_sla","TEST-ONLY 48h")){{put("store_id",store.toString());}},merchant,Map.of("Idempotency-Key",key()));assertEquals(201,offer.status(),offer.body().toString());
  assertEquals(201,req("POST","/merchant/offers/"+offer.id()+"/inventory-adjustments",Map.of("delta_qty",20,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());
  assertEquals(200,req("POST","/merchant/offers/"+offer.id()+"/activate",Map.of("reason","TEST-ONLY lifecycle"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());
  int v=db.queryForObject("SELECT coalesce(max(version_no),0)+1 FROM shipping_rule_versions WHERE merchant_id=?",Integer.class,merchantId);
  db.update("INSERT INTO shipping_rule_versions(id,merchant_id,version_no,province_codes,base_fen,per_kg_fen,free_threshold_fen,created_by) VALUES (?,?,?,'[\"310000\"]',300,100,NULL,?)",UUID.randomUUID(),merchantId,v,adminPrincipal);
  var cart=req("POST","/consumer/cart/items",Map.of("offer_id",offer.id(),"quantity",qty),u,Map.of("Idempotency-Key",key()));
  var address=req("POST","/consumer/addresses",Map.of("recipient","TEST recipient","phone","13800000000","province_code","310000","city_code","310100","district_code","310101","detail","TEST-only address"),u,Map.of("Idempotency-Key",key()));
  var quote=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",multi?List.of(cart.id(),secondCart(u,price,qty)):List.of(cart.id()),"address_id",address.id(),"coupon_ids",coupons,"use_membership",false),u,Map.of("Idempotency-Key",key()));assertEquals(200,quote.status(),quote.body().toString());
  var order=req("POST","/consumer/orders",Map.of("quote_id",quote.data().get("quote_id").asString()),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());
  String payment=order.data().get("payment").get("id").asString();
  var attempt=req("POST","/consumer/payments/"+payment+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));
  beforeConfirm.run();assertEquals(expectedStatus,req("POST","/consumer/payments/"+payment+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());
  return new GoodsFixture(payment,order.data().get("suborders").get(0).get("id").asString(),order.data().get("suborders").get(0).get("items").get(0).get("id").asString(),order.data().get("payable_amount_fen").asLong());
 }

 String secondCart(String u,long price,int qty){
  UUID second=UUID.randomUUID();db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) SELECT ?,spu_id,?,weight_g,package_unit FROM skus WHERE id=?",second,key(),UUID.fromString(sku));
  db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) SELECT ?,?,1,'PUBLISHED',ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,clock_timestamp() FROM sku_standard_versions WHERE sku_id=? AND status='PUBLISHED'",UUID.randomUUID(),second,UUID.fromString(sku));
  var body=new LinkedHashMap<String,Object>(Map.of("sku_id",second.toString(),"sale_price_fen",price,"member_price_fen",Math.min(price,900),"fulfillment_sla","TEST-ONLY"));body.put("store_id",store.toString());
  var offer=req("POST","/merchant/offers",body,merchant,Map.of("Idempotency-Key",key()));assertEquals(201,offer.status(),offer.body().toString());
  assertEquals(201,req("POST","/merchant/offers/"+offer.id()+"/inventory-adjustments",Map.of("delta_qty",20,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());
  assertEquals(200,req("POST","/merchant/offers/"+offer.id()+"/activate",Map.of("reason","TEST-ONLY"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());
  var cart=req("POST","/consumer/cart/items",Map.of("offer_id",offer.id(),"quantity",qty),u,Map.of("Idempotency-Key",key()));assertEquals(200,cart.status(),cart.body().toString());return cart.id();
 }
 void receiveAll(String u,GoodsFixture f){
  var items=db.queryForList("SELECT id,quantity FROM order_items WHERE suborder_id=? ORDER BY id",UUID.fromString(f.subId())).stream().map(row->Map.of("order_item_id",row.get("id").toString(),"quantity",row.get("quantity"))).toList();
  long v=read("/consumer/suborders/"+f.subId()+"/fulfillment",u).data().get("version").asLong();
  var shipped=req("POST","/merchant/suborders/"+f.subId()+"/shipments",Map.of("carrier_code","SF","tracking_no","TEST"+key().replace("-",""),"items",items),merchant,Map.of("Idempotency-Key",key(),"If-Match","\""+v+"\""));assertEquals(200,shipped.status(),shipped.body().toString());
  var shipments=shipped.data().get("shipments");String ship=shipments.get(shipments.size()-1).get("id").asString();
  var received=req("POST","/consumer/suborders/"+f.subId()+"/confirm-receipt",Map.of("shipment_ids",List.of(ship)),u,Map.of("Idempotency-Key",key(),"If-Match","\""+shipped.data().get("version").asLong()+"\""));assertEquals(200,received.status(),received.body().toString());
 }
 Map<String,Object> reviewBody(List<String>assets,String pet,boolean share){var b=new LinkedHashMap<String,Object>();b.put("rating",4);b.put("service_rating",5);b.put("body","TEST-ONLY received goods review");b.put("asset_ids",assets);b.put("pet_id",pet);b.put("share_pet_label",share);return b;}
 Map<String,Object> articleBody(List<String>assets,List<String>skus){return Map.of("title","TEST-ONLY knowledge","category","FOOD_KNOWLEDGE","body","<script>plain text, no execution</script>","source_refs",List.of("TEST-ONLY source"),"sponsored",true,"asset_ids",assets,"sku_ids",skus);}
 Response submitReview(String u,String item,Map<String,Object>b){return req("POST","/consumer/order-items/"+item+"/reviews",b,u,Map.of("Idempotency-Key",key()));}
 Response approveReview(Response review){var r=req("POST","/admin/reviews/"+review.id()+"/moderation",Map.of("decision","APPROVE","reason","TEST-ONLY checked"),admin,Map.of("Idempotency-Key",key(),"If-Match","\""+review.data().get("version").asLong()+"\"","X-Reverify-Token",proof("review.moderate")));assertEquals(200,r.status(),r.body().toString());return r;}
 Response editReview(String u,Response review,Map<String,Object>b){return req("PATCH","/consumer/reviews/"+review.id(),b,u,Map.of("Idempotency-Key",key(),"If-Match","\""+review.data().get("version").asLong()+"\""));}
 Response createArticle(Map<String,Object>b){var r=req("POST","/admin/content",b,admin,Map.of("Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());return r;}
 Response submitArticle(Response article){var r=req("POST","/admin/content/"+article.id()+"/submit",Map.of(),admin,Map.of("Idempotency-Key",key(),"If-Match","\""+article.data().get("version").asLong()+"\""));assertEquals(200,r.status(),r.body().toString());return r;}
 Response moderateArticle(Response article,String decision){return req("POST","/admin/content/"+article.id()+"/moderation",Map.of("decision",decision,"reason","TEST-ONLY explicit decision"),admin,Map.of("Idempotency-Key",key(),"If-Match","\""+article.data().get("version").asLong()+"\"","X-Reverify-Token",proof("content.moderate")));}
 byte[] png(){try{var image=new java.awt.image.BufferedImage(2,2,java.awt.image.BufferedImage.TYPE_INT_RGB);var out=new java.io.ByteArrayOutputStream();javax.imageio.ImageIO.write(image,"png",out);return out.toByteArray();}catch(Exception e){throw new AssertionError(e);}}
 byte[] video(){try(var in=getClass().getResourceAsStream("/review-video.base64")){return Base64.getDecoder().decode(new String(in.readAllBytes(),java.nio.charset.StandardCharsets.US_ASCII).strip());}catch(Exception e){throw new AssertionError(e);}}
 String upload(String who,String scope,String mime,byte[] bytes){try{
  String hash=HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes));
  var grant=req("POST","/media/upload-grants",Map.of("scope",scope,"mime",mime,"size_bytes",bytes.length,"sha256",hash),who,Map.of());assertEquals(201,grant.status(),grant.body().toString());String id=grant.data().get("asset_id").asString();
  var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1/media/"+id+"/content")).header("Authorization","Bearer "+who).header("Content-Type",mime).header("X-Upload-Token",grant.data().get("upload_token").asString()).PUT(HttpRequest.BodyPublishers.ofByteArray(bytes)).build();
  var response=http.send(request,HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());SAMPLES.add(Map.of("method","put","path","/media/"+id+"/content","status",response.statusCode(),"response",body));assertEquals(200,response.statusCode(),response.body());return id;
 }catch(Exception e){throw new AssertionError(e);}}
 static final List<Map<String,Object>> BINARY=new java.util.concurrent.CopyOnWriteArrayList<>();
 int binary(String path,String who,byte[] expected){try{var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path));if(who!=null)request.header("Authorization","Bearer "+who);var r=http.send(request.GET().build(),HttpResponse.BodyHandlers.ofByteArray());if(r.statusCode()==200){assertArrayEquals(expected,r.body());assertEquals("nosniff",r.headers().firstValue("X-Content-Type-Options").orElseThrow());assertTrue(r.headers().firstValue("Cache-Control").orElseThrow().contains("no-store"));BINARY.add(Map.of("path",path,"status",r.statusCode(),"content_type",r.headers().firstValue("Content-Type").orElseThrow(),"bytes",r.body().length));}else{SAMPLES.add(Map.of("method","get","path",path,"status",r.statusCode(),"response",json.readTree(new String(r.body(),java.nio.charset.StandardCharsets.UTF_8))));}return r.statusCode();}catch(Exception e){throw new AssertionError(e);}}
 long reviewEarn(String u){return db.queryForObject("SELECT coalesce(sum(points),0) FROM points_ledger WHERE user_id=? AND entry_type IN ('REVIEW_EARN','MEDIA_REVIEW_BONUS','REVIEW_CLAWBACK')",Long.class,UUID.fromString(userIdOf(u)));}
 Response aftersale(String u,GoodsFixture f,int quantity){var a=req("POST","/consumer/suborders/"+f.subId()+"/aftersales",Map.of("type","REFUND_ONLY","reason_code","QUALITY_ISSUE","reason_text","TEST-ONLY", "items",List.of(Map.of("order_item_id",f.itemId(),"quantity",quantity)),"evidence",List.of()),u,Map.of("Idempotency-Key",key()));assertEquals(200,a.status(),a.body().toString());return a;}
 Response refund(String u,GoodsFixture f,int quantity){var a=aftersale(u,f,quantity);var r=req("POST","/merchant/aftersales/"+a.id()+"/decide",Map.of("action","APPROVE_REFUND","reason","TEST-ONLY"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\""+a.data().get("version").asLong()+"\""));assertEquals(200,r.status(),r.body().toString());return r;}

 String match(Response r){return "\""+r.data().get("version").asLong()+"\"";}

 @Autowired cn.pawday.support.SupportInboxConsumer inbox;
 String principalOf(String token){return db.queryForObject("SELECT p.id::text FROM identity_principal p JOIN auth_session s ON s.principal_id=p.id WHERE s.access_token_hash=?",String.class,crypto.hash(token));}
 String proofFor(String token,String action){String proof=crypto.token();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) SELECT ?,id,?,?,? FROM auth_session WHERE access_token_hash=?",crypto.hash(proof),action,Timestamp.from(clock.instant().plusSeconds(300)),Timestamp.from(clock.instant()),crypto.hash(token));return proof;}
 Response conversation(String u,boolean platform){var body=new LinkedHashMap<String,Object>();body.put("kind",platform?"PLATFORM":"MERCHANT");body.put("store_id",platform?null:store.toString());var r=req("POST","/consumer/conversations",body,u,Map.of("Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());return r;}
 Response assign(Response c,String who,String target){String realm=who.equals(merchant)?"merchant":"admin";var r=req("POST","/"+realm+"/conversations/"+c.id()+"/assignment",Map.of("principal_id",principalOf(target),"reason","TEST ONLY assignment"),who,Map.of("Idempotency-Key",key(),"If-Match",match(c),"X-Reverify-Token",proofFor(who,"support.assign")));assertEquals(200,r.status(),r.body().toString());return r;}
 Map<String,Object> body(String type,String text,List<String>assets,String target){var b=new LinkedHashMap<String,Object>();b.put("type",type);b.put("body",text);b.put("asset_ids",assets);b.put("target_id",target);return b;}
 Response send(String realm,String who,String c,Map<String,Object>body,String k){return req("POST","/"+realm+"/conversations/"+c+"/messages",body,who,Map.of("Idempotency-Key",k));}
 cn.pawday.outbox.EventEnvelope event(String mid,int attempt){var row=db.queryForMap("SELECT * FROM outbox_event WHERE event_type='SupportMessageCreated' AND payload->>'message_id'=?",mid);return new cn.pawday.outbox.EventEnvelope((UUID)row.get("id"),"SupportMessageCreated",1,"CONVERSATION",row.get("aggregate_id").toString(),null,attempt,((Number)row.get("generation")).intValue(),json.readValue(row.get("payload").toString(),Map.class));}

 @Autowired OutboxPublisher publisher;@Autowired OutboxRepository outboxRepo;@Autowired RabbitPublisher rabbitPublisher;@Autowired DeliveryPolicy policy;@Autowired RabbitAdmin rabbitAdmin;@Autowired CachingConnectionFactory springConnection;@Autowired cn.pawday.support.SupportRabbitListener listener;
 Connection connection;Channel channel;
 @BeforeEach void brokerSetup()throws Exception{connect();rabbitAdmin.initialize();channel.queuePurge(RabbitTopology.SUPPORT_QUEUE);channel.queuePurge(RabbitTopology.DLQ);}
 void connect()throws Exception{var factory=new ConnectionFactory();factory.setHost(HOST);factory.setPort(PORT);factory.setUsername(USER);factory.setPassword(PASSWORD);factory.setConnectionTimeout(3000);connection=factory.newConnection();channel=connection.createChannel();}
 @AfterEach void closeBroker()throws Exception{if(channel!=null&&channel.isOpen())channel.close();if(connection!=null&&connection.isOpen())connection.close();}
 GetResponse next(String queue){var result=new AtomicReference<GetResponse>();await().atMost(Duration.ofSeconds(8)).pollInterval(Duration.ofMillis(20)).until(()->{result.set(channel.basicGet(queue,false));return result.get()!=null;});return result.get();}
 void receive(GetResponse d)throws Exception{var props=new org.springframework.amqp.core.MessageProperties();props.setMessageId(d.getProps().getMessageId());props.setDeliveryTag(d.getEnvelope().getDeliveryTag());listener.receive(new Message(d.getBody(),props),channel);}
 void pump()throws Exception{publisher.publishOne();var d=channel.basicGet(RabbitTopology.SUPPORT_QUEUE,false);if(d!=null)receive(d);}
 void flush()throws Exception{while(publisher.publishOne()){}while(true){var d=channel.basicGet(RabbitTopology.SUPPORT_QUEUE,false);if(d==null)break;receive(d);}}
 Response ready(String u)throws Exception{var c=assign(conversation(u,true),admin,admin);flush();return c;}
 String state(UUID e){return db.queryForObject("SELECT status FROM outbox_event WHERE id=?",String.class,e);}
 long effects(UUID event){return db.queryForObject("SELECT count(*) FROM notification_messages WHERE event_id=?",Long.class,event);}
 @Test void duplicateRealDeliveryProducesOnlyOneNotification()throws Exception{String u=consumer();var c=ready(u);var m=send("admin",admin,c.id(),body("TEXT","real duplicate",List.of(),null),key());var e=event(m.id(),1);var claim=outboxRepo.claim("M53 duplicate").orElseThrow();rabbitPublisher.publish(claim);outboxRepo.published(claim);receive(next(RabbitTopology.SUPPORT_QUEUE));rabbitPublisher.publish(claim);receive(next(RabbitTopology.SUPPORT_QUEUE));assertEquals(1,effects(e.event_id()));assertEquals(1,read("/consumer/conversations/"+c.id(),u).data().get("delivered_sequence").asLong());}
 @Test void commitBeforeAckCrashRedeliversWithoutDuplicatingNotification()throws Exception{String u=consumer();var c=ready(u);var m=send("admin",admin,c.id(),body("TEXT","commit then ack crash",List.of(),null),key());UUID e=event(m.id(),1).event_id();publisher.publishOne();var first=next(RabbitTopology.SUPPORT_QUEUE);inbox.process(json.readValue(first.getBody(),EventEnvelope.class));assertEquals(1,effects(e));channel.close();channel=connection.createChannel();var again=next(RabbitTopology.SUPPORT_QUEUE);assertTrue(again.getEnvelope().isRedeliver());receive(again);assertEquals(1,effects(e));}
 @Test void missingConfirmRetriesAgainstActualQueueAndDeduplicates()throws Exception{String u=consumer();var c=ready(u);var m=send("admin",admin,c.id(),body("TEXT","confirm lost",List.of(),null),key());UUID id=event(m.id(),1).event_id();var claim=outboxRepo.claim("M53 lost confirm").orElseThrow();try(var proxy=new ConfirmDroppingProxy(HOST,PORT)){var cf=new CachingConnectionFactory("127.0.0.1",proxy.port());cf.setUsername(USER);cf.setPassword(PASSWORD);cf.setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED);cf.setPublisherReturns(true);var template=new RabbitTemplate(cf);template.setMandatory(true);try{var failure=assertThrows(RabbitPublisher.PublishFailure.class,()->new RabbitPublisher(template,policy).publish(claim));assertEquals("CONFIRM_TIMEOUT",failure.code);assertTrue(proxy.discarded.get()>0);outboxRepo.failed(claim,failure.code);}finally{cf.destroy();}}receive(next(RabbitTopology.SUPPORT_QUEUE));await().dontCatchUncaughtExceptions().atMost(Duration.ofSeconds(8)).until(()->{publisher.publishOne();return state(id).equals("PUBLISHED");});receive(next(RabbitTopology.SUPPORT_QUEUE));assertEquals(1,effects(id));}
 @Test void twoPublishersClaimDistinctMessageFacts()throws Exception{String u=consumer();var c=ready(u);var ids=new HashSet<UUID>();for(int i=0;i<8;i++){var m=send("admin",admin,c.id(),body("TEXT","parallel "+i,List.of(),null),key());ids.add(event(m.id(),1).event_id());}var second=new OutboxPublisher(outboxRepo,rabbitPublisher);try(var pool=Executors.newFixedThreadPool(2)){var a=pool.submit(()->{while(publisher.publishOne()){};});var b=pool.submit(()->{while(second.publishOne()){};});a.get(15,TimeUnit.SECONDS);b.get(15,TimeUnit.SECONDS);}Set<String> seen=new HashSet<>();for(int i=0;i<8;i++){var d=next(RabbitTopology.SUPPORT_QUEUE);seen.add(d.getProps().getMessageId());receive(d);}assertEquals(8,seen.size());for(UUID id:ids){assertEquals("PUBLISHED",state(id));assertEquals(1,effects(id));}}
 @Test void poisonEnvelopeIsDeadLetteredDurablyWithoutCreatingBusinessResult()throws Exception{String u=consumer();ready(u);channel.confirmSelect();channel.basicPublish(RabbitTopology.EXCHANGE,"SupportMessageCreated",new AMQP.BasicProperties.Builder().messageId(UUID.randomUUID().toString()).deliveryMode(2).build(),"{INVALID JSON".getBytes(java.nio.charset.StandardCharsets.UTF_8));channel.waitForConfirmsOrDie(3000);receive(next(RabbitTopology.SUPPORT_QUEUE));publisher.publishOne();var d=next(RabbitTopology.DLQ);assertTrue(new String(d.getBody(),java.nio.charset.StandardCharsets.UTF_8).contains("INVALID_ENVELOPE"));channel.basicAck(d.getEnvelope().getDeliveryTag(),false);}
 @Test void consumerFailureRetriesDeadLettersThenControlledReplayRecovers()throws Exception{String u=consumer();var c=ready(u);var m=send("admin",admin,c.id(),body("TEXT","failure recovery",List.of(),null),key());UUID id=event(m.id(),1).event_id();db.execute("CREATE FUNCTION test_notification_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'TEST transient failure'; END $$");db.execute("CREATE TRIGGER test_notification_failure BEFORE INSERT ON notification_messages FOR EACH ROW EXECUTE FUNCTION test_notification_failure()");try{await().atMost(Duration.ofSeconds(10)).until(()->{pump();return db.queryForObject("SELECT count(*) FROM processed_event WHERE consumer='support-notifications-v1' AND event_id=? AND status='DEAD'",Integer.class,id)==1;});}finally{db.execute("DROP TRIGGER test_notification_failure ON notification_messages");db.execute("DROP FUNCTION test_notification_failure()");}assertEquals(0,effects(id));publisher.publishOne();var dead=next(RabbitTopology.DLQ);channel.basicAck(dead.getEnvelope().getDeliveryTag(),false);String path="/admin/operations/outbox/"+id+"/replay";var b=Map.of("expected_generation",0,"reason_code","TEST_SUPPORT_RESTORED");assertEquals(403,req("POST",path,b,admin,Map.of("Idempotency-Key",key())).status());String k=key(),proof=proofFor(admin,"outbox.replay");var headers=Map.of("Idempotency-Key",k,"X-Reverify-Token",proof);assertEquals(200,req("POST",path,b,admin,headers).status());assertEquals(200,req("POST",path,b,admin,headers).status());await().atMost(Duration.ofSeconds(8)).until(()->{pump();return effects(id)==1;});assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='outbox.replay' AND object_id=?",Integer.class,id.toString()));assertEquals(1,read("/consumer/messages",u).data().size());}
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

 @Test void stoppedBrokerStillAcceptsRealHttpMessageAndRestartRepairsDelivery()throws Exception{String u=consumer();var c=ready(u);UUID id;brokerControl("stop_app");try{springConnection.resetConnection();channel=null;connection.abort();connection=null;var m=send("admin",admin,c.id(),body("TEXT","broker offline saved",List.of(),null),key());assertEquals(200,m.status());id=event(m.id(),1).event_id();publisher.publishOne();assertEquals("FAILED_RETRYABLE",state(id));assertEquals(1,read("/consumer/conversations/"+c.id()+"/messages",u).data().size());assertEquals(0,effects(id));}finally{brokerControl("start_app");springConnection.resetConnection();}connect();rabbitAdmin.initialize();await().atMost(Duration.ofSeconds(12)).until(()->{pump();return state(id).equals("PUBLISHED")&&effects(id)==1;});}
 @Test void orderAndAfterSaleActualFactsReachIndependentInbox()throws Exception{String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var a=aftersale(u,f,1);flush();assertFalse(read("/consumer/messages?category=ORDER",u).data().isEmpty());var list=read("/consumer/messages?category=AFTERSALE",u);assertEquals(1,list.data().size());assertEquals(a.id(),list.data().get(0).get("target_id").asString());assertEquals(200,read("/consumer/messages/"+list.data().get(0).get("id").asString()+"/target",u).status());}
 @AfterAll static void evidence()throws Exception{Files.createDirectories(Path.of("target"));Files.writeString(Path.of("target/m53-delivery-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
}
