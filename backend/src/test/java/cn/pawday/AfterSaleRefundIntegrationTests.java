package cn.pawday;
import cn.pawday.identity.*;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.net.URI;
import java.net.http.*;
import java.nio.file.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
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
@org.springframework.context.annotation.Import(AfterSaleRefundIntegrationTests.TimeConfiguration.class)
class AfterSaleRefundIntegrationTests {
 static final java.util.concurrent.atomic.AtomicLong OFFSET=new java.util.concurrent.atomic.AtomicLong();
 @org.springframework.boot.test.context.TestConfiguration static class TimeConfiguration {
  @org.springframework.context.annotation.Bean @org.springframework.context.annotation.Primary Clock checkoutTestClock(){return new Clock(){public ZoneId getZone(){return ZoneOffset.UTC;}public Clock withZone(ZoneId zone){return this;}public Instant instant(){return Instant.now().plusSeconds(OFFSET.get());}};}
 }
 @AfterEach void resetClock(){OFFSET.set(0);}

 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.simulation-enabled",()->true);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);}
 @Autowired JdbcTemplate db;@Autowired Crypto crypto;@Autowired Clock clock;@LocalServerPort int port;
 @Autowired cn.pawday.payment.RefundService refunds;
 final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new CopyOnWriteArrayList<>();
 String admin,merchant,foreign,colleague;UUID adminSession,adminPrincipal,merchantId,store;String sku;
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}String id(){return data().get("id").asString();}}

 String key(){return UUID.randomUUID().toString();}
 String identity(String realm,UUID m,List<String> permissions){UUID p=UUID.randomUUID(),role=UUID.randomUUID();if(realm.equals("CONSUMER")){UUID u=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",u);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",p,u);}else db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,?,?,?,?,?)",p,realm,m,key(),"TEST-ONLY",realm.equals("ADMIN")?crypto.encrypt(new byte[20]):null);
  db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,'Aftersale test')",role,realm,key());for(String permission:permissions)db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code=?",role,permission);db.update("INSERT INTO principal_role VALUES (?,?,?)",p,role,realm);UUID session=UUID.randomUUID();String t=crypto.token();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'AFTERSALE-IT',?,?,?)",session,p,crypto.hash(t),Timestamp.from(clock.instant().plusSeconds(900)),Timestamp.from(clock.instant().plusSeconds(2592000)),Timestamp.from(clock.instant()));if(realm.equals("ADMIN")){adminSession=session;adminPrincipal=p;}if(realm.equals("MERCHANT"))db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",p,m,store);return t;
 }
 @BeforeEach void setup(){OFFSET.set(0);merchantId=UUID.randomUUID();store=UUID.randomUUID();db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE')",merchantId,key());db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST scope')",store,merchantId);
  admin=identity("ADMIN",null,List.of("offer.admin.manage","order.admin.read","payment.read","aftersale.arbitrate"));merchant=identity("MERCHANT",merchantId,List.of("offer.read","offer.write","inventory.adjust","order.read","order.ship","order.default-scope","order.cancel.handle","aftersale.handle"));colleague=identity("MERCHANT",merchantId,List.of("order.read","order.ship","order.default-scope"));UUID m=UUID.randomUUID();db.update("INSERT INTO merchant VALUES (?,'TEST foreign','ACTIVE')",m);UUID saved=store;store=UUID.randomUUID();db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST foreign store')",store,m);foreign=identity("MERCHANT",m,List.of("order.read","order.cancel.handle","aftersale.handle"));store=saved;
  UUID brand=UUID.randomUUID(),spu=UUID.randomUUID(),k=UUID.randomUUID();sku=k.toString();db.update("INSERT INTO brands(id,name,source_ref) VALUES (?,?,'TEST-ONLY')",brand,key());db.update("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES (?,?,'TEST-ONLY','CAT','DRY_FOOD')",spu,brand);db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES (?,?,?,1000,'BAG')",k,spu,key());db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) VALUES (?,?,1,'PUBLISHED','[\"TEST-ONLY\"]','[]',false,'[]','[\"TEST-ONLY source\"]','2026-10-01',?,clock_timestamp())",UUID.randomUUID(),k,adminPrincipal);
 }
 Response req(String method,String path,Object payload,String token,Map<String,String> headers){try{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));var response=http.send(b.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",body));return new Response(response.statusCode(),body);}catch(Exception e){throw new AssertionError(e);}}
 Response read(String path,String token){return req("GET",path,null,token,Map.of());}
 String create(){var b=new LinkedHashMap<String,Object>(Map.of("sku_id",sku,"sale_price_fen",1000,"member_price_fen",900,"fulfillment_sla","TEST-ONLY 48h"));b.put("store_id",store.toString());var r=req("POST","/merchant/offers",b,merchant,Map.of("Idempotency-Key",key()));assertEquals(201,r.status(),r.body().toString());return r.id();}
 String ready(){String o=create();assertEquals(201,req("POST","/merchant/offers/"+o+"/inventory-adjustments",Map.of("delta_qty",20,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());assertEquals(200,req("POST","/merchant/offers/"+o+"/activate",Map.of("reason","TEST-ONLY lifecycle"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());return o;}
 String consumer(){return identity("CONSUMER",null,List.of());}
 UUID user(String token){return db.queryForObject("SELECT p.user_id FROM identity_principal p JOIN auth_session s ON s.principal_id=p.id WHERE s.access_token_hash=?",UUID.class,crypto.hash(token));}
 Map<String,Object> addressBody(){return Map.of("recipient","TEST recipient","phone","13800000000","province_code","310000","city_code","310100","district_code","310101","detail","TEST-only address");}
 String addressFor(String u){var r=req("POST","/consumer/addresses",addressBody(),u,Map.of("Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());return r.id();}
 String addFor(String u,String o,int qty){var r=req("POST","/consumer/cart/items",Map.of("offer_id",o,"quantity",qty),u,Map.of("Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());return r.id();}
 void shipping(){db.update("INSERT INTO shipping_rule_versions(id,merchant_id,version_no,province_codes,base_fen,per_kg_fen,free_threshold_fen,created_by) VALUES (?,?,1,'[\"310000\"]',300,100,NULL,?)",UUID.randomUUID(),merchantId,adminPrincipal);}
 String coupon(String u,String scope,long amount,long threshold){UUID c=UUID.randomUUID(),def=UUID.randomUUID();db.update("INSERT INTO coupon_definitions(id,version,status,parameters) VALUES (?,1,'PUBLISHED','{}')",def);db.update("INSERT INTO user_coupons(id,user_id,definition_id,definition_version,scope,merchant_id,amount_fen,threshold_fen,status,expires_at,version,rule_version) VALUES (?,?,?,1,?, ?,?,?, 'AVAILABLE',?,0,'TEST-ONLY-1')",c,user(u),def,scope,scope.equals("MERCHANT")?merchantId:null,amount,threshold,Timestamp.from(clock.instant().plusSeconds(600)));return c.toString();}
 String quote(String u,String i,String a,List<String>coupons){var q=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",List.of(i),"address_id",a,"coupon_ids",coupons,"use_membership",false),u,Map.of("Idempotency-Key",key()));assertEquals(200,q.status(),q.body().toString());return q.data().get("quote_id").asString();}
 long balance(String o){return db.queryForObject("SELECT on_hand_qty FROM inventory_balances WHERE offer_id=?",Long.class,UUID.fromString(o));}

 record Fixture(String u,String offer,Response order,String payment){}
 Fixture fixture(int qty,List<String>coupons){String u=consumer(),o=ready();shipping();String i=addFor(u,o,qty),a=addressFor(u);var order=req("POST","/consumer/orders",Map.of("quote_id",quote(u,i,a,coupons)),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());return new Fixture(u,o,order,order.data().get("payment").get("id").asString());}
 Fixture paid(int qty,List<String>coupons){var f=fixture(qty,coupons);var attempt=req("POST","/consumer/payments/"+f.payment()+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),f.u(),Map.of("Idempotency-Key",key()));String a=attempt.data().get("attempts").get(0).get("id").asString();assertEquals(200,req("POST","/consumer/payments/"+f.payment()+"/simulation",Map.of("attempt_id",a,"outcome","SUCCEEDED"),f.u(),Map.of()).status());return f;}
 String sub(Fixture f){return f.order().data().get("suborders").get(0).get("id").asString();}
 String item(Fixture f){return f.order().data().get("suborders").get(0).get("items").get(0).get("id").asString();}
 long subVersion(Fixture f){return read("/consumer/suborders/"+sub(f)+"/fulfillment",f.u()).data().get("version").asLong();}
 String ship(Fixture f,int qty){var r=req("POST","/merchant/suborders/"+sub(f)+"/shipments",Map.of("carrier_code","SF","tracking_no","TEST"+key().replace("-",""),"items",List.of(Map.of("order_item_id",item(f),"quantity",qty))),merchant,Map.of("If-Match","\""+subVersion(f)+"\"","Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());var ships=r.data().get("shipments");return ships.get(ships.size()-1).get("id").asString();}
 void receive(Fixture f,String shipment){var r=req("POST","/consumer/suborders/"+sub(f)+"/confirm-receipt",Map.of("shipment_ids",List.of(shipment)),f.u(),Map.of("If-Match","\""+subVersion(f)+"\"","Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());}

 Response cancelPaid(String who,Fixture f,int qty,String k){return req("POST","/consumer/suborders/"+sub(f)+"/cancellations",Map.of("reason_code","CONSUMER_CANCELLED","items",List.of(Map.of("order_item_id",item(f),"quantity",qty))),who,Map.of("Idempotency-Key",k));}
 Response merchantCancel(Fixture f,int qty,String who,String k){return req("POST","/merchant/suborders/"+sub(f)+"/cancellations",Map.of("reason_code","MERCHANT_OUT_OF_STOCK","items",List.of(Map.of("order_item_id",item(f),"quantity",qty))),who,Map.of("Idempotency-Key",k));}
 Response applyRefundOnly(Fixture f,int qty,String k){return req("POST","/consumer/suborders/"+sub(f)+"/aftersales",Map.of("type","REFUND_ONLY","reason_code","QUALITY_ISSUE","reason_text","TEST-ONLY quality concern","items",List.of(Map.of("order_item_id",item(f),"quantity",qty)),"evidence",List.of(Map.of("content","TEST-ONLY photo description"))),f.u(),Map.of("Idempotency-Key",k));}
 Response applyReturn(Fixture f,int qty,String k){return req("POST","/consumer/suborders/"+sub(f)+"/aftersales",Map.of("type","RETURN_REFUND","reason_code","WRONG_ITEM","reason_text","TEST-ONLY wrong item","items",List.of(Map.of("order_item_id",item(f),"quantity",qty)),"evidence",List.of()),f.u(),Map.of("Idempotency-Key",k));}
 Response aftersale(String who,String realm,String id){return read("/"+realm+"/aftersales/"+id,who);}
 Response decide(String who,String id,long v,String action,String k){return req("POST","/merchant/aftersales/"+id+"/decide",Map.of("action",action,"reason","TEST-ONLY merchant decision"),who,Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 Response shipReturn(Fixture f,String id,long v,String k){return req("POST","/consumer/aftersales/"+id+"/return-shipment",Map.of("carrier_code","ZTO","tracking_no","RET"+key().replace("-","")),f.u(),Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 Response arrival(String id,long v,String k){return req("POST","/merchant/aftersales/"+id+"/confirm-arrival",Map.of(),merchant,Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 Response inspect(String id,long v,String action,String k){return req("POST","/merchant/aftersales/"+id+"/inspect",Map.of("action",action,"reason","TEST-ONLY inspection"),merchant,Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 Response escalate(Fixture f,String id,long v,String k){return req("POST","/consumer/aftersales/"+id+"/escalate",Map.of("reason","TEST-ONLY consumer escalation"),f.u(),Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 String proof(String action){String p=crypto.token();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(p),adminSession,action,Timestamp.from(clock.instant().plusSeconds(300)),Timestamp.from(clock.instant()));return p;}
 Response arbitrate(String id,long v,String decision,String p,String k){var h=new HashMap<String,String>(Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));if(p!=null)h.put("X-Reverify-Token",p);return req("POST","/admin/aftersales/"+id+"/decide",Map.of("decision",decision,"reason","TEST-ONLY platform ruling"),admin,h);}
 void directive(String refundNo,String outcome){db.update("INSERT INTO simulated_refund_directives(refund_no,outcome) VALUES (?,?) ON CONFLICT (refund_no) DO UPDATE SET outcome=EXCLUDED.outcome",refundNo,outcome);}
 String pendingRefundNo(UUID payment){return db.queryForObject("SELECT refund_no FROM refunds WHERE payment_id=? ORDER BY created_at DESC LIMIT 1",String.class,payment);}

 @Test void refundUnitsFrozenPerLogicalUnit(){var f=paid(3,List.of());
  long payable=db.queryForObject("SELECT payable_amount_fen FROM order_items WHERE id=?",Long.class,UUID.fromString(item(f)));
  var units=db.queryForList("SELECT unit_index,paid_amount_fen FROM order_item_refund_units WHERE order_item_id=? ORDER BY unit_index",UUID.fromString(item(f)));assertEquals(3,units.size());
  long base=payable/3,rem=payable%3;for(int idx=0;idx<3;idx++)assertEquals(base+(idx<rem?1:0),((Number)units.get(idx).get("paid_amount_fen")).longValue());
  assertEquals(payable,units.stream().mapToLong(x->((Number)x.get("paid_amount_fen")).longValue()).sum());
 }
 @Test void refundUnitsRemainderDistributionFollowsFrozenSnapshot(){String u=consumer(),o=ready();shipping();String i=addFor(u,o,3),a=addressFor(u);String c=coupon(u,"MERCHANT",1900,0);var order=req("POST","/consumer/orders",Map.of("quote_id",quote(u,i,a,List.of(c))),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());
  String itemId=order.data().get("suborders").get(0).get("items").get(0).get("id").asString();
  long payable=db.queryForObject("SELECT payable_amount_fen FROM order_items WHERE id=?",Long.class,UUID.fromString(itemId));assertTrue(payable<3000,"merchant coupon must discount the item");assertTrue(payable%3>0,"fixture must exercise remainder distribution");
  var units=db.queryForList("SELECT paid_amount_fen FROM order_item_refund_units WHERE order_item_id=? ORDER BY unit_index",UUID.fromString(itemId));
  var expected=new ArrayList<Long>();for(int idx=0;idx<3;idx++)expected.add(payable/3+(idx<payable%3?1:0));
  assertEquals(expected,units.stream().map(x->((Number)x.get("paid_amount_fen")).longValue()).toList());
 }
 @Test void paidPartialCancellationRefundsFrozenUnitsAndRestocksOnce(){var f=paid(2,List.of());
  var first=cancelPaid(f.u(),f,1,key());assertEquals(200,first.status(),first.body().toString());
  assertEquals("COMPLETED",first.data().get("status").asString());assertEquals(1000,first.data().get("refund_amount_fen").asLong());assertEquals("SUCCEEDED",first.data().get("refund").get("status").asString());
  assertEquals(1,db.queryForObject("SELECT cancelled_qty FROM order_items WHERE id=?",Integer.class,UUID.fromString(item(f))));assertEquals(19,balance(f.offer()));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM inventory_restock_events WHERE source_type='CANCELLATION_ITEM' AND offer_id=?",Integer.class,UUID.fromString(f.offer())));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='CANCELLATION' AND status='REFUNDED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
  var adminRefunds=read("/admin/refunds?status=SUCCEEDED",admin);assertEquals(200,adminRefunds.status());assertTrue(adminRefunds.body().get("data").toString().contains(first.data().get("refund").get("refund_no").asString()));
  var listed=read("/consumer/suborders/"+sub(f)+"/cancellations",f.u());assertEquals(200,listed.status());assertEquals(1,listed.body().get("data").size());
  var second=cancelPaid(f.u(),f,1,key());assertEquals(200,second.status(),second.body().toString());
  long shipping=db.queryForObject("SELECT payable_amount_fen FROM suborders WHERE id=?",Long.class,UUID.fromString(sub(f)))-db.queryForObject("SELECT coalesce(sum(payable_amount_fen),0) FROM order_items WHERE suborder_id=?",Long.class,UUID.fromString(sub(f)));
  assertEquals(1000+shipping,second.data().get("refund_amount_fen").asLong());
  assertEquals("CANCELLED",read("/consumer/suborders/"+sub(f)+"/fulfillment",f.u()).data().get("fulfillment_status").asString());
  assertEquals("CANCELLED",read("/consumer/orders/"+f.order().id(),f.u()).data().get("status").asString());
  assertEquals(20,balance(f.offer()));
 }
 @Test void concurrentCancellationsCannotExceedUnshippedQuantity()throws Exception{var f=paid(2,List.of());
  var pool=Executors.newFixedThreadPool(2);try{var start=new CountDownLatch(1);Callable<Response> work=()->{start.await();return cancelPaid(f.u(),f,2,key());};var x=pool.submit(work);var y=pool.submit(work);start.countDown();var statuses=List.of(x.get(20,TimeUnit.SECONDS).status(),y.get(20,TimeUnit.SECONDS).status());assertTrue(statuses.contains(200),statuses.toString());assertTrue(statuses.contains(409),statuses.toString());assertEquals(1,db.queryForObject("SELECT count(*) FROM order_cancellations WHERE suborder_id=?",Integer.class,UUID.fromString(sub(f))));assertEquals(2,db.queryForObject("SELECT cancelled_qty FROM order_items WHERE id=?",Integer.class,UUID.fromString(item(f))));}finally{pool.shutdownNow();}
 }
 @Test void shippedQuantitiesCannotBeCancelledAndRemainingStillShips(){var f=paid(3,List.of());ship(f,1);
  assertEquals(409,cancelPaid(f.u(),f,3,key()).status());
  var cancel=cancelPaid(f.u(),f,1,key());assertEquals(200,cancel.status(),cancel.body().toString());assertEquals(1000,cancel.data().get("refund_amount_fen").asLong());
  assertEquals(0,db.queryForObject("SELECT count(*) FROM order_cancellation_items i JOIN order_cancellations c ON c.id=i.cancellation_id WHERE c.suborder_id=? AND i.shipping_refund_fen>0",Integer.class,UUID.fromString(sub(f))));
  ship(f,1);assertEquals("SHIPPED_WAITING_RECEIPT",read("/consumer/suborders/"+sub(f)+"/fulfillment",f.u()).data().get("fulfillment_status").asString());
 }
 @Test void transientChannelFailureKeepsCancellationAndRetriesSameRefundNumber(){var f=paid(2,List.of());
  // The endpoint drives the channel synchronously, so stage the failure directive through a directly created intent.
  UUID cid=UUID.randomUUID();db.update("INSERT INTO order_cancellations(id,order_id,suborder_id,actor_type,reason_code,status) VALUES (?,?,?,'CONSUMER','CONSUMER_CANCELLED','ACCEPTED')",cid,UUID.fromString(f.order().id()),UUID.fromString(sub(f)));
  UUID rid=refunds.createIntent(UUID.fromString(f.payment()),cid,null,1000);String refundNo=db.queryForObject("SELECT refund_no FROM refunds WHERE id=?",String.class,rid);
  UUID claim=UUID.randomUUID();db.update("INSERT INTO order_refund_unit_claims(id,order_item_id,unit_index,source_type,source_item_id,refund_id) VALUES (?,?,1,'CANCELLATION',?,?)",claim,UUID.fromString(item(f)),cid,rid);
  directive(refundNo,"FAIL_TRANSIENT");refunds.drive(rid);
  var held=db.queryForMap("SELECT status,attempt_count,last_error_code,next_retry_at FROM refunds WHERE id=?",rid);
  assertEquals("PROCESSING",held.get("status"));assertEquals(1,((Number)held.get("attempt_count")).intValue());assertEquals("SIMULATED_TRANSIENT",held.get("last_error_code"));assertNotNull(held.get("next_retry_at"));
  assertEquals("ACCEPTED",db.queryForObject("SELECT status FROM order_cancellations WHERE id=?",String.class,cid));
  assertEquals("RESERVED",db.queryForObject("SELECT status FROM order_refund_unit_claims WHERE id=?",String.class,claim));
  assertEquals(0,db.queryForObject("SELECT count(*) FROM simulated_payment_refund_requests WHERE refund_no=?",Integer.class,refundNo));
  directive(refundNo,"SUCCEED");db.update("UPDATE refunds SET next_retry_at=clock_timestamp()-interval '1 hour' WHERE id=?",rid);refunds.drive(rid);
  assertEquals("SUCCEEDED",db.queryForObject("SELECT status FROM refunds WHERE id=?",String.class,rid));
  assertEquals(2,db.queryForObject("SELECT attempt_count FROM refunds WHERE id=?",Integer.class,rid));
  assertEquals("COMPLETED",db.queryForObject("SELECT status FROM order_cancellations WHERE id=?",String.class,cid));
  assertEquals("REFUNDED",db.queryForObject("SELECT status FROM order_refund_unit_claims WHERE id=?",String.class,claim));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_payment_refund_requests WHERE refund_no=?",Integer.class,refundNo));
 }
 @Test void finalChannelFailureExhaustsToManualQueueWithoutReleasingOccupation(){var f=paid(2,List.of());
  // Same staging approach: the directive must exist before the first drive of this refund number.
  UUID cid=UUID.randomUUID();db.update("INSERT INTO order_cancellations(id,order_id,suborder_id,actor_type,reason_code,status) VALUES (?,?,?,'CONSUMER','CONSUMER_CANCELLED','ACCEPTED')",cid,UUID.fromString(f.order().id()),UUID.fromString(sub(f)));
  UUID rid=refunds.createIntent(UUID.fromString(f.payment()),cid,null,1000);String refundNo=db.queryForObject("SELECT refund_no FROM refunds WHERE id=?",String.class,rid);
  UUID claim=UUID.randomUUID();db.update("INSERT INTO order_refund_unit_claims(id,order_item_id,unit_index,source_type,source_item_id,refund_id) VALUES (?,?,1,'CANCELLATION',?,?)",claim,UUID.fromString(item(f)),cid,rid);
  directive(refundNo,"FAIL_FINAL");for(int i=0;i<8;i++)refunds.drive(rid);
  var state=db.queryForMap("SELECT status,attempt_count,next_retry_at FROM refunds WHERE id=?",rid);
  assertEquals("FAILED_FINAL",state.get("status"));assertEquals(8,((Number)state.get("attempt_count")).intValue());assertNull(state.get("next_retry_at"));
  assertEquals("ACCEPTED",db.queryForObject("SELECT status FROM order_cancellations WHERE id=?",String.class,cid));
  assertEquals("RESERVED",db.queryForObject("SELECT status FROM order_refund_unit_claims WHERE id=?",String.class,claim));
  assertEquals(0,db.queryForObject("SELECT count(*) FROM simulated_payment_refund_requests WHERE refund_no=?",Integer.class,refundNo));
  refunds.recoverBatch();assertEquals("FAILED_FINAL",db.queryForObject("SELECT status FROM refunds WHERE id=?",String.class,rid));
 }
 @Test void channelSuccessWithLocalRollbackRecoversWithoutDuplicateRefund(){var f=paid(2,List.of());
  db.execute("CREATE FUNCTION fail_m45_refund_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='refund.succeeded' THEN RAISE EXCEPTION 'TEST fault';END IF; RETURN NEW; END $$");
  db.execute("CREATE TRIGGER fail_m45_refund_audit BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION fail_m45_refund_audit()");
  Response created;
  try{created=cancelPaid(f.u(),f,1,key());assertEquals(503,created.status(),created.body().toString());}finally{db.execute("DROP TRIGGER fail_m45_refund_audit ON audit_event");db.execute("DROP FUNCTION fail_m45_refund_audit()");}
  UUID cid=db.queryForObject("SELECT id FROM order_cancellations WHERE suborder_id=?",UUID.class,UUID.fromString(sub(f)));
  assertEquals("REFUND_PENDING",db.queryForObject("SELECT status FROM order_cancellations WHERE id=?",String.class,cid));
  UUID rid=db.queryForObject("SELECT id FROM refunds WHERE cancellation_id=?",UUID.class,cid);
  assertEquals("PROCESSING",db.queryForObject("SELECT status FROM refunds WHERE id=?",String.class,rid));
  String refundNo=db.queryForObject("SELECT refund_no FROM refunds WHERE id=?",String.class,rid);
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_payment_refund_requests WHERE refund_no=?",Integer.class,refundNo));
  refunds.recoverBatch();
  assertEquals("SUCCEEDED",db.queryForObject("SELECT status FROM refunds WHERE id=?",String.class,rid));
  assertEquals("COMPLETED",db.queryForObject("SELECT status FROM order_cancellations WHERE id=?",String.class,cid));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_payment_refund_requests WHERE refund_no=?",Integer.class,refundNo));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM inventory_restock_events WHERE source_type='CANCELLATION_ITEM' AND offer_id=?",Integer.class,UUID.fromString(f.offer())));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE refund_id=? AND status='REFUNDED'",Integer.class,rid));
  var view=read("/consumer/cancellations/"+cid,f.u());assertEquals(200,view.status(),view.body().toString());assertEquals("COMPLETED",view.data().get("status").asString());
 }
 @Test void zeroAmountUnitsCompleteWithoutChannelRefund(){String u=consumer(),o=ready();shipping();String i=addFor(u,o,2),a=addressFor(u);String c=coupon(u,"MERCHANT",2000,0);var order=req("POST","/consumer/orders",Map.of("quote_id",quote(u,i,a,List.of(c))),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());
  var f=new Fixture(u,o,order,order.data().get("payment").get("id").asString());var attempt=req("POST","/consumer/payments/"+f.payment()+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));assertEquals(200,req("POST","/consumer/payments/"+f.payment()+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());
  var cancel=cancelPaid(u,f,1,key());assertEquals(200,cancel.status(),cancel.body().toString());
  assertEquals("COMPLETED",cancel.data().get("status").asString());assertEquals(0,cancel.data().get("refund_amount_fen").asLong());assertTrue(cancel.data().get("refund").isNull());
  assertEquals(0,db.queryForObject("SELECT count(*) FROM refunds WHERE payment_id=?",Integer.class,UUID.fromString(f.payment())));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='CANCELLATION' AND status='REFUNDED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
 }
 @Test void wholeScopeCancellationReturnsCouponOnceAfterRefund(){String u=consumer(),o=ready();shipping();String i=addFor(u,o,2),a=addressFor(u);String c=coupon(u,"PLATFORM",100,0);var order=req("POST","/consumer/orders",Map.of("quote_id",quote(u,i,a,List.of(c))),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());
  var f=new Fixture(u,o,order,order.data().get("payment").get("id").asString());var attempt=req("POST","/consumer/payments/"+f.payment()+"/attempts",Map.of("channel","ALIPAY","client_platform","WEB"),u,Map.of("Idempotency-Key",key()));assertEquals(200,req("POST","/consumer/payments/"+f.payment()+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());
  assertEquals(200,cancelPaid(u,f,1,key()).status());
  assertEquals("USED",db.queryForObject("SELECT status FROM user_coupons WHERE id=?",String.class,UUID.fromString(c)));
  var second=cancelPaid(u,f,1,key());assertEquals(200,second.status(),second.body().toString());assertEquals("COMPLETED",second.data().get("status").asString());
  assertEquals("RETURNED",db.queryForObject("SELECT status FROM user_coupons WHERE id=?",String.class,UUID.fromString(c)));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM coupon_return_events WHERE coupon_id=?",Integer.class,UUID.fromString(c)));
  refunds.recoverBatch();assertEquals(1,db.queryForObject("SELECT count(*) FROM coupon_return_events WHERE coupon_id=?",Integer.class,UUID.fromString(c)));
 }
 @Test void expiredCouponCompletesAsExpiredNotReturned(){String u=consumer(),o=ready();shipping();String i=addFor(u,o,2),a=addressFor(u);String c=coupon(u,"PLATFORM",100,0);var order=req("POST","/consumer/orders",Map.of("quote_id",quote(u,i,a,List.of(c))),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status());
  var f=new Fixture(u,o,order,order.data().get("payment").get("id").asString());var attempt=req("POST","/consumer/payments/"+f.payment()+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));assertEquals(200,req("POST","/consumer/payments/"+f.payment()+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());
  OFFSET.set(700);assertEquals(200,cancelPaid(u,f,2,key()).status());
  assertEquals("EXPIRED",db.queryForObject("SELECT status FROM user_coupons WHERE id=?",String.class,UUID.fromString(c)));
  assertEquals("EXPIRED",db.queryForObject("SELECT resulting_status FROM coupon_return_events WHERE coupon_id=?",String.class,UUID.fromString(c)));
 }
 @Test void merchantOutOfStockCancellationRefundsAndNotifies(){var f=paid(2,List.of());
  var cancel=merchantCancel(f,1,merchant,key());assertEquals(200,cancel.status(),cancel.body().toString());
  assertEquals("COMPLETED",cancel.data().get("status").asString());assertEquals("MERCHANT",cancel.data().get("actor_type").asString());assertEquals("MERCHANT_OUT_OF_STOCK",cancel.data().get("reason_code").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='order.cancel.merchant' AND object_id=?",Integer.class,cancel.id()));
  var listed=read("/merchant/suborders/"+sub(f)+"/cancellations",merchant);assertEquals(200,listed.status());assertEquals(1,listed.body().get("data").size());
  assertEquals(403,merchantCancel(f,1,colleague,key()).status());assertEquals(404,merchantCancel(f,1,foreign,key()).status());
 }
 @Test void afterSaleRefundOnlyFlowRefundsOriginalRoute(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);
  var applied=applyRefundOnly(f,1,key());assertEquals(200,applied.status(),applied.body().toString());String aid=applied.id();
  assertEquals("PENDING_MERCHANT",applied.data().get("status").asString());assertEquals(1000,applied.data().get("refund_amount_fen").asLong());
  var decided=decide(merchant,aid,0,"APPROVE_REFUND",key());assertEquals(200,decided.status(),decided.body().toString());
  assertEquals("COMPLETED",decided.data().get("status").asString());assertEquals("SUCCEEDED",decided.data().get("refund").get("status").asString());assertEquals(1000,decided.data().get("refund").get("amount_fen").asLong());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='AFTERSALE' AND status='REFUNDED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
  var view=aftersale(f.u(),"consumer",aid);assertEquals("COMPLETED",view.data().get("status").asString());assertEquals(1,view.data().get("evidence").size());
  var merchantView=aftersale(merchant,"merchant",aid);assertEquals(200,merchantView.status());
  assertEquals(0,db.queryForObject("SELECT count(*) FROM inventory_restock_events WHERE source_type='AFTERSALE_ITEM' AND offer_id=?",Integer.class,UUID.fromString(f.offer())));
 }
 @Test void returnRefundRestocksExactlyOnceAfterInspection(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);
  String aid=applyReturn(f,1,key()).id();
  assertEquals(200,decide(merchant,aid,0,"APPROVE_RETURN",key()).status());
  var shipped=shipReturn(f,aid,1,key());assertEquals(200,shipped.status(),shipped.body().toString());assertEquals("RETURN_IN_TRANSIT",shipped.data().get("status").asString());assertEquals("ZTO",shipped.data().get("return_carrier_code").asString());
  assertEquals(200,arrival(aid,2,key()).status());
  var inspected=inspect(aid,3,"ACCEPT",key());assertEquals(200,inspected.status(),inspected.body().toString());
  assertEquals("COMPLETED",inspected.data().get("status").asString());assertEquals("SUCCEEDED",inspected.data().get("refund").get("status").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM inventory_restock_events WHERE source_type='AFTERSALE_ITEM' AND offer_id=?",Integer.class,UUID.fromString(f.offer())));
  assertEquals(19,balance(f.offer()));
 }
 @Test void merchantRejectKeepsQuantityLockedUntilPlatformFinalReject(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);
  String aid=applyRefundOnly(f,1,key()).id();
  var rejected=decide(merchant,aid,0,"REJECT",key());assertEquals(200,rejected.status());assertEquals("REJECTED",rejected.data().get("status").asString());
  assertEquals(409,applyRefundOnly(f,2,key()).status());
  assertEquals(409,req("POST","/consumer/aftersales/"+aid+"/cancel",Map.of(),f.u(),Map.of("Idempotency-Key",key(),"If-Match","\"1\"")).status());
  var escalated=escalate(f,aid,1,key());assertEquals(200,escalated.status(),escalated.body().toString());assertEquals("PLATFORM_ESCALATED",escalated.data().get("status").asString());
  assertEquals(403,arbitrate(aid,2,"REJECTED",null,key()).status());
  var queue=read("/admin/aftersales?status=PLATFORM_ESCALATED",admin);assertEquals(200,queue.status());assertTrue(queue.body().get("data").toString().contains(aid));
  var ruled=arbitrate(aid,2,"REJECTED",proof("aftersale.arbitrate"),key());assertEquals(200,ruled.status(),ruled.body().toString());assertEquals("REJECTED",ruled.data().get("status").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='AFTERSALE' AND status='RELEASED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM aftersale_decisions WHERE aftersale_id=? AND decision='REJECTED'",Integer.class,UUID.fromString(aid)));
  assertEquals(409,escalate(f,aid,3,key()).status());
  assertEquals(200,applyRefundOnly(f,1,key()).status());
 }
 @Test void platformArbitrationApprovesOriginalRouteRefund(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);
  String aid=applyRefundOnly(f,1,key()).id();assertEquals(200,decide(merchant,aid,0,"REJECT",key()).status());assertEquals(200,escalate(f,aid,1,key()).status());
  var ruled=arbitrate(aid,2,"REFUND_APPROVED",proof("aftersale.arbitrate"),key());assertEquals(200,ruled.status(),ruled.body().toString());
  assertEquals("COMPLETED",ruled.data().get("status").asString());assertEquals("SUCCEEDED",ruled.data().get("refund").get("status").asString());
  assertEquals(1000,db.queryForObject("SELECT amount_fen FROM aftersale_decisions WHERE aftersale_id=?",Long.class,UUID.fromString(aid)));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='aftersale.arbitrate' AND object_id=?",Integer.class,aid));
 }
 @Test void arbitrationReverifyActionIsAllowlisted(){
  var r=req("POST","/admin/auth/reverify",Map.of("action","aftersale.arbitrate","password","TEST-ONLY wrong password","totp_code","000000"),admin,Map.of());
  assertNotEquals("REVERIFY_ACTION_NOT_ALLOWED",r.body().get("error").get("code").asText(),r.body().toString());
 }
 @Test void concurrentAfterSaleApplicationsCannotExceedShippedQuantity()throws Exception{var f=paid(1,List.of());String h=ship(f,1);receive(f,h);
  var pool=Executors.newFixedThreadPool(2);try{var start=new CountDownLatch(1);Callable<Response> work=()->{start.await();return applyRefundOnly(f,1,key());};var x=pool.submit(work);var y=pool.submit(work);start.countDown();var statuses=List.of(x.get(20,TimeUnit.SECONDS).status(),y.get(20,TimeUnit.SECONDS).status());assertTrue(statuses.contains(200),statuses.toString());assertTrue(statuses.contains(409),statuses.toString());assertEquals(1,db.queryForObject("SELECT count(*) FROM aftersales WHERE suborder_id=?",Integer.class,UUID.fromString(sub(f))));}finally{pool.shutdownNow();}
 }
 @Test void crossRealmAndScopeBoundariesHold(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);String aid=applyRefundOnly(f,1,key()).id();
  String other=consumer();assertEquals(404,aftersale(other,"consumer",aid).status());
  assertEquals(404,decide(foreign,aid,0,"REJECT",key()).status());
  assertEquals(403,decide(colleague,aid,0,"REJECT",key()).status());
  assertEquals(403,decide(f.u(),aid,0,"REJECT",key()).status());
  assertEquals(403,read("/admin/aftersales",f.u()).status());
  assertEquals(200,aftersale(admin,"admin",aid).status());
 }
 @Test void staleVersionAndMissingPreconditionRejected(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);String aid=applyRefundOnly(f,1,key()).id();
  assertEquals(428,req("POST","/merchant/aftersales/"+aid+"/decide",Map.of("action","REJECT","reason","TEST-ONLY"),merchant,Map.of("Idempotency-Key",key())).status());
  assertEquals(409,decide(merchant,aid,7,"REJECT",key()).status());
  assertEquals("PENDING_MERCHANT",aftersale(f.u(),"consumer",aid).data().get("status").asString());
 }
 @Test void idempotentApplyReplaysSameAfterSale(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);String k=key();
  var first=applyRefundOnly(f,1,k);var second=applyRefundOnly(f,1,k);
  assertEquals(200,first.status());assertEquals(200,second.status());assertEquals(first.id(),second.id());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM aftersales WHERE suborder_id=?",Integer.class,UUID.fromString(sub(f))));
 }
 @Test void auditFailureRollsBackDecisionRefundAndClaimChanges(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);String aid=applyRefundOnly(f,1,key()).id();
  db.execute("CREATE FUNCTION fail_m45_decide_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='aftersale.decide' THEN RAISE EXCEPTION 'TEST fault';END IF; RETURN NEW; END $$");
  db.execute("CREATE TRIGGER fail_m45_decide_audit BEFORE INSERT ON audit_event FOR EACH ROW EXECUTE FUNCTION fail_m45_decide_audit()");
  try{assertEquals(503,decide(merchant,aid,0,"APPROVE_REFUND",key()).status());}finally{db.execute("DROP TRIGGER fail_m45_decide_audit ON audit_event");db.execute("DROP FUNCTION fail_m45_decide_audit()");}
  assertEquals("PENDING_MERCHANT",db.queryForObject("SELECT status FROM aftersales WHERE id=?",String.class,UUID.fromString(aid)));
  assertEquals(0,db.queryForObject("SELECT count(*) FROM refunds WHERE aftersale_id=?",Integer.class,UUID.fromString(aid)));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='AFTERSALE' AND status='RESERVED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
  assertEquals(200,decide(merchant,aid,0,"APPROVE_REFUND",key()).status());
  assertEquals("COMPLETED",aftersale(f.u(),"consumer",aid).data().get("status").asString());
 }
 @Test void databaseGuardsRejectTampering(){var f=paid(2,List.of());var created=cancelPaid(f.u(),f,1,key());assertEquals(200,created.status());
  UUID cid=UUID.fromString(created.id());UUID rid=UUID.fromString(created.data().get("refund").get("id").asString());
  assertThrows(Exception.class,()->db.update("UPDATE refunds SET amount_fen=1 WHERE id=?",rid));
  assertThrows(Exception.class,()->db.update("UPDATE refunds SET status='SUCCEEDED' WHERE id=?",rid));
  assertThrows(Exception.class,()->db.update("UPDATE order_refund_unit_claims SET unit_index=unit_index+1 WHERE refund_id=?",rid));
  assertThrows(Exception.class,()->db.update("UPDATE order_items SET cancelled_qty=0 WHERE id=?",UUID.fromString(item(f))));
  assertThrows(Exception.class,()->db.update("DELETE FROM order_cancellations WHERE id=?",cid));
  assertThrows(Exception.class,()->db.update("INSERT INTO order_refund_unit_claims(id,order_item_id,unit_index,source_type,source_item_id,status) SELECT ?,order_item_id,unit_index,'CANCELLATION',?,'RESERVED' FROM order_refund_unit_claims WHERE refund_id=?",UUID.randomUUID(),UUID.randomUUID(),rid));
  assertThrows(Exception.class,()->db.update("UPDATE order_cancellation_items SET quantity=1 WHERE cancellation_id=?",cid));
 }
 @Test void afterSaleCancelledByConsumerReleasesOccupation(){var f=paid(2,List.of());String h=ship(f,2);receive(f,h);
  String aid=applyReturn(f,1,key()).id();assertEquals(200,decide(merchant,aid,0,"APPROVE_RETURN",key()).status());
  var cancelled=req("POST","/consumer/aftersales/"+aid+"/cancel",Map.of(),f.u(),Map.of("Idempotency-Key",key(),"If-Match","\"1\""));assertEquals(200,cancelled.status(),cancelled.body().toString());assertEquals("CANCELLED",cancelled.data().get("status").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE source_type='AFTERSALE' AND status='RELEASED' AND order_item_id=?",Integer.class,UUID.fromString(item(f))));
  assertEquals(200,applyReturn(f,1,key()).status());
 }
 @AfterAll static void finish()throws Exception{Files.writeString(Path.of("target/m45-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
}
