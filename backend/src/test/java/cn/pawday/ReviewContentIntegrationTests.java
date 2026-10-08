package cn.pawday;
import cn.pawday.identity.*;
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
class ReviewContentIntegrationTests {
 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("pawday.storage.local-root",()->System.getProperty("java.io.tmpdir")+"/pawday-m52-"+PG.getPort());r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.simulation-enabled",()->true);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);r.add("pawday.membership.worker-enabled",()->false);}
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
  admin=identity("ADMIN",null,List.of("offer.admin.manage","order.admin.read","payment.read","membership.plan.manage","points.policy.manage","points.reward.manage","points.adjust","points.read","review.read","review.moderate","review.policy.manage","content.read","content.write","content.moderate","aftersale.arbitrate"));merchant=identity("MERCHANT",merchantId,List.of("offer.read","offer.write","inventory.adjust","order.read","order.default-scope","order.ship","aftersale.handle","review.merchant.read"));
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
 @Test void onlyReceivedPurchasedItemsCanBeReviewed(){
  String u=consumer();var f=paidGoods(u,1);assertFalse(read("/consumer/order-items/"+f.itemId()+"/review-eligibility",u).data().get("eligible").asBoolean());
  assertEquals(409,submitReview(u,f.itemId(),reviewBody(List.of(),null,false)).status());
  assertEquals(404,submitReview(consumer(),f.itemId(),reviewBody(List.of(),null,false)).status());
  assertEquals(403,submitReview(merchant,f.itemId(),reviewBody(List.of(),null,false)).status());
  assertEquals(401,submitReview(null,f.itemId(),reviewBody(List.of(),null,false)).status());
  receiveAll(u,f);assertTrue(read("/consumer/order-items/"+f.itemId()+"/review-eligibility",u).data().get("eligible").asBoolean());
  var bad=reviewBody(List.of(),null,false);bad.put("verified_purchase",true);assertEquals(400,submitReview(u,f.itemId(),bad).status());
 }
 @Test void pendingReviewApprovalAndPublicPrivacy(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var r=submitReview(u,f.itemId(),reviewBody(List.of(),null,false));assertEquals(200,r.status(),r.body().toString());
  assertEquals(404,read("/public/reviews/"+r.id(),null).status());assertEquals(0,reviewEarn(u));
  assertEquals(403,req("POST","/admin/reviews/"+r.id()+"/moderation",Map.of("decision","APPROVE","reason","TEST"),admin,Map.of("Idempotency-Key",key(),"If-Match",match(r))).status());
  r=approveReview(r);assertEquals(10,reviewEarn(u));var pub=read("/public/reviews/"+r.id(),null);assertEquals(200,pub.status());assertTrue(pub.data().get("verified_purchase").asBoolean());assertTrue(pub.data().get("pet_label").isNull());
  for(String name:List.of("user_id","order_id","pet_id","merchant_id","store_id","moderation"))assertNull(pub.data().get(name));
  assertEquals(404,read("/consumer/reviews/"+r.id(),consumer()).status());
  String spu=r.data().get("spu_id").asString();assertEquals(200,read("/public/spus/"+spu+"/reviews",null).status());assertEquals(200,read("/consumer/spus/"+spu+"/reviews",u).status());
  assertEquals(200,read("/consumer/reviews/"+r.id(),u).status());assertEquals(200,read("/consumer/reviews",u).status());assertEquals(200,read("/admin/reviews",admin).status());assertEquals(200,read("/admin/reviews/"+r.id(),admin).status());
  assertEquals(1,read("/merchant/reviews?store_id="+store,merchant).body().get("data").size());assertEquals(400,read("/merchant/reviews",merchant).status());assertEquals(404,read("/merchant/reviews?store_id="+UUID.randomUUID(),merchant).status());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM review_moderation WHERE review_id=?",Integer.class,UUID.fromString(r.id())));
 }
 @Test void createIdempotencyAndDifferentPayloadConflict(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var b=reviewBody(List.of(),null,false);String k=key(),path="/consumer/order-items/"+f.itemId()+"/reviews";
  var first=req("POST",path,b,u,Map.of("Idempotency-Key",k));assertEquals(200,first.status());assertEquals(first.id(),req("POST",path,b,u,Map.of("Idempotency-Key",k)).id());
  b.put("body","changed");assertEquals(409,req("POST",path,b,u,Map.of("Idempotency-Key",k)).status());assertEquals(409,submitReview(u,f.itemId(),b).status());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM reviews WHERE order_item_id=?",Integer.class,UUID.fromString(f.itemId())));
 }
 @Test void concurrentCreateHasOneReviewFact()throws Exception{
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var start=new java.util.concurrent.CountDownLatch(1);
  try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){var a=pool.submit(()->{start.await();return submitReview(u,f.itemId(),reviewBody(List.of(),null,false));});var b=pool.submit(()->{start.await();return submitReview(u,f.itemId(),reviewBody(List.of(),null,false));});start.countDown();assertEquals(Set.of(200,409),Set.of(a.get().status(),b.get().status()));}
 }
 @Test void parentOrderAwardsBaseAndMediaOnlyOnceAcrossItems(){
  String u=consumer();multi=true;var f=paidGoods(u,1);receiveAll(u,f);var items=db.queryForList("SELECT id FROM order_items WHERE suborder_id=?",UUID.fromString(f.subId()));assertEquals(2,items.size());
  String image=upload(u,"REVIEW","image/png",png());for(var item:items)approveReview(submitReview(u,item.get("id").toString(),reviewBody(List.of(image),null,false)));assertEquals(15,reviewEarn(u));
  assertEquals(2,db.queryForObject("SELECT count(*) FROM points_ledger WHERE user_id=? AND entry_type IN ('REVIEW_EARN','MEDIA_REVIEW_BONUS')",Integer.class,UUID.fromString(userIdOf(u))));
 }
 @Test void editingPreservesPublishedRevisionAndRewardsAreFrozen(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(),null,false)));String revision=r.data().get("revision_id").asString();
  var policy=req("POST","/admin/review-reward-policies",Map.of("base_points",80,"media_bonus_points",40,"refund_strategy","NONE"),admin,Map.of("Idempotency-Key",key(),"X-Reverify-Token",proof("review.policy.manage")));assertEquals(200,policy.status());assertEquals(200,read("/admin/review-reward-policies",admin).status());
  String image=upload(u,"REVIEW","image/png",png());var b=reviewBody(List.of(image),null,false);b.put("body","new media revision");var edited=editReview(u,r,b);assertEquals(200,edited.status());assertEquals(revision,read("/public/reviews/"+r.id(),null).data().get("revision_id").asString());
  assertEquals(409,editReview(u,r,b).status());edited=approveReview(edited);assertEquals(15,reviewEarn(u));assertEquals("new media revision",read("/public/reviews/"+r.id(),null).data().get("body").asString());
  assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("UPDATE review_revisions SET body='mutated' WHERE id=?",UUID.fromString(revision)));
  assertEquals(2,db.queryForObject("SELECT count(*) FROM review_moderation WHERE review_id=?",Integer.class,UUID.fromString(r.id())));
 }
 @Test void referencedMediaCannotBeDeletedAndPrivateMediaCannotBeBorrowed(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);String own=upload(u,"REVIEW","image/png",png()),foreign=upload(consumer(),"REVIEW","image/png",png()),avatar=upload(u,"AVATAR","image/png",png());
  assertEquals(404,submitReview(u,f.itemId(),reviewBody(List.of(foreign),null,false)).status());assertEquals(404,submitReview(u,f.itemId(),reviewBody(List.of(avatar),null,false)).status());assertEquals(400,submitReview(u,f.itemId(),reviewBody(List.of(own,own),null,false)).status());
  var r=submitReview(u,f.itemId(),reviewBody(List.of(own),null,false));assertEquals(200,r.status());assertEquals(409,req("DELETE","/media/"+own,null,u,Map.of()).status());
  assertEquals(200,binary("/consumer/reviews/"+r.id()+"/media/"+own,u,png()));assertEquals(200,binary("/admin/reviews/"+r.id()+"/media/"+own,admin,png()));assertEquals(404,binary("/public/reviews/"+r.id()+"/media/"+own,null,png()));
  r=approveReview(r);assertEquals(200,binary("/public/reviews/"+r.id()+"/media/"+own,null,png()));assertEquals(404,binary("/public/reviews/"+r.id()+"/media/"+foreign,null,png()));
 }
 @Test void realH264VideoCanBeReviewedButNotUsedForArticle(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);String asset=upload(u,"REVIEW","video/mp4",video());var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(asset),null,false)));assertEquals(15,reviewEarn(u));assertEquals(200,binary("/public/reviews/"+r.id()+"/media/"+asset,null,video()));
  assertEquals(400,req("POST","/media/upload-grants",Map.of("scope","ARTICLE","mime","video/mp4","size_bytes",video().length,"sha256","a".repeat(64)),admin,Map.of()).status());
 }
 @Test void hideReviewRemovesPublicMediaWithoutErasingEvidence(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);String a=upload(u,"REVIEW","image/png",png());var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(a),null,false)));
  var hidden=req("POST","/admin/reviews/"+r.id()+"/moderation",Map.of("decision","HIDE","reason","TEST"),admin,Map.of("Idempotency-Key",key(),"If-Match",match(r),"X-Reverify-Token",proof("review.moderate")));assertEquals(200,hidden.status());
  assertEquals(404,read("/public/reviews/"+r.id(),null).status());assertEquals(404,binary("/public/reviews/"+r.id()+"/media/"+a,null,png()));assertEquals(200,binary("/consumer/reviews/"+r.id()+"/media/"+a,u,png()));assertEquals(15,reviewEarn(u));
 }
 @Test void fullSplitRefundClawsBackAllReviewPointsExactly(){
  String u=consumer();var f=paidGoods(u,3,67,List.of());receiveAll(u,f);String a=upload(u,"REVIEW","image/png",png());approveReview(submitReview(u,f.itemId(),reviewBody(List.of(a),null,false)));assertEquals(15,reviewEarn(u));
  for(int i=0;i<3;i++)refund(u,f,1);assertEquals(0,reviewEarn(u));assertEquals(15,db.queryForObject("SELECT -sum(points) FROM points_ledger WHERE user_id=? AND entry_type='REVIEW_CLAWBACK'",Long.class,UUID.fromString(userIdOf(u))));
  assertFalse(read("/consumer/order-items/"+f.itemId()+"/review-eligibility",u).data().get("eligible").asBoolean());assertEquals(200,read("/consumer/points/ledger?entry_type=REVIEW_CLAWBACK",u).status());
 }
 @Test void mediaUpgradeAfterPartialRefundCatchesUpClawback(){
  String u=consumer();var f=paidGoods(u,2);receiveAll(u,f);var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(),null,false)));refund(u,f,1);assertEquals(5,reviewEarn(u));
  String a=upload(u,"REVIEW","image/png",png());r=approveReview(editReview(u,r,reviewBody(List.of(a),null,false)));assertEquals(8,reviewEarn(u));refund(u,f,1);assertEquals(0,reviewEarn(u));
 }
 @Test void activeAftersaleBlocksFirstReview(){String u=consumer();var f=paidGoods(u,2);receiveAll(u,f);aftersale(u,f,1);assertEquals(409,submitReview(u,f.itemId(),reviewBody(List.of(),null,false)).status());}
 @Test void articleDraftSubmissionPublicationAndLiveProducts(){
  String asset=upload(admin,"ARTICLE","image/png",png());var a=createArticle(articleBody(List.of(asset),List.of(sku)));assertEquals(404,read("/public/content/"+a.id(),null).status());assertEquals(409,moderateArticle(a,"PUBLISH").status());a=submitArticle(a);assertEquals(404,read("/public/content/"+a.id(),null).status());a=moderateArticle(a,"PUBLISH");assertEquals(200,a.status(),a.body().toString());
  var pub=read("/public/content/"+a.id(),null);assertEquals(200,pub.status());assertEquals("<script>plain text, no execution</script>",pub.data().get("body").asString());assertTrue(pub.data().get("sponsored").asBoolean());assertTrue(pub.data().get("products").get(0).get("available").asBoolean());assertNull(pub.data().get("created_by"));
  assertEquals(200,read("/public/content?category=FOOD_KNOWLEDGE",null).status());assertEquals(200,read("/consumer/content/"+a.id(),consumer()).status());assertEquals(200,read("/admin/content",admin).status());assertEquals(200,read("/admin/content/"+a.id(),admin).status());
  assertEquals(200,binary("/public/content/"+a.id()+"/media/"+asset,null,png()));assertEquals(200,binary("/admin/content/"+a.id()+"/media/"+asset,admin,png()));assertEquals(409,req("DELETE","/media/"+asset,null,admin,Map.of()).status());
  assertEquals(400,read("/public/content/"+a.id()+"?pet_id="+UUID.randomUUID(),null).status());assertEquals(404,read("/consumer/content/"+a.id()+"?pet_id="+UUID.randomUUID(),consumer()).status());
 }
 @Test void articleRejectedRevisionDoesNotReplacePublishedArticle(){
  var a=moderateArticle(submitArticle(createArticle(articleBody(List.of(),List.of()))),"PUBLISH");String id=a.id(),revision=a.data().get("revision_id").asString();var b=new LinkedHashMap<>(articleBody(List.of(),List.of()));b.put("title","replacement draft");
  var revised=req("PATCH","/admin/content/"+id,b,admin,Map.of("Idempotency-Key",key(),"If-Match",match(a)));assertEquals(200,revised.status());assertEquals(409,req("PATCH","/admin/content/"+id,b,admin,Map.of("Idempotency-Key",key(),"If-Match",match(a))).status());
  assertEquals(revision,read("/public/content/"+id,null).data().get("revision_id").asString());var rejected=moderateArticle(submitArticle(revised),"REJECT");assertEquals(200,rejected.status());assertEquals(revision,read("/public/content/"+id,null).data().get("revision_id").asString());
  var published=moderateArticle(submitArticle(rejected),"PUBLISH");assertEquals(200,published.status());assertEquals("replacement draft",read("/public/content/"+id,null).data().get("title").asString());assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("DELETE FROM content_article_revisions WHERE id=?",UUID.fromString(revision)));
 }
 @Test void articleHideAndInvalidInputAreControlled(){
  var bad=new LinkedHashMap<>(articleBody(List.of(),List.of()));bad.put("source_refs",List.of());assertEquals(400,req("POST","/admin/content",bad,admin,Map.of("Idempotency-Key",key())).status());
  assertEquals(403,req("POST","/admin/content",articleBody(List.of(),List.of()),consumer(),Map.of("Idempotency-Key",key())).status());
  String asset=upload(admin,"ARTICLE","image/png",png());var a=moderateArticle(submitArticle(createArticle(articleBody(List.of(asset),List.of()))),"PUBLISH");a=moderateArticle(a,"HIDE");assertEquals(200,a.status());assertEquals(404,read("/public/content/"+a.id(),null).status());assertEquals(404,binary("/public/content/"+a.id()+"/media/"+asset,null,png()));assertEquals(200,binary("/admin/content/"+a.id()+"/media/"+asset,admin,png()));
 }
 @Test void publishingCommandsRejectReaderOnlyAndMissingProof(){
  var a=submitArticle(createArticle(articleBody(List.of(),List.of())));String reader=identity("ADMIN",null,List.of("content.read","review.read"));
  assertEquals(403,req("POST","/admin/content/"+a.id()+"/moderation",Map.of("decision","PUBLISH","reason","TEST"),reader,Map.of("Idempotency-Key",key(),"If-Match",match(a))).status());
  assertEquals(403,req("POST","/admin/content/"+a.id()+"/moderation",Map.of("decision","PUBLISH","reason","TEST"),admin,Map.of("Idempotency-Key",key(),"If-Match",match(a))).status());assertEquals(404,read("/public/content/"+a.id(),null).status());
 }
 @Test void invalidPaginationAndPoliciesAreRejected(){assertEquals(400,read("/public/content?limit=101",null).status());assertEquals(400,read("/public/content?cursor=bad",null).status());assertEquals(400,read("/public/content?category=USER_FEED",null).status());assertEquals(400,req("POST","/admin/review-reward-policies",Map.of("base_points",-1,"media_bonus_points",5,"refund_strategy","NONE"),admin,Map.of("Idempotency-Key",key())).status());}


 Response pet(String u){var r=req("POST","/consumer/pets",Map.of("name","PRIVATE pet name","species_id","10000000-0000-4000-8000-000000000001","sex","UNKNOWN","neutered_status","UNKNOWN","allergens",List.of(),"avoidance_notes",List.of("PRIVATE medical note")),u,Map.of("Idempotency-Key",key()));assertEquals(201,r.status(),r.body().toString());return r;}
 @Test void explicitPetConsentAndImmediateRevocation(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var p=pet(u);assertEquals(404,submitReview(u,f.itemId(),reviewBody(List.of(),pet(consumer()).id(),true)).status());assertEquals(400,submitReview(u,f.itemId(),reviewBody(List.of(),p.id(),false)).status());
  var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(),p.id(),true)));var visible=read("/public/reviews/"+r.id(),null);assertFalse(visible.data().get("pet_label").isNull());assertFalse(visible.body().toString().contains("PRIVATE"));
  r=editReview(u,r,reviewBody(List.of(),null,false));assertEquals(200,r.status());assertTrue(read("/public/reviews/"+r.id(),null).data().get("pet_label").isNull(),"revocation is immediate even before re-moderation");
 }
 @Test void deletedPetStopsPublicLabelAndArticleFitRequiresOwnPet(){
  String u=consumer();var p=pet(u);var f=paidGoods(u,1);receiveAll(u,f);var r=approveReview(submitReview(u,f.itemId(),reviewBody(List.of(),p.id(),true)));var a=moderateArticle(submitArticle(createArticle(articleBody(List.of(),List.of(sku)))),"PUBLISH");assertEquals(200,read("/consumer/content/"+a.id()+"?pet_id="+p.id(),u).status());assertEquals(404,read("/consumer/content/"+a.id()+"?pet_id="+p.id(),consumer()).status());
  assertEquals(200,req("DELETE","/consumer/pets/"+p.id(),null,u,Map.of("Idempotency-Key",key(),"If-Match",match(p))).status());assertTrue(read("/public/reviews/"+r.id(),null).data().get("pet_label").isNull());
 }
 @Test void failedAuditRollsBackPublicationRewardProofAndOutbox(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var r=submitReview(u,f.itemId(),reviewBody(List.of(),null,false));String proof=proof("review.moderate"),k=key();var b=Map.of("decision","APPROVE","reason","TEST");var headers=Map.of("Idempotency-Key",k,"If-Match",match(r),"X-Reverify-Token",proof);
  db.execute("CREATE FUNCTION fail_review_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='review.ReviewModerated' THEN RAISE EXCEPTION 'TEST_ONLY audit failure'; END IF; RETURN NEW; END $$");db.execute("CREATE TRIGGER test_review_audit BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION fail_review_audit()");
  try{assertEquals(503,req("POST","/admin/reviews/"+r.id()+"/moderation",b,admin,headers).status());assertEquals(0,reviewEarn(u));assertEquals("PENDING",read("/consumer/reviews/"+r.id(),u).data().get("draft_status").asString());assertEquals(0,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='ReviewModerated' AND aggregate_id=?",Integer.class,r.id()));assertEquals(0,db.queryForObject("SELECT count(*) FROM identity_command WHERE idempotency_key=?",Integer.class,k));}
  finally{db.execute("DROP TRIGGER test_review_audit ON audit_event");db.execute("DROP FUNCTION fail_review_audit()");}
  assertEquals(200,req("POST","/admin/reviews/"+r.id()+"/moderation",b,admin,headers).status());assertEquals(10,reviewEarn(u));assertEquals(200,req("POST","/admin/reviews/"+r.id()+"/moderation",b,admin,headers).status());assertEquals(10,reviewEarn(u));
 }
 @Test void writeOnlyAdminCannotCommitAnUnreadableArticle(){String writer=identity("ADMIN",null,List.of("content.write"));int before=db.queryForObject("SELECT count(*) FROM content_articles",Integer.class);assertEquals(403,req("POST","/admin/content",articleBody(List.of(),List.of()),writer,Map.of("Idempotency-Key",key())).status());assertEquals(before,db.queryForObject("SELECT count(*) FROM content_articles",Integer.class));}
 @Test void noneRefundPolicyDoesNotClawBackReviewAward(){
  var policy=req("POST","/admin/review-reward-policies",Map.of("base_points",7,"media_bonus_points",2,"refund_strategy","NONE"),admin,Map.of("Idempotency-Key",key(),"X-Reverify-Token",proof("review.policy.manage")));assertEquals(200,policy.status());String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);approveReview(submitReview(u,f.itemId(),reviewBody(List.of(),null,false)));assertEquals(7,reviewEarn(u));refund(u,f,1);assertEquals(7,reviewEarn(u));assertTrue(db.queryForObject("SELECT count(*) FROM points_ledger WHERE user_id=? AND entry_type='REFUND_CLAWBACK'",Integer.class,UUID.fromString(userIdOf(u)))>0);
 }
 @Test void pendingResourceCannotBeAttachedAndDeletedResourceCannotBeRead(){
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);var grant=req("POST","/media/upload-grants",Map.of("scope","REVIEW","mime","image/png","size_bytes",64,"sha256","a".repeat(64)),u,Map.of());assertEquals(201,grant.status());assertEquals(409,submitReview(u,f.itemId(),reviewBody(List.of(grant.data().get("asset_id").asString()),null,false)).status());
  String a=upload(u,"REVIEW","image/png",png());assertEquals(202,req("DELETE","/media/"+a,null,u,Map.of()).status());assertEquals(409,submitReview(u,f.itemId(),reviewBody(List.of(a),null,false)).status());
 }
 @Test void retiredProductIsUnavailableWithoutReplacingArticleHistory(){
  var a=moderateArticle(submitArticle(createArticle(articleBody(List.of(),List.of(sku)))),"PUBLISH");db.update("UPDATE sku_standard_versions SET status='RETIRED' WHERE sku_id=?",UUID.fromString(sku));var publicA=read("/public/content/"+a.id(),null);assertEquals(200,publicA.status());assertFalse(publicA.data().get("products").get(0).get("available").asBoolean());assertEquals(a.data().get("revision_id").asString(),publicA.data().get("revision_id").asString());
 }
 @Test void concurrentMediaDeleteAndAttachNeverLeaveBrokenReference()throws Exception{
  String u=consumer();var f=paidGoods(u,1);receiveAll(u,f);String asset=upload(u,"REVIEW","image/png",png());var start=new java.util.concurrent.CountDownLatch(1);
  try(var pool=java.util.concurrent.Executors.newFixedThreadPool(2)){var a=pool.submit(()->{start.await();return submitReview(u,f.itemId(),reviewBody(List.of(asset),null,false));});var b=pool.submit(()->{start.await();return req("DELETE","/media/"+asset,null,u,Map.of());});start.countDown();var review=a.get();var deleted=b.get();assertTrue(review.status()==200&&deleted.status()==409||review.status()==409&&deleted.status()==202,review.body()+" / "+deleted.body());}
  assertEquals(0,db.queryForObject("SELECT count(*) FROM media_asset_usage u JOIN media_asset a ON a.id=u.asset_id WHERE a.status<>'READY'",Integer.class));
 }

 @AfterAll static void evidence()throws Exception{Files.createDirectories(Path.of("target"));JsonMapper j=JsonMapper.builder().build();Files.writeString(Path.of("target/m52-contract-samples.json"),j.writeValueAsString(SAMPLES));Files.writeString(Path.of("target/m52-binary-samples.json"),j.writeValueAsString(BINARY));PG.close();}
}
