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
class SettlementIntegrationTests {
 static final EmbeddedPostgres PG;
 static {try{PG=EmbeddedPostgres.builder().setPort(0).start();}catch(Exception e){throw new ExceptionInInitializerError(e);}}
 @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("spring.datasource.url",()->PG.getJdbcUrl("postgres","postgres"));r.add("spring.datasource.username",()->"postgres");r.add("spring.datasource.password",()->"postgres");r.add("pawday.auth.secret-key",()->"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=");r.add("management.health.redis.enabled",()->false);r.add("management.health.rabbit.enabled",()->false);r.add("pawday.outbox.workers-enabled",()->false);r.add("pawday.outbox.consumer-enabled",()->false);r.add("pawday.search.enabled",()->false);r.add("pawday.storage.cleanup-enabled",()->false);r.add("pawday.checkout.expiry-enabled",()->false);r.add("pawday.ordering.expiry-enabled",()->false);r.add("pawday.payment.simulation-enabled",()->true);r.add("pawday.payment.recovery-enabled",()->false);r.add("pawday.refund.recovery-enabled",()->false);r.add("pawday.settlement.worker-enabled",()->false);}
 @Autowired JdbcTemplate db;@Autowired Crypto crypto;@Autowired Clock clock;@LocalServerPort int port;
 @Autowired cn.pawday.settlement.SettlementService settlements;
 @Autowired org.springframework.transaction.support.TransactionTemplate tx;
 final JsonMapper json=JsonMapper.builder().build();final HttpClient http=HttpClient.newHttpClient();
 static final List<Map<String,Object>> SAMPLES=new CopyOnWriteArrayList<>();
 String admin,merchant,colleague,foreign;UUID adminSession,adminPrincipal,merchantId,store,foreignMerchant;String sku;
 record Response(int status,JsonNode body){JsonNode data(){return body.get("data");}String id(){return data().get("id").asString();}}

 String key(){return UUID.randomUUID().toString();}
 String identity(String realm,UUID m,List<String> permissions){UUID p=UUID.randomUUID(),role=UUID.randomUUID();if(realm.equals("CONSUMER")){UUID u=UUID.randomUUID();db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE')",u);db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",p,u);}else db.update("INSERT INTO identity_principal(id,realm,merchant_id,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,?,?,?,?,?)",p,realm,m,key(),"TEST-ONLY",realm.equals("ADMIN")?crypto.encrypt(new byte[20]):null);
  db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,?,?,'Settlement test')",role,realm,key());for(String permission:permissions)db.update("INSERT INTO role_permission SELECT ?,id FROM permission WHERE code=?",role,permission);db.update("INSERT INTO principal_role VALUES (?,?,?)",p,role,realm);UUID session=UUID.randomUUID();String t=crypto.token();db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'SETTLEMENT-IT',?,?,?)",session,p,crypto.hash(t),Timestamp.from(clock.instant().plusSeconds(900)),Timestamp.from(clock.instant().plusSeconds(2592000)),Timestamp.from(clock.instant()));if(realm.equals("ADMIN")){adminSession=session;adminPrincipal=p;}if(realm.equals("MERCHANT"))db.update("INSERT INTO principal_store_scope VALUES (?,?,?)",p,m,store);return t;
 }
 void newSku(){UUID brand=UUID.randomUUID(),spu=UUID.randomUUID(),k=UUID.randomUUID();sku=k.toString();db.update("INSERT INTO brands(id,name,source_ref) VALUES (?,?,'TEST-ONLY')",brand,key());db.update("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES (?,?,'TEST-ONLY','CAT','DRY_FOOD')",spu,brand);db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES (?,?,?,1000,'BAG')",k,spu,key());db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) VALUES (?,?,1,'PUBLISHED','[\"TEST-ONLY\"]','[]',false,'[]','[\"TEST-ONLY source\"]','2026-10-01',?,clock_timestamp())",UUID.randomUUID(),k,adminPrincipal);}
 @BeforeEach void setup(){merchantId=UUID.randomUUID();store=UUID.randomUUID();db.update("INSERT INTO merchant(id,name,status) VALUES (?,?,'ACTIVE')",merchantId,key());db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST scope')",store,merchantId);
  admin=identity("ADMIN",null,List.of("offer.admin.manage","order.admin.read","payment.read","aftersale.arbitrate","settlement.read","settlement.execute","settlement.policy.manage","ledger.read","ledger.adjust"));merchant=identity("MERCHANT",merchantId,List.of("offer.read","offer.write","inventory.adjust","order.read","order.ship","order.default-scope","order.cancel.handle","aftersale.handle","settlement.read","ledger.read"));colleague=identity("MERCHANT",merchantId,List.of("order.read","order.default-scope"));foreignMerchant=UUID.randomUUID();db.update("INSERT INTO merchant VALUES (?,'TEST foreign','ACTIVE')",foreignMerchant);UUID saved=store;store=UUID.randomUUID();db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST foreign store')",store,foreignMerchant);foreign=identity("MERCHANT",foreignMerchant,List.of("order.read","settlement.read","ledger.read"));store=saved;
  newSku();
 }
 Response req(String method,String path,Object payload,String token,Map<String,String> headers){try{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));if(token!=null)b.header("Authorization","Bearer "+token);headers.forEach(b::header);if(payload==null)b.method(method,HttpRequest.BodyPublishers.noBody());else b.header("Content-Type","application/json").method(method,HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)));var response=http.send(b.build(),HttpResponse.BodyHandlers.ofString());var body=json.readTree(response.body());SAMPLES.add(Map.of("method",method.toLowerCase(),"path",path,"status",response.statusCode(),"response",body));return new Response(response.statusCode(),body);}catch(Exception e){throw new AssertionError(e);}}
 Response read(String path,String token){return req("GET",path,null,token,Map.of());}
 String create(){var b=new LinkedHashMap<String,Object>(Map.of("sku_id",sku,"sale_price_fen",1000,"member_price_fen",900,"fulfillment_sla","TEST-ONLY 48h"));b.put("store_id",store.toString());var r=req("POST","/merchant/offers",b,merchant,Map.of("Idempotency-Key",key()));assertEquals(201,r.status(),r.body().toString());return r.id();}
 String ready(){String o=create();assertEquals(201,req("POST","/merchant/offers/"+o+"/inventory-adjustments",Map.of("delta_qty",20,"reason_code","COUNT_CORRECTION","expected_version",0),merchant,Map.of("Idempotency-Key",key())).status());assertEquals(200,req("POST","/merchant/offers/"+o+"/activate",Map.of("reason","TEST-ONLY lifecycle"),merchant,Map.of("Idempotency-Key",key(),"If-Match","\"0\"")).status());return o;}
 String consumer(){return identity("CONSUMER",null,List.of());}
 String addressFor(String u){var r=req("POST","/consumer/addresses",Map.of("recipient","TEST recipient","phone","13800000000","province_code","310000","city_code","310100","district_code","310101","detail","TEST-only address"),u,Map.of("Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());return r.id();}
 void shipping(){int v=db.queryForObject("SELECT coalesce(max(version_no),0)+1 FROM shipping_rule_versions WHERE merchant_id=?",Integer.class,merchantId);db.update("INSERT INTO shipping_rule_versions(id,merchant_id,version_no,province_codes,base_fen,per_kg_fen,free_threshold_fen,created_by) VALUES (?,?,?,'[\"310000\"]',300,100,NULL,?)",UUID.randomUUID(),merchantId,v,adminPrincipal);}
 record Fixture(String u,String offer,Response order,String payment){}
 Fixture paid(int qty){newSku();String u=consumer(),o=ready();shipping();String i=req("POST","/consumer/cart/items",Map.of("offer_id",o,"quantity",qty),u,Map.of("Idempotency-Key",key())).id();String a=addressFor(u);var q=req("POST","/consumer/checkout/quotes",Map.of("cart_item_ids",List.of(i),"address_id",a,"coupon_ids",List.of(),"use_membership",false),u,Map.of("Idempotency-Key",key()));assertEquals(200,q.status(),q.body().toString());var order=req("POST","/consumer/orders",Map.of("quote_id",q.data().get("quote_id").asString()),u,Map.of("Idempotency-Key",key()));assertEquals(200,order.status(),order.body().toString());var f=new Fixture(u,o,order,order.data().get("payment").get("id").asString());var attempt=req("POST","/consumer/payments/"+f.payment()+"/attempts",Map.of("channel","WECHAT","client_platform","ANDROID"),u,Map.of("Idempotency-Key",key()));assertEquals(200,req("POST","/consumer/payments/"+f.payment()+"/simulation",Map.of("attempt_id",attempt.data().get("attempts").get(0).get("id").asString(),"outcome","SUCCEEDED"),u,Map.of()).status());return f;}
 String sub(Fixture f){return f.order().data().get("suborders").get(0).get("id").asString();}
 String item(Fixture f){return f.order().data().get("suborders").get(0).get("items").get(0).get("id").asString();}
 long subVersion(Fixture f){return read("/consumer/suborders/"+sub(f)+"/fulfillment",f.u()).data().get("version").asLong();}
 void shipAndReceive(Fixture f,int qty){var r=req("POST","/merchant/suborders/"+sub(f)+"/shipments",Map.of("carrier_code","SF","tracking_no","TEST"+key().replace("-",""),"items",List.of(Map.of("order_item_id",item(f),"quantity",qty))),merchant,Map.of("If-Match","\""+subVersion(f)+"\"","Idempotency-Key",key()));assertEquals(200,r.status(),r.body().toString());var ships=r.data().get("shipments");String h=ships.get(ships.size()-1).get("id").asString();var receipt=req("POST","/consumer/suborders/"+sub(f)+"/confirm-receipt",Map.of("shipment_ids",List.of(h)),f.u(),Map.of("If-Match","\""+subVersion(f)+"\"","Idempotency-Key",key()));assertEquals(200,receipt.status(),receipt.body().toString());}
 Response cancelPaid(Fixture f,int qty,String k){return req("POST","/consumer/suborders/"+sub(f)+"/cancellations",Map.of("reason_code","CONSUMER_CANCELLED","items",List.of(Map.of("order_item_id",item(f),"quantity",qty))),f.u(),Map.of("Idempotency-Key",k));}
 Response applyRefundOnly(Fixture f,int qty,String k){return req("POST","/consumer/suborders/"+sub(f)+"/aftersales",Map.of("type","REFUND_ONLY","reason_code","QUALITY_ISSUE","reason_text","TEST-ONLY quality concern","items",List.of(Map.of("order_item_id",item(f),"quantity",qty)),"evidence",List.of(Map.of("content","TEST-ONLY photo description"))),f.u(),Map.of("Idempotency-Key",k));}
 Response decide(String id,long v,String action,String k){return req("POST","/merchant/aftersales/"+id+"/decide",Map.of("action",action,"reason","TEST-ONLY merchant decision"),merchant,Map.of("Idempotency-Key",k,"If-Match","\""+v+"\""));}
 String proof(String action){String p=crypto.token();db.update("INSERT INTO reverify_grant(token_hash,session_id,action,expires_at,created_at) VALUES (?,?,?,?,?)",crypto.hash(p),adminSession,action,Timestamp.from(clock.instant().plusSeconds(300)),Timestamp.from(clock.instant()));return p;}
 Response initiate(){var h=new HashMap<String,String>(Map.of("Idempotency-Key",key()));h.put("X-Reverify-Token",proof("settlement.execute"));return req("POST","/admin/merchants/"+merchantId+"/settlements",Map.of(),admin,h);}
 Response retry(String id){var h=new HashMap<String,String>(Map.of("Idempotency-Key",key()));h.put("X-Reverify-Token",proof("settlement.execute"));return req("POST","/admin/settlements/"+id+"/retry",Map.of(),admin,h);}
 void bufferDays(int days){var h=new HashMap<String,String>(Map.of());h.put("X-Reverify-Token",proof("settlement.policy.manage"));var r=req("POST","/admin/settlement-policies",Map.of("buffer_days",days),admin,h);assertEquals(200,r.status(),r.body().toString());}
 long balance(){return read("/admin/merchants/"+merchantId+"/finance-summary",admin).data().get("balance_fen").asLong();}
 String trackStatus(String subId){return db.queryForObject("SELECT status FROM settlement_tracks WHERE suborder_id=?",String.class,UUID.fromString(subId));}
 void assertReconciliationConsistent(){var r=read("/admin/finance/reconciliation",admin);assertEquals(200,r.status(),r.body().toString());assertTrue(r.data().get("consistent").asBoolean(),r.body().toString());}

 @Test void paymentSuccessFreezesCommissionSnapshotAndPostsPendingFacts(){var f=paid(2);
  long itemPayable=db.queryForObject("SELECT payable_amount_fen FROM order_items WHERE id=?",Long.class,UUID.fromString(item(f)));
  long subPayable=db.queryForObject("SELECT payable_amount_fen FROM suborders WHERE id=?",Long.class,UUID.fromString(sub(f)));
  var alloc=db.queryForMap("SELECT * FROM commission_allocations WHERE order_item_id=?",UUID.fromString(item(f)));
  assertEquals(500,((Number)alloc.get("rate_basis_points")).intValue());assertEquals(itemPayable,((Number)alloc.get("base_amount_fen")).longValue());
  long commission=(itemPayable*500+5000)/10000;assertEquals(commission,((Number)alloc.get("commission_fen")).longValue());
  assertEquals(subPayable,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE suborder_id=? AND entry_type='SALE_CREDIT'",Long.class,UUID.fromString(sub(f))));
  assertEquals(commission,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE order_item_id=? AND entry_type='COMMISSION_DEBIT'",Long.class,UUID.fromString(item(f))));
  assertEquals("WAITING_RECEIPT",trackStatus(sub(f)));
  var summary=read("/merchant/finance-summary",merchant);assertEquals(200,summary.status(),summary.body().toString());
  assertEquals(subPayable-commission,summary.data().get("balance_fen").asLong());assertEquals(0,summary.data().get("eligible_fen").asLong());assertEquals(0,summary.data().get("settled_total_fen").asLong());
  assertEquals(409,initiate().status());
  assertReconciliationConsistent();
 }
 @Test void receiptCompletionStartsBufferAndExpiryPromotesWithFrozenPolicySnapshot(){bufferDays(0);var f=paid(1);shipAndReceive(f,1);
  var track=db.queryForMap("SELECT * FROM settlement_tracks WHERE suborder_id=?",UUID.fromString(sub(f)));
  assertEquals("BUFFERING",track.get("status"));assertEquals(0,((Number)track.get("buffer_days")).intValue());assertNotNull(track.get("eligible_at"));assertNotNull(track.get("settlement_policy_id"));
  assertEquals(1,settlements.promoteDue());assertEquals("ELIGIBLE",trackStatus(sub(f)));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='SettlementEligible' AND aggregate_id=?",Integer.class,sub(f)));
  bufferDays(7);var second=paid(1);shipAndReceive(second,1);assertEquals(0,settlements.promoteDue());assertEquals("BUFFERING",trackStatus(sub(second)));
  assertEquals("ELIGIBLE",trackStatus(sub(f)));
  var tracks=read("/admin/settlement-tracks?status=ELIGIBLE",admin);assertEquals(200,tracks.status());assertTrue(tracks.body().get("data").toString().contains(sub(f)));
  var merchantTracks=read("/merchant/settlement-tracks",merchant);assertEquals(200,merchantTracks.status());assertTrue(merchantTracks.body().get("data").toString().contains(sub(f)));
  assertReconciliationConsistent();
 }
 @Test void merchantPolicyWinsAndRefundReversesFrozenRateNotCurrentRate(){
  var h=new HashMap<String,String>(Map.of());h.put("X-Reverify-Token",proof("settlement.policy.manage"));
  var created=req("POST","/admin/commission-policies",Map.of("name","TEST-ONLY merchant 10%","merchant_id",merchantId.toString(),"rate_basis_points",1000,"priority",10,"effective_from","2026-01-01T00:00:00Z"),admin,h);assertEquals(200,created.status(),created.body().toString());
  var f=paid(2);
  var alloc=db.queryForMap("SELECT * FROM commission_allocations WHERE order_item_id=?",UUID.fromString(item(f)));
  assertEquals(1000,((Number)alloc.get("rate_basis_points")).intValue());assertEquals(created.id(),alloc.get("policy_id").toString());
  long base=((Number)alloc.get("base_amount_fen")).longValue();long commission=(base*1000+5000)/10000;assertEquals(commission,((Number)alloc.get("commission_fen")).longValue());
  var newer=new HashMap<String,String>(Map.of());newer.put("X-Reverify-Token",proof("settlement.policy.manage"));
  assertEquals(200,req("POST","/admin/commission-policies",Map.of("name","TEST-ONLY merchant 50%","merchant_id",merchantId.toString(),"rate_basis_points",5000,"priority",20,"effective_from","2026-01-02T00:00:00Z"),admin,newer).status());
  var cancel=cancelPaid(f,1,key());assertEquals(200,cancel.status(),cancel.body().toString());
  long refunded=cancel.data().get("refund_amount_fen").asLong();assertEquals(1000,refunded);
  long expectedReversal=(commission*1000+base/2)/base;
  assertEquals(expectedReversal,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE refund_id=(SELECT id FROM refunds WHERE cancellation_id=?) AND entry_type='COMMISSION_REVERSAL'",Long.class,UUID.fromString(cancel.id())));
  assertEquals(1000,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE refund_id=(SELECT id FROM refunds WHERE cancellation_id=?) AND entry_type='REFUND_DEBIT'",Long.class,UUID.fromString(cancel.id())));
  var ledger=read("/merchant/ledger?entry_type=COMMISSION_REVERSAL",merchant);assertEquals(200,ledger.status());assertEquals(1,ledger.body().get("data").size());
  var policies=read("/admin/commission-policies",admin);assertEquals(200,policies.status());assertTrue(policies.body().get("data").size()>=3);
  assertReconciliationConsistent();
 }
 @Test void wholeSuborderCancellationRefundsShippingThroughLedger(){var f=paid(1);
  long subPayable=db.queryForObject("SELECT payable_amount_fen FROM suborders WHERE id=?",Long.class,UUID.fromString(sub(f)));
  var cancel=cancelPaid(f,1,key());assertEquals(200,cancel.status(),cancel.body().toString());
  assertEquals(subPayable,cancel.data().get("refund_amount_fen").asLong());
  assertEquals("ADJUSTED",trackStatus(sub(f)));
  assertEquals(1000,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE refund_id=(SELECT id FROM refunds WHERE cancellation_id=?) AND entry_type='REFUND_DEBIT'",Long.class,UUID.fromString(cancel.id())));
  assertEquals(subPayable-1000,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE refund_id=(SELECT id FROM refunds WHERE cancellation_id=?) AND entry_type='SHIPPING_ADJUSTMENT'",Long.class,UUID.fromString(cancel.id())));
  assertEquals(0,balance());
  assertReconciliationConsistent();
 }
 @Test void afterSaleFreezesTrackAndTerminalDecisionRestoresEligibility(){bufferDays(0);var f=paid(2);shipAndReceive(f,2);assertEquals("BUFFERING",trackStatus(sub(f)));
  String aid=applyRefundOnly(f,1,key()).id();assertEquals("FROZEN",trackStatus(sub(f)));
  assertEquals(0,settlements.promoteDue());assertEquals("FROZEN",trackStatus(sub(f)));
  var rejected=decide(aid,0,"REJECT",key());assertEquals(200,rejected.status(),rejected.body().toString());
  assertEquals("ELIGIBLE",trackStatus(sub(f)));
  assertReconciliationConsistent();
 }
 @Test void settledBatchConsumesBalanceAndTracksExactlyOnce(){bufferDays(0);var f=paid(2);shipAndReceive(f,2);assertEquals(1,settlements.promoteDue());
  long subPayable=db.queryForObject("SELECT payable_amount_fen FROM suborders WHERE id=?",Long.class,UUID.fromString(sub(f)));
  long commission=db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE order_item_id=? AND entry_type='COMMISSION_DEBIT'",Long.class,UUID.fromString(item(f)));
  var initiated=initiate();assertEquals(200,initiated.status(),initiated.body().toString());
  assertEquals("SETTLED",initiated.data().get("status").asString());assertEquals(subPayable-commission,initiated.data().get("amount_fen").asLong());
  assertEquals("SETTLED",trackStatus(sub(f)));
  assertEquals(subPayable-commission,db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE settlement_id=? AND entry_type='SETTLEMENT_DEBIT'",Long.class,UUID.fromString(initiated.id())));
  assertEquals(0,db.queryForObject("SELECT sum(signed_amount_fen) FROM settlement_items WHERE settlement_id=?",Long.class,UUID.fromString(initiated.id())));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_settlement_disbursements WHERE settlement_no=?",Integer.class,initiated.data().get("settlement_no").asString()));
  assertEquals(0,balance());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='SettlementCompleted' AND aggregate_id=?",Integer.class,initiated.id()));
  assertEquals(409,initiate().status());
  assertEquals(409,retry(initiated.id()).status());
  var batch=read("/merchant/settlements/"+initiated.id(),merchant);assertEquals(200,batch.status(),batch.body().toString());assertEquals("SETTLED",batch.data().get("status").asString());assertTrue(batch.data().get("items").size()>=3);
  var adminBatch=read("/admin/settlements/"+initiated.id(),admin);assertEquals(200,adminBatch.status());assertEquals(initiated.id(),adminBatch.id());
  var batches=read("/admin/settlements?status=SETTLED",admin);assertEquals(200,batches.status());assertTrue(batches.body().get("data").toString().contains(initiated.id()));
  var policies=read("/admin/settlement-policies",admin);assertEquals(200,policies.status());assertTrue(policies.body().get("data").size()>=2);
  assertReconciliationConsistent();
 }
 @Test void refundAfterSettlementBridgesThroughAdjustmentAndDeductsFromNextBatch(){bufferDays(0);var f=paid(1);shipAndReceive(f,1);settlements.promoteDue();
  var first=initiate();assertEquals(200,first.status(),first.body().toString());assertEquals("SETTLED",trackStatus(sub(f)));
  String aid=applyRefundOnly(f,1,key()).id();var decided=decide(aid,0,"APPROVE_REFUND",key());assertEquals(200,decided.status(),decided.body().toString());assertEquals("SUCCEEDED",decided.data().get("refund").get("status").asString());
  assertEquals("ADJUSTED",trackStatus(sub(f)));
  UUID refund=UUID.fromString(decided.data().get("refund").get("id").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE refund_id=? AND entry_type='REFUND_DEBIT' AND NOT affects_balance",Integer.class,refund));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE refund_id=? AND entry_type='COMMISSION_REVERSAL' AND NOT affects_balance",Integer.class,refund));
  long reversed=db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE refund_id=? AND entry_type='COMMISSION_REVERSAL'",Long.class,refund);
  long adjustmentAmount=1000-reversed;
  var adjustment=db.queryForMap("SELECT * FROM merchant_ledger_entries WHERE refund_id=? AND entry_type='SETTLEMENT_ADJUSTMENT'",refund);
  assertEquals(adjustmentAmount,((Number)adjustment.get("amount_fen")).longValue());assertEquals(first.id(),adjustment.get("settlement_id").toString());
  assertEquals("SETTLED",db.queryForObject("SELECT status FROM settlements WHERE id=?",String.class,UUID.fromString(first.id())));
  assertEquals(-adjustmentAmount,balance());
  var summary=read("/admin/merchants/"+merchantId+"/finance-summary",admin);assertEquals(adjustmentAmount,summary.data().get("receivable_fen").asLong());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM outbox_event WHERE event_type='SettlementAdjustmentCreated' AND aggregate_id=?",Integer.class,first.id()));
  var second=paid(1);shipAndReceive(second,1);settlements.promoteDue();
  long secondNet=db.queryForObject("SELECT payable_amount_fen FROM suborders WHERE id=?",Long.class,UUID.fromString(sub(second)))-db.queryForObject("SELECT amount_fen FROM merchant_ledger_entries WHERE order_item_id=? AND entry_type='COMMISSION_DEBIT'",Long.class,UUID.fromString(item(second)));
  var next=initiate();assertEquals(200,next.status(),next.body().toString());
  assertEquals(secondNet-adjustmentAmount,next.data().get("amount_fen").asLong());
  assertEquals(0,balance());
  assertReconciliationConsistent();
 }
 @Test void settlementRechecksEligibilityAfterWaitingForTrackLock()throws Exception{
  bufferDays(0);var f=paid(1);shipAndReceive(f,1);settlements.promoteDue();
  var task=new java.util.concurrent.atomic.AtomicReference<Future<Response>>();
  try(var pool=Executors.newSingleThreadExecutor()){
   tx.executeWithoutResult(s->{
    db.queryForMap("SELECT id FROM settlement_tracks WHERE suborder_id=? FOR UPDATE",UUID.fromString(sub(f)));
    task.set(pool.submit(()->initiate()));
    org.awaitility.Awaitility.await().atMost(Duration.ofSeconds(5)).until(()->db.queryForObject("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%settlement_tracks%'",Integer.class)>0);
    db.update("UPDATE settlement_tracks SET status='FROZEN',version=version+1 WHERE suborder_id=?",UUID.fromString(sub(f)));
   });
   var result=task.get().get(10,TimeUnit.SECONDS);assertEquals(409,result.status(),result.body().toString());
  }
  assertEquals(0,db.queryForObject("SELECT count(*) FROM simulated_settlement_disbursements WHERE merchant_id=?",Integer.class,merchantId));assertEquals("FROZEN",trackStatus(sub(f)));
 }
 @Test void splitFullRefundReversesTheEntireFrozenCommission(){
  var h=Map.of("X-Reverify-Token",proof("settlement.policy.manage"));
  assertEquals(200,req("POST","/admin/commission-policies",Map.of("name","TEST two basis points","merchant_id",merchantId.toString(),"rate_basis_points",2,"priority",100,"effective_from","2026-01-01T00:00:00Z"),admin,h).status());
  var f=paid(3);long frozen=db.queryForObject("SELECT commission_fen FROM commission_allocations WHERE order_item_id=?",Long.class,UUID.fromString(item(f)));assertEquals(1,frozen);
  for(int i=0;i<3;i++){var c=cancelPaid(f,1,key());assertEquals(200,c.status(),c.body().toString());}
  assertEquals(frozen,db.queryForObject("SELECT coalesce(sum(amount_fen),0) FROM merchant_ledger_entries WHERE entry_type='COMMISSION_REVERSAL' AND order_item_id=?",Long.class,UUID.fromString(item(f))));assertEquals(0,balance());assertReconciliationConsistent();
 }
 @Test void repeatedRefundsAfterSettlementRemainCollectableInNextBatch(){
  bufferDays(0);var f=paid(2);shipAndReceive(f,2);settlements.promoteDue();var first=initiate();assertEquals(200,first.status());
  for(int i=0;i<2;i++){var a=applyRefundOnly(f,1,key());assertEquals(200,a.status());var decided=decide(a.id(),0,"APPROVE_REFUND",key());assertEquals(200,decided.status(),decided.body().toString());}
  assertEquals(2,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE suborder_id=? AND entry_type='SETTLEMENT_ADJUSTMENT'",Integer.class,UUID.fromString(sub(f))));
  var nextGoods=paid(3);shipAndReceive(nextGoods,3);settlements.promoteDue();
  var next=initiate();assertEquals(200,next.status(),next.body().toString());assertEquals(0,balance(),"every post-payout refund debit must be included in the next batch");assertReconciliationConsistent();
 }
 @Test void transientDisbursementFailureRetriesWithoutDuplicatePayout(){bufferDays(0);var f=paid(1);shipAndReceive(f,1);settlements.promoteDue();
  db.update("INSERT INTO simulated_settlement_directives(settlement_no,outcome) VALUES (?,'FAIL_TRANSIENT')","MERCHANT:"+merchantId);
  var initiated=initiate();assertEquals(200,initiated.status(),initiated.body().toString());
  assertEquals("FAILED_RETRYABLE",initiated.data().get("status").asString());
  assertEquals(0,db.queryForObject("SELECT count(*) FROM simulated_settlement_disbursements WHERE merchant_id=?",Integer.class,merchantId));
  assertEquals(0,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE merchant_id=? AND entry_type='SETTLEMENT_DEBIT'",Integer.class,merchantId));
  assertEquals("PROCESSING",trackStatus(sub(f)));
  var retried=retry(initiated.id());assertEquals(200,retried.status(),retried.body().toString());assertEquals("SETTLED",retried.data().get("status").asString());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_settlement_disbursements WHERE settlement_no=?",Integer.class,initiated.data().get("settlement_no").asString()));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE settlement_id=? AND entry_type='SETTLEMENT_DEBIT'",Integer.class,UUID.fromString(initiated.id())));
  assertEquals("SETTLED",trackStatus(sub(f)));
  assertEquals(0,settlements.retryFailed());
  assertReconciliationConsistent();
 }
 @Test void workerRetriesFailedDisbursement(){bufferDays(0);var f=paid(1);shipAndReceive(f,1);settlements.promoteDue();
  db.update("INSERT INTO simulated_settlement_directives(settlement_no,outcome) VALUES (?,'FAIL_TRANSIENT')","MERCHANT:"+merchantId);
  var initiated=initiate();assertEquals("FAILED_RETRYABLE",initiated.data().get("status").asString());
  db.update("UPDATE settlements SET next_retry_at=clock_timestamp()-interval '1 second' WHERE id=?",UUID.fromString(initiated.id()));
  assertEquals(1,settlements.retryFailed());
  assertEquals("SETTLED",db.queryForObject("SELECT status FROM settlements WHERE id=?",String.class,UUID.fromString(initiated.id())));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM simulated_settlement_disbursements WHERE merchant_id=?",Integer.class,merchantId));
  assertReconciliationConsistent();
 }
 @Test void manualAdjustmentRequiresReverifyAndStaysIdempotent(){
  var noProof=req("POST","/admin/merchants/"+merchantId+"/ledger-adjustments",Map.of("direction","DEBIT","amount_fen",300,"reason","TEST-ONLY correction"),admin,Map.of("Idempotency-Key",key()));
  assertEquals(403,noProof.status(),noProof.body().toString());
  String k=key();var h=new HashMap<String,String>(Map.of("Idempotency-Key",k));h.put("X-Reverify-Token",proof("ledger.adjust"));
  var first=req("POST","/admin/merchants/"+merchantId+"/ledger-adjustments",Map.of("direction","DEBIT","amount_fen",300,"reason","TEST-ONLY correction"),admin,h);assertEquals(200,first.status(),first.body().toString());
  assertEquals("MANUAL_ADJUSTMENT",first.data().get("entry_type").asString());assertTrue(first.data().get("affects_balance").asBoolean());
  var replay=req("POST","/admin/merchants/"+merchantId+"/ledger-adjustments",Map.of("direction","DEBIT","amount_fen",300,"reason","TEST-ONLY correction"),admin,h);assertEquals(200,replay.status());assertEquals(first.id(),replay.id());
  assertEquals(1,db.queryForObject("SELECT count(*) FROM merchant_ledger_entries WHERE merchant_id=? AND entry_type='MANUAL_ADJUSTMENT'",Integer.class,merchantId));
  assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_event WHERE action='ledger.adjust' AND object_id=?",Integer.class,first.id()));
  assertEquals(-300,balance());
  assertEquals(300,read("/merchant/finance-summary",merchant).data().get("receivable_fen").asLong());
  assertReconciliationConsistent();
 }
 @Test void rbacAndCrossMerchantBoundariesHold(){var f=paid(1);
  assertEquals(200,read("/merchant/ledger",merchant).status());
  assertEquals(200,read("/merchant/ledger",foreign).status());
  assertEquals(0,read("/merchant/ledger",foreign).body().get("data").size());
  assertEquals(403,read("/admin/merchants/"+merchantId+"/ledger",merchant).status());
  assertEquals(403,read("/merchant/ledger",colleague).status());
  assertEquals(403,read("/merchant/settlements",colleague).status());
  assertEquals(403,read("/admin/finance/reconciliation",merchant).status());
  assertEquals(403,read("/admin/finance/reconciliation",f.u()).status());
  assertEquals(403,read("/admin/settlement-tracks",merchant).status());
  assertEquals(403,initiateAs(colleague));
  assertEquals(404,read("/merchant/settlements/"+UUID.randomUUID(),merchant).status());
  var listed=read("/admin/merchants/"+merchantId+"/ledger",admin);assertEquals(200,listed.status());assertTrue(listed.body().get("data").size()>=2);
 }
 int initiateAs(String token){var h=new HashMap<String,String>(Map.of("Idempotency-Key",key()));h.put("X-Reverify-Token",proof("settlement.execute"));return req("POST","/admin/merchants/"+merchantId+"/settlements",Map.of(),token,h).status();}
 @Test void concurrentInitiationConsumesEntriesOnce()throws Exception{bufferDays(0);var f=paid(1);shipAndReceive(f,1);settlements.promoteDue();
  var pool=Executors.newFixedThreadPool(2);try{var start=new CountDownLatch(1);Callable<Response> work=()->{start.await();return initiate();};var x=pool.submit(work);var y=pool.submit(work);start.countDown();var statuses=List.of(x.get(20,TimeUnit.SECONDS).status(),y.get(20,TimeUnit.SECONDS).status());assertTrue(statuses.contains(200),statuses.toString());assertTrue(statuses.contains(409),statuses.toString());assertEquals(1,db.queryForObject("SELECT count(*) FROM settlements WHERE merchant_id=?",Integer.class,merchantId));}finally{pool.shutdownNow();}
  assertReconciliationConsistent();
 }
 @Test void databaseGuardsRejectLedgerTampering(){var f=paid(1);
  UUID entry=db.queryForObject("SELECT id FROM merchant_ledger_entries WHERE suborder_id=? AND entry_type='SALE_CREDIT'",UUID.class,UUID.fromString(sub(f)));
  UUID alloc=db.queryForObject("SELECT id FROM commission_allocations WHERE order_item_id=?",UUID.class,UUID.fromString(item(f)));
  UUID track=db.queryForObject("SELECT id FROM settlement_tracks WHERE suborder_id=?",UUID.class,UUID.fromString(sub(f)));
  assertThrows(Exception.class,()->db.update("UPDATE merchant_ledger_entries SET amount_fen=1 WHERE id=?",entry));
  assertThrows(Exception.class,()->db.update("DELETE FROM merchant_ledger_entries WHERE id=?",entry));
  assertThrows(Exception.class,()->db.update("UPDATE commission_allocations SET commission_fen=1 WHERE id=?",alloc));
  assertThrows(Exception.class,()->db.update("UPDATE commission_policies SET rate_basis_points=1 WHERE id='7b2f2b6a-7c1f-4d0d-9c1a-000000000001'"));
  assertThrows(Exception.class,()->db.update("UPDATE settlement_tracks SET status='SETTLED',version=version+1 WHERE id=?",track));
  assertThrows(Exception.class,()->db.update("INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,suborder_id,source_event,created_by_type) VALUES (?,?,'SALE_CREDIT','CREDIT',1,TRUE,?,'TEST','SYSTEM')",UUID.randomUUID(),merchantId,UUID.fromString(sub(f))));
  assertThrows(Exception.class,()->db.update("INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,source_event,created_by_type) VALUES (?,?,'SALE_CREDIT','DEBIT',1,TRUE,'TEST','SYSTEM')",UUID.randomUUID(),merchantId));
  assertReconciliationConsistent();
 }
 @AfterAll static void finish()throws Exception{Files.writeString(Path.of("target/m46-contract-samples.json"),JsonMapper.builder().build().writeValueAsString(SAMPLES));PG.close();}
}
