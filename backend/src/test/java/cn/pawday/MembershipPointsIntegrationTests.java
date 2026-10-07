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
class MembershipPointsIntegrationTests {
 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.simulation-enabled",()->true);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);r.add("pawday.membership.worker-enabled",()->false);}
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

 String key(){return UUID.randomUUID().toString();}
 String identity(String realm,UUID m,List<String> permissions){UUID p=UUID.randomUUID(),role=UUID.randomUUID();if(realm.equals("CONSUMER")){UUID u=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",u);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",p,u);}else db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,?,?,?,?,?)",p,realm,m,key(),"TEST-ONLY",realm.equals("ADMIN")?crypto.encrypt(new byte[20]):null);
  db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,'Membership test')",role,realm,key());for(String permission:permissions)db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code=?",role,permission);db.update("INSERT INTO principal_role VALUES (?,?,?)",p,role,realm);UUID session=UUID.randomUUID();String t=crypto.token();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'M51-IT',?,?,?)",session,p,crypto.hash(t),Timestamp.from(clock.instant().plusSeconds(86400*40)),Timestamp.from(clock.instant().plusSeconds(86400*40)),Timestamp.from(clock.instant()));if(realm.equals("ADMIN")){adminSession=session;adminPrincipal=p;}if(realm.equals("MERCHANT"))db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",p,m,store);return t;
 }
 @BeforeEach void setup(){merchantId=UUID.randomUUID();store=UUID.randomUUID();db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE')",merchantId,key());db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST scope')",store,merchantId);
  admin=identity("ADMIN",null,List.of("offer.admin.manage","order.admin.read","payment.read","membership.plan.manage","points.policy.manage","points.reward.manage","points.adjust","points.read"));merchant=identity("MERCHANT",merchantId,List.of("offer.read","offer.write","inventory.adjust","order.read","order.default-scope"));
  UUID brand=UUID.randomUUID(),spu=UUID.randomUUID(),k=UUID.randomUUID();sku=k.toString();db.update("INSERT INTO brands(id,name,source_ref) VALUES (?,?,'TEST-ONLY')",brand,key());db.update("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES (?,?,'TEST-ONLY','CAT','DRY_FOOD')",spu,brand);db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES (?,?,?,1000,'BAG')",k,spu,key());db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) VALUES (?,?,1,'PUBLISHED','[\"TEST-ONLY\"]','[]',false,'[]','[\"TEST-ONLY source\"]','2026-10-01',?,clock_timestamp())",UUID.randomUUID(),k,adminPrincipal);
 }
 Response req(String method,String path,Object payload,String token,Map<String,String> headers){try{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));var response=http.send(b.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",body));return new Response(response.statusCode(),body);}catch(Exception e){throw new AssertionError(e);}}
 Response read(String path,String token){return req("GET",path,null,token,Map.of());}
 String consumer(){return identity("CONSUMER",null,List.of());}
 String proof(String action){String p=crypto.token();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(p),adminSession,action,Timestamp.from(clock.instant().plusSeconds(300)),Timestamp.from(clock.instant()));return p;}
 String userIdOf(String token){return read("/consumer/me",token).data().get("user_id").asString();}

 /** Buy a plan through the shared simulated payment pipeline and return the PAID membership order. */
 Response buyMembership(String u,String planCode){
  var created=req("POST","/consumer/membership/orders",Map.of("plan_code",planCode),u,Map.of("Idempotency-Key",key()));assertEquals(200,created.status(),created.body().toString());
  String payment=created.data().get("payment").get("id").asString();
  var attempt=req("POST","/consumer/payments/"+payment+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));assertEquals(200,attempt.status(),attempt.body().toString());
  var paid=req("POST","/consumer/payments/"+payment+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of());assertEquals(200,paid.status(),paid.body().toString());
  assertEquals("SUCCEEDED",paid.data().get("status").asString());
  return req("GET","/consumer/membership/orders/"+created.id(),null,u,Map.of());
 }
 long balance(String u){return read("/consumer/points",u).data().get("balance").asLong();}

 @Test void purchaseActivatesMembershipAndRenewalExtendsFromCurrentExpiry(){
  String u=consumer();
  var plans=read("/consumer/membership/plans",u);assertEquals(200,plans.status(),plans.body().toString());assertEquals(2,plans.body().get("data").size());
  assertEquals("NONE",read("/consumer/membership",u).data().get("effective_status").asString());
  var first=buyMembership(u,"MEMBER_MONTH");assertEquals("PAID",first.data().get("status").asString(),first.body().toString());
  var current=read("/consumer/membership",u);assertEquals("ACTIVE",current.data().get("effective_status").asString());
  var firstExpiry=Instant.parse(current.data().get("expires_at").asString());
  assertTrue(firstExpiry.isAfter(clock.instant().plusSeconds(25L*86400)),"month plan should last roughly a month");
  clock.advance(3*86400);
  var second=buyMembership(u,"MEMBER_YEAR");assertEquals("PAID",second.data().get("status").asString());
  var renewed=read("/consumer/membership",u).data();
  var renewedExpiry=Instant.parse(renewed.get("expires_at").asString());
  assertTrue(renewedExpiry.isAfter(firstExpiry.plusSeconds(360L*86400)),"renewal must extend from the previous expiry, not from now: "+renewedExpiry);
  assertEquals(2,db.queryForObject("SELECT count(*) FROM membership_orders WHERE user_id=? AND status='PAID'",Integer.class,UUID.fromString(userIdOf(u))));
  assertEquals(2,read("/consumer/membership/orders",u).body().get("data").size());
  var snapshot=json.readTree(db.queryForObject("SELECT plan_snapshot::text FROM membership_orders WHERE id=?",String.class,UUID.fromString(first.id())));
  long currentPrice=db.queryForObject("SELECT price_fen FROM membership_plans WHERE code='MEMBER_MONTH' ORDER BY plan_version DESC LIMIT 1",Long.class);
  assertEquals(currentPrice,snapshot.get("price_fen").asLong());
  assertEquals(2,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='MembershipActivated' AND aggregate_id=?",Integer.class,userIdOf(u)));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='membership.activate' AND object_id=?",Integer.class,first.id()));
 }
 @Test void membershipPaymentUsesSharedPipelineWithoutGoodsSideEffects(){
  String u=consumer();
  var created=req("POST","/consumer/membership/orders",Map.of("plan_code","MEMBER_MONTH"),u,Map.of("Idempotency-Key",key()));
  String payment=created.data().get("payment").get("id").asString();
  var view=read("/consumer/payments/"+payment,u);assertEquals(200,view.status(),view.body().toString());
  long monthPrice=db.queryForObject("SELECT price_fen FROM membership_plans WHERE code='MEMBER_MONTH' ORDER BY plan_version DESC LIMIT 1",Long.class);
  assertEquals(monthPrice,view.data().get("amount_fen").asLong());
  assertTrue(view.data().get("simulation").asBoolean());
  var attempt=req("POST","/consumer/payments/"+payment+"/attempts",Map.of("channel","ALIPAY","client_platform","WEB"),u,Map.of("Idempotency-Key",key()));assertEquals(200,attempt.status());
  int tracksBefore=db.queryForObject("SELECT count(*) FROM settlement_tracks",Integer.class);
  int ledgerBefore=db.queryForObject("SELECT count(*) FROM merchant_ledger_entries",Integer.class);
  int earnBefore=db.queryForObject("SELECT count(*) FROM points_ledger WHERE entry_type='PURCHASE_EARN'",Integer.class);
  var paid=req("POST","/consumer/payments/"+payment+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of());
  assertEquals("SUCCEEDED",paid.data().get("status").asString());assertEquals("ALIPAY",paid.data().get("final_channel").asString());
  assertEquals(tracksBefore,db.queryForObject("SELECT count(*) FROM settlement_tracks",Integer.class),"membership payments must not open settlement tracks");
  assertEquals(ledgerBefore,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries",Integer.class));
  assertEquals(earnBefore,db.queryForObject("SELECT count(*) FROM points_ledger WHERE entry_type='PURCHASE_EARN'",Integer.class),"membership purchases do not earn goods points");
  assertEquals("ACTIVE",read("/consumer/membership",u).data().get("effective_status").asString());
  var other=consumer();assertEquals(404,read("/consumer/payments/"+payment,other).status());
  assertEquals(404,read("/consumer/membership/orders/"+created.id(),other).status());
 }
 @Test void membershipEligibilityUnlocksMemberPriceInQuote(){
  String u=consumer();
  assertFalse(read("/consumer/checkout/benefits",u).data().get("membership_eligible").asBoolean());
  buyMembership(u,"MEMBER_MONTH");
  assertTrue(read("/consumer/checkout/benefits",u).data().get("membership_eligible").asBoolean());
  var offer=req("POST","/merchant/offers",new LinkedHashMap<String,Object>(Map.of("sku_id",sku,"sale_price_fen",1000,"member_price_fen",900,"fulfillment_sla","TEST-ONLY 48h")){{put("store_id",store.toString());}},merchant,Map.of("Idempotency-Key",key()));assertEquals(201,offer.status(),offer.body().toString());
  assertEquals(201,req("POST","/merchant/offers/"+offer.id()+"/inventory-adjustments",Map.of("delta_qty",5,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());
  assertEquals(200,req("POST","/merchant/offers/"+offer.id()+"/activate",Map.of("reason","TEST-ONLY lifecycle"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());
  var cart=req("POST","/consumer/cart/items",Map.of("offer_id",offer.id(),"quantity",1),u,Map.of("Idempotency-Key",key()));
  var address=req("POST","/consumer/addresses",Map.of("recipient","TEST recipient","phone","13800000000","province_code","310000","city_code","310100","district_code","310101","detail","TEST-only address"),u,Map.of("Idempotency-Key",key()));
  int v=db.queryForObject("SELECT coalesce(max(version_no),0)+1 FROM shipping_rule_versions WHERE merchant_id=?",Integer.class,merchantId);
  db.update("INSERT INTO shipping_rule_versions(id,merchant_id,version_no,province_codes,base_fen,per_kg_fen,free_threshold_fen,created_by) VALUES (?,?,?,'[\"310000\"]',300,100,NULL,?)",UUID.randomUUID(),merchantId,v,adminPrincipal);
  var plain=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",List.of(cart.id()),"address_id",address.id(),"coupon_ids",List.of(),"use_membership",false),u,Map.of("Idempotency-Key",key()));
  assertEquals(200,plain.status(),plain.body().toString());
  var member=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",List.of(cart.id()),"address_id",address.id(),"coupon_ids",List.of(),"use_membership",true),u,Map.of("Idempotency-Key",key()));
  assertEquals(200,member.status(),member.body().toString());
  assertTrue(member.data().get("membership_snapshot").get("used").asBoolean());
  assertEquals(100,plain.data().get("payable_amount_fen").asInt()-member.data().get("payable_amount_fen").asInt(),"member price is exactly 100 fen lower");
 }
 @Test void unpaidMembershipOrderExpires(){
  String u=consumer();
  var created=req("POST","/consumer/membership/orders",Map.of("plan_code","MEMBER_YEAR"),u,Map.of("Idempotency-Key",key()));
  clock.advance(901);
  assertEquals(1,memberships.expireBatch());
  var view=req("GET","/consumer/membership/orders/"+created.id(),null,u,Map.of());
  assertEquals(200,view.status(),view.body().toString());
  assertEquals("EXPIRED",view.data().get("status").asString());
  assertEquals("CLOSED",view.data().get("payment").get("status").asString());
  assertEquals("NONE",read("/consumer/membership",u).data().get("effective_status").asString());
  assertEquals(0,memberships.expireBatch());
 }
 @Test void goodsPaymentEarnsPointsAtPolicyRate(){
  String u=consumer();
  var fixture=paidGoods(u,2);
  var o=db.queryForMap("SELECT payable_amount_fen,shipping_amount_fen FROM orders WHERE id=(SELECT order_id FROM payments WHERE id=?)",UUID.fromString(fixture.payment()));
  long rate=db.queryForObject("SELECT earn_points_per_yuan FROM points_policies ORDER BY policy_version DESC LIMIT 1",Long.class);
  long expected=Math.max(0,((Number)o.get("payable_amount_fen")).longValue()-((Number)o.get("shipping_amount_fen")).longValue())/100*rate;
  assertEquals(expected,balance(u));
  var entry=db.queryForMap("SELECT * FROM points_ledger WHERE user_id=?",UUID.fromString(userIdOf(u)));
  assertEquals("PURCHASE_EARN",entry.get("entry_type"));assertEquals("PURCHASE:"+fixture.payment(),entry.get("business_key"));
  int currentPolicy=db.queryForObject("SELECT policy_version FROM points_policies ORDER BY policy_version DESC LIMIT 1",Integer.class);
  assertEquals(currentPolicy,((Number)entry.get("policy_version")).intValue());
  var overview=read("/consumer/points",u);assertEquals(200,overview.status());assertEquals(currentPolicy,overview.data().get("policy").get("policy_version").asInt());
  var ledger=read("/consumer/points/ledger?entry_type=PURCHASE_EARN",u);assertEquals(200,ledger.status());assertEquals(1,ledger.body().get("data").size());
 }
 @Test void refundClawbackCanDriveBalanceNegativeAndBlocksRedemption(){
  String u=consumer();
  var fixture=paidGoods(u,1);
  long earned=balance(u);assertTrue(earned>0);
  var h=new HashMap<String,String>(Map.of());h.put("X-Reverify-Token",proof("points.reward.manage"));
  var reward=req("POST","/admin/points-rewards",Map.of("code","TEST-TREAT","name","TEST-ONLY treat","cost_points",earned,"status","ACTIVE"),admin,h);assertEquals(200,reward.status(),reward.body().toString());
  var redeemed=req("POST","/consumer/points/redemptions",Map.of("reward_id",reward.id()),u,Map.of("Idempotency-Key",key()));assertEquals(200,redeemed.status(),redeemed.body().toString());
  assertEquals(0,balance(u));
  var cancel=req("POST","/consumer/suborders/"+fixture.subId()+"/cancellations",Map.of("reason_code","CONSUMER_CANCELLED","items",List.of(Map.of("order_item_id",fixture.itemId(),"quantity",1))),u,Map.of("Idempotency-Key",key()));assertEquals(200,cancel.status(),cancel.body().toString());
  assertEquals(-earned,balance(u),"clawback overtakes spent points and keeps a negative balance");
  var entry=db.queryForMap("SELECT * FROM points_ledger WHERE entry_type='REFUND_CLAWBACK' AND user_id=?",UUID.fromString(userIdOf(u)));
  String refundId=db.queryForObject("SELECT id FROM refunds WHERE cancellation_id=?",String.class,UUID.fromString(cancel.id()));
  assertEquals(-earned,((Number)entry.get("points")).longValue());assertEquals("CLAWBACK:"+refundId,entry.get("business_key"));
  assertEquals(422,req("POST","/consumer/points/redemptions",Map.of("reward_id",reward.id()),u,Map.of("Idempotency-Key",key())).status());
 }
 @Test void checkinOncePerDayWithStreakCycle(){
  String u=consumer();
  int perDay=db.queryForObject("SELECT checkin_points FROM points_policies ORDER BY policy_version DESC LIMIT 1",Integer.class);
  String k=key();
  var first=req("POST","/consumer/points/checkins",null,u,Map.of("Idempotency-Key",k));assertEquals(200,first.status(),first.body().toString());
  assertEquals(1,first.data().get("cycle_day").asInt());assertEquals(perDay,first.data().get("points").asInt());
  var replay=req("POST","/consumer/points/checkins",null,u,Map.of("Idempotency-Key",k));assertEquals(200,replay.status());assertEquals(first.id(),replay.id());
  assertEquals(409,req("POST","/consumer/points/checkins",null,u,Map.of("Idempotency-Key",key())).status());
  assertEquals(perDay,balance(u));
  clock.advance(86400);
  var second=req("POST","/consumer/points/checkins",null,u,Map.of("Idempotency-Key",key()));assertEquals(200,second.status());assertEquals(2,second.data().get("cycle_day").asInt());
  assertEquals(2L*perDay,balance(u));
  var checkins=read("/consumer/points/checkins",u);assertEquals(200,checkins.status());assertEquals(2,checkins.body().get("data").size());
  assertTrue(read("/consumer/points",u).data().get("checked_in_today").asBoolean());
 }
 @Test void adminManagementRequiresReverifyPermissionAndStaysIdempotent(){
  String u=consumer();
  assertEquals(403,req("POST","/admin/points-policies",Map.of("earn_points_per_yuan",2,"checkin_points",5,"checkin_cycle_days",30),admin,Map.of()).status());
  assertEquals(403,read("/admin/points-policies",u).status());
  assertEquals(403,read("/consumer/points",admin).status());
  assertEquals(403,read("/consumer/membership/plans",merchant).status());
  var hp=new HashMap<String,String>(Map.of());hp.put("X-Reverify-Token",proof("points.policy.manage"));
  var policy=req("POST","/admin/points-policies",Map.of("earn_points_per_yuan",2,"checkin_points",6,"checkin_cycle_days",30),admin,hp);assertEquals(200,policy.status(),policy.body().toString());
  assertEquals(2,policy.data().get("policy_version").asInt());
  var hw=new HashMap<String,String>(Map.of());hw.put("X-Reverify-Token",proof("points.reward.manage"));
  assertEquals(200,req("POST","/admin/points-rewards",Map.of("code","TEST-COMBO","name","TEST-ONLY combo","cost_points",50,"status","ACTIVE"),admin,hw).status());
  assertEquals(200,req("POST","/admin/points-rewards",Map.of("code","TEST-COMBO","name","TEST-ONLY combo retired","cost_points",50,"status","RETIRED"),admin,new HashMap<String,String>(Map.of("X-Reverify-Token",proof("points.reward.manage")))).status());
  assertTrue(read("/consumer/points/rewards",u).body().get("data").isEmpty(),"retired latest version hides the reward");
  var hm=new HashMap<String,String>(Map.of());hm.put("X-Reverify-Token",proof("membership.plan.manage"));
  var plan=req("POST","/admin/membership-plans",Map.of("code","MEMBER_MONTH","name","月度会员","term","MONTH","price_fen",1800,"ai_quota",30,"benefits",List.of("会员价"),"status","ACTIVE"),admin,hm);assertEquals(200,plan.status(),plan.body().toString());
  assertEquals(1800,plan.data().get("price_fen").asInt());
  var plans=read("/consumer/membership/plans",u);
  long monthPrice=0;for(var node:plans.body().get("data"))if(node.get("code").asString().equals("MEMBER_MONTH"))monthPrice=node.get("price_fen").asLong();
  assertEquals(1800,monthPrice,"consumer sees the newer plan version");
  assertEquals(200,read("/admin/points-policies",admin).status());
  assertEquals(200,read("/admin/points-rewards",admin).status());
  assertEquals(200,read("/admin/membership-plans",admin).status());
  String uid=userIdOf(u);String k=key();var ha=new HashMap<String,String>(Map.of("Idempotency-Key",k));ha.put("X-Reverify-Token",proof("points.adjust"));
  var adjusted=req("POST","/admin/users/"+uid+"/points-adjustments",Map.of("points",25,"reason","TEST-ONLY goodwill"),admin,ha);assertEquals(200,adjusted.status(),adjusted.body().toString());
  var replay=req("POST","/admin/users/"+uid+"/points-adjustments",Map.of("points",25,"reason","TEST-ONLY goodwill"),admin,ha);assertEquals(200,replay.status());assertEquals(adjusted.id(),replay.id());
  assertEquals(25,balance(u));
  assertEquals(25,read("/admin/users/"+uid+"/points",admin).data().get("balance").asInt());
  assertEquals(1,read("/admin/users/"+uid+"/points/ledger",admin).body().get("data").size());
  assertEquals(403,read("/admin/users/"+uid+"/points",u).status());
 }
 @Test void databaseGuardsRejectTamperingAndOrphanPayments(){
  String u=consumer();var fixture=paidGoods(u,1);
  UUID entry=db.queryForObject("SELECT id FROM points_ledger WHERE user_id=?",UUID.class,UUID.fromString(userIdOf(u)));
  assertThrows(Exception.class,()->db.update("UPDATE points_ledger SET points=9999 WHERE id=?",entry));
  assertThrows(Exception.class,()->db.update("DELETE FROM points_ledger WHERE id=?",entry));
  assertThrows(Exception.class,()->db.update("INSERT INTO points_ledger(id,user_id,entry_type,points,business_key,created_by_type) VALUES (?,?,'PURCHASE_EARN',-5,?,'SYSTEM')",UUID.randomUUID(),UUID.fromString(userIdOf(u)),key()));
  assertThrows(Exception.class,()->db.update("UPDATE membership_plans SET price_fen=1 WHERE code='MEMBER_MONTH'"));
  var paidOrders=db.queryForList("SELECT id FROM membership_orders WHERE status='PAID' LIMIT 1",UUID.class);
  if(!paidOrders.isEmpty())assertThrows(Exception.class,()->db.update("UPDATE membership_orders SET status='CANCELLED',version=version+1 WHERE status='PAID' AND id=?",paidOrders.getFirst()));
  assertThrows(Exception.class,()->db.update("INSERT INTO payments(id,payment_no,amount_fen,currency,expires_at) VALUES (?,?,1,'CNY',clock_timestamp())",UUID.randomUUID(),key()));
 }
 @Test void validationRejectsMalformedRequests(){
  String u=consumer();
  assertEquals(400,req("POST","/consumer/membership/orders",Map.of("plan_code","MEMBER_MONTH","extra",1),u,Map.of("Idempotency-Key",key())).status());
  assertEquals(404,req("POST","/consumer/membership/orders",Map.of("plan_code","NOPE"),u,Map.of("Idempotency-Key",key())).status());
  assertEquals(400,req("POST","/consumer/membership/orders",Map.of("plan_code","MEMBER_MONTH"),u,Map.of()).status());
  assertEquals(400,req("POST","/consumer/points/redemptions",Map.of("reward_id","not-a-uuid"),u,Map.of("Idempotency-Key",key())).status());
  assertEquals(404,req("POST","/consumer/points/redemptions",Map.of("reward_id",UUID.randomUUID().toString()),u,Map.of("Idempotency-Key",key())).status());
  assertEquals(400,read("/consumer/points/ledger?entry_type=BOGUS",u).status());
 }

 /** Goods purchase fixture: 1000 fen unit price, 300 flat shipping, simulated WECHAT payment. */
 record GoodsFixture(String payment,String subId,String itemId,long payable){}
 GoodsFixture paidGoods(String u,int qty){
  var offer=req("POST","/merchant/offers",new LinkedHashMap<String,Object>(Map.of("sku_id",sku,"sale_price_fen",1000,"member_price_fen",900,"fulfillment_sla","TEST-ONLY 48h")){{put("store_id",store.toString());}},merchant,Map.of("Idempotency-Key",key()));assertEquals(201,offer.status(),offer.body().toString());
  assertEquals(201,req("POST","/merchant/offers/"+offer.id()+"/inventory-adjustments",Map.of("delta_qty",20,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());
  assertEquals(200,req("POST","/merchant/offers/"+offer.id()+"/activate",Map.of("reason","TEST-ONLY lifecycle"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());
  int v=db.queryForObject("SELECT coalesce(max(version_no),0)+1 FROM shipping_rule_versions WHERE merchant_id=?",Integer.class,merchantId);
  db.update("INSERT INTO shipping_rule_versions(id,merchant_id,version_no,province_codes,base_fen,per_kg_fen,free_threshold_fen,created_by) VALUES (?,?,?,'[\"310000\"]',300,100,NULL,?)",UUID.randomUUID(),merchantId,v,adminPrincipal);
  var cart=req("POST","/consumer/cart/items",Map.of("offer_id",offer.id(),"quantity",qty),u,Map.of("Idempotency-Key",key()));
  var address=req("POST","/consumer/addresses",Map.of("recipient","TEST recipient","phone","13800000000","province_code","310000","city_code","310100","district_code","310101","detail","TEST-only address"),u,Map.of("Idempotency-Key",key()));
  var quote=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",List.of(cart.id()),"address_id",address.id(),"coupon_ids",List.of(),"use_membership",false),u,Map.of("Idempotency-Key",key()));assertEquals(200,quote.status(),quote.body().toString());
  var order=req("POST","/consumer/orders",Map.of("quote_id",quote.data().get("quote_id").asString()),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());
  String payment=order.data().get("payment").get("id").asString();
  var attempt=req("POST","/consumer/payments/"+payment+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));
  assertEquals(200,req("POST","/consumer/payments/"+payment+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());
  return new GoodsFixture(payment,order.data().get("suborders").get(0).get("id").asString(),order.data().get("suborders").get(0).get("items").get(0).get("id").asString(),order.data().get("payable_amount_fen").asLong());
 }
 @AfterAll static void finish()throws Exception{Files.writeString(Path.of("target/m51-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
}
