package cn.pawday.booking;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.pilot.PilotPolicy;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.core.env.Environment;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** B1 only: synthetic terms and unpaid holds. No payment, refund or settlement instructions. */
@Service
public class ServiceTradeService {
 private final PublishingSupport p; private final AccessGuard guard; private final IdempotentCommandExecutor commands;
 private final AuditWriter audit; private final AuthService auth; private final Crypto crypto; private final Clock clock;
 private final PilotPolicy pilot; private final TransactionTemplate tx; private final boolean enabled;
 private static final List<String> PUBLIC=List.of("service_id","store_id","service_title","service_kind","currency","amount_fen","billing_unit","cancel_cutoff_minutes","consumer_late_cancel","merchant_cancel","no_show");
 public ServiceTradeService(PublishingSupport p,AccessGuard guard,IdempotentCommandExecutor commands,AuditWriter audit,AuthService auth,Crypto crypto,Clock clock,PilotPolicy pilot,TransactionTemplate tx,Environment env){
  this.p=p;this.guard=guard;this.commands=commands;this.audit=audit;this.auth=auth;this.crypto=crypto;this.clock=clock;this.pilot=pilot;this.tx=tx;
  enabled=env.getProperty("pawday.service-trade.simulation-enabled",Boolean.class,false)&&env.getProperty("pawday.booking.simulation-enabled",Boolean.class,false)
   &&Set.of("development","test","pilot").contains(env.getProperty("pawday.deployment-mode","development"))
   &&Arrays.stream(env.getActiveProfiles()).noneMatch(Set.of("production","prod")::contains);
 }
 private void gate(){if(!enabled)throw new Failure(404,"SERVICE_TRADE_SIMULATION_DISABLED");if(pilot.paused())throw new Failure(503,"PILOT_PAUSED");}
 private void consumer(Actor a){gate();if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 private void staff(Actor a,UUID store,String code){gate();permission(a,Actor.Realm.MERCHANT,code);guard.store(a,store);p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND s.merchant_id=? AND m.status='ACTIVE'",store,a.merchantId());}
 private void visible(UUID store){p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id JOIN nearby_store_profile n ON n.store_id=s.id WHERE s.id=? AND m.status='ACTIVE' AND n.publication_status='PUBLISHED' AND n.claim_status='VERIFIED' FOR SHARE OF m,n",store);}
 private Map<String,Object> snapshot(Map<String,Object> row){return p.json.readValue(row.get("snapshot").toString(),Map.class);}
 private String digest(Map<String,Object> value){return crypto.hash(p.json.writeValueAsString(new TreeMap<>(value)));}
 private Map<String,Object> terms(UUID id){return p.one("SELECT * FROM service_trade_terms WHERE id=?",id);}
 private Map<String,Object> termsView(Map<String,Object> row,boolean publicOnly){
  var values=snapshot(row);Map<String,Object> v=new LinkedHashMap<>();if(publicOnly)PUBLIC.forEach(k->v.put(k,values.get(k)));else v.putAll(values);
  for(String key:List.of("id","version","terms_sha256"))v.put(key,row.get(key));v.put("simulated",true);
  if(!publicOnly){v.put("state",row.get("state"));v.put("policy_snapshot_sha256",row.get("policy_snapshot_sha256"));v.put("authorization_status","ENGINEERING_SCENARIO_ONLY");}return v;
 }
 public Map<String,Object> draft(Actor a,UUID store,Map<String,Object>b,String key,HttpServletRequest r){
  staff(a,store,"service.terms.write");fields(b,"service_id","currency","amount_fen","billing_unit","cancel_cutoff_minutes","consumer_late_cancel","merchant_cancel","no_show","commission_basis_points","settlement_buffer_minutes","evidence_refs");
  UUID service=id(b.get("service_id"));integer(b.get("amount_fen"),1,1000000000);integer(b.get("cancel_cutoff_minutes"),0,129600);integer(b.get("commission_basis_points"),0,10000);integer(b.get("settlement_buffer_minutes"),0,129600);
  if(!"CNY".equals(b.get("currency"))||!"WHOLE_SLOT".equals(b.get("billing_unit"))||!"MANUAL_REVIEW".equals(b.get("consumer_late_cancel"))||!"FULL_REFUND".equals(b.get("merchant_cancel"))||!"MANUAL_REVIEW".equals(b.get("no_show")))throw new Failure(400,"VALIDATION_ERROR");
  if(!(b.get("evidence_refs") instanceof List<?> evidence)||evidence.isEmpty()||evidence.size()>20)throw new Failure(400,"VALIDATION_ERROR");
  for(Object e:evidence){if(!(e instanceof Map<?,?> m)||!m.keySet().equals(Set.of("kind","reference"))||!"TEST_SCENARIO".equals(m.get("kind"))||!(m.get("reference") instanceof String ref)||!ref.matches("TEST_ONLY_[A-Z0-9_-]{1,100}"))throw new Failure(400,"SYNTHETIC_EVIDENCE_REQUIRED");}
  return commands.command(a,"service.terms.draft:"+store,key,b,()->{
   staff(a,store,"service.terms.write");var s=p.one("SELECT * FROM booking_services WHERE id=? AND store_id=? FOR SHARE",service,store);
   var data=new TreeMap<String,Object>(b);data.put("store_id",store.toString());data.put("service_title",s.get("title"));data.put("service_kind",s.get("kind"));
   var shown=new TreeMap<String,Object>();PUBLIC.forEach(k->shown.put(k,data.get(k)));UUID tid=UUID.randomUUID();
   p.db.update("INSERT INTO service_trade_terms(id,service_id,store_id,snapshot,terms_sha256,policy_snapshot_sha256,created_by,created_at) VALUES (?,?,?,?::jsonb,?,?,?,?)",tid,service,store,p.json.writeValueAsString(data),digest(shown),digest(data),a.principalId(),now());record(a,"service.terms.draft",tid,r);return termsView(terms(tid),false);
  });
 }
 public List<Map<String,Object>> termsList(Actor a,UUID store,UUID after,int size){if(store==null){gate();permission(a,Actor.Realm.ADMIN,"service.terms.review");}else staff(a,store,"service.terms.write");limit(size);return p.db.queryForList("SELECT * FROM service_trade_terms WHERE "+(store==null?"":"store_id=? AND ")+"id>? ORDER BY id LIMIT ?",store==null?new Object[]{after,size+1}:new Object[]{store,after,size+1}).stream().map(row->termsView(row,false)).toList();}
 public Map<String,Object> review(Actor a,UUID id,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){
  gate();permission(a,Actor.Realm.ADMIN,"service.terms.review");fields(b,"decision","reason_code");boolean approve="APPROVE_SIMULATION".equals(b.get("decision"));
  if(!(approve&&"TEST_SCENARIO_REVIEWED".equals(b.get("reason_code"))||"REJECT".equals(b.get("decision"))&&"RULES_INCOMPLETE".equals(b.get("reason_code"))))throw new Failure(400,"VALIDATION_ERROR");long v=version(match);var original=terms(id);
  return commands.command(a,"service.terms.review:"+id,key,Map.of("body",b,"version",v),()->{
   gate();p.one("SELECT id FROM booking_services WHERE id=? FOR UPDATE",original.get("service_id"));var row=p.one("SELECT * FROM service_trade_terms WHERE id=? FOR UPDATE",id);sameVersion(row,v);if(!"DRAFT".equals(row.get("state")))throw new Failure(409,"SERVICE_TERMS_NOT_DRAFT");
   auth.consumeProof(a,"service.terms.review",proof);
   if(approve)p.db.update("UPDATE service_trade_terms SET state='RETIRED',version=version+1 WHERE service_id=? AND state='REVIEWED'",row.get("service_id"));
   p.db.update("UPDATE service_trade_terms SET state=?,version=version+1,reviewed_by=?,reviewed_at=? WHERE id=?",approve?"REVIEWED":"REJECTED",a.principalId(),now(),id);record(a,"service.terms.review",id,r);return termsView(terms(id),false);
  });
 }
 public Map<String,Object> readTerms(Actor a,UUID id,boolean byService){consumer(a);var t=byService?p.one("SELECT * FROM service_trade_terms WHERE service_id=? AND state='REVIEWED'",id):terms(id);visible((UUID)t.get("store_id"));var s=p.one("SELECT * FROM booking_services WHERE id=? AND status='ACTIVE'",t.get("service_id"));if(!"REVIEWED".equals(t.get("state")))throw new Failure(409,"SERVICE_TERMS_UNAVAILABLE");return termsView(t,true);}
 public Map<String,Object> quote(Actor a,Map<String,Object>b,String key,HttpServletRequest r){
  consumer(a);fields(b,"terms_id","slot_id");UUID tid=id(b.get("terms_id")),slot=id(b.get("slot_id"));
  return commands.command(a,"service.trade.quote",key,b,()->{
   consumer(a);var sl=p.one("SELECT * FROM booking_slots WHERE id=? FOR SHARE",slot);var s=p.one("SELECT * FROM booking_services WHERE id=? FOR SHARE",sl.get("service_id"));var t=terms(tid);available(sl,s,t);
   UUID q=UUID.randomUUID();Instant expiry=earlier(clock.instant().plusSeconds(300),((Timestamp)sl.get("starts_at")).toInstant());
   p.db.update("INSERT INTO service_trade_quotes(id,terms_id,slot_id,service_id,store_id,user_id,terms_version,service_version,terms_sha256,policy_snapshot_sha256,payable_fen,created_at,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",q,tid,slot,s.get("id"),s.get("store_id"),a.userId(),t.get("version"),s.get("version"),t.get("terms_sha256"),t.get("policy_snapshot_sha256"),snapshot(t).get("amount_fen"),now(),Timestamp.from(expiry));record(a,"service.trade.quote",q,r);return quoteView(q);
  });
 }
 private void available(Map<String,Object> slot,Map<String,Object> s,Map<String,Object> t){visible((UUID)s.get("store_id"));if(!"ACTIVE".equals(s.get("status"))||!((Timestamp)slot.get("starts_at")).toInstant().isAfter(clock.instant()))throw new Failure(409,"BOOKING_NOT_AVAILABLE");if(!"REVIEWED".equals(t.get("state"))||!s.get("id").equals(t.get("service_id")))throw new Failure(409,"SERVICE_TERMS_UNAVAILABLE");}
 private Map<String,Object> quoteView(UUID id){var q=p.one("SELECT q.id,q.store_id,q.service_id,q.slot_id,q.terms_id,q.terms_version,q.terms_sha256,'CNY' AS currency,q.payable_fen,s.starts_at,s.ends_at,q.expires_at,false AS capacity_held,true AS simulated FROM service_trade_quotes q JOIN booking_slots s ON s.id=q.slot_id WHERE q.id=?",id);return p.view(q);}
 public Map<String,Object> reserve(Actor a,Map<String,Object>b,String key,HttpServletRequest r){
  consumer(a);fields(b,"quote_id","accepted_terms_sha256");UUID qid=id(b.get("quote_id"));String hash=text(b.get("accepted_terms_sha256"),64);if(!hash.matches("[0-9a-f]{64}"))throw new Failure(400,"VALIDATION_ERROR");ownedQuote(a,qid);
  return commands.command(a,"service.trade.reserve",key,b,()->{
   consumer(a);var q=ownedQuote(a,qid);var slot=p.one("SELECT * FROM booking_slots WHERE id=? FOR UPDATE",q.get("slot_id"));var s=p.one("SELECT * FROM booking_services WHERE id=? FOR SHARE",q.get("service_id"));var t=terms((UUID)q.get("terms_id"));available(slot,s,t);
   if(!((Timestamp)q.get("expires_at")).toInstant().isAfter(clock.instant())||number(q.get("terms_version"))!=number(t.get("version"))||number(q.get("service_version"))!=number(s.get("version")))throw new Failure(409,"SERVICE_QUOTE_EXPIRED");
   if(!hash.equals(q.get("terms_sha256")))throw new Failure(409,"SERVICE_TERMS_CONFIRMATION_REQUIRED");
   if(!p.db.queryForList("SELECT id FROM service_trade_orders WHERE quote_id=?",qid).isEmpty())throw new Failure(409,"SERVICE_QUOTE_ALREADY_USED");
   if(p.db.queryForObject("SELECT (SELECT count(*) FROM service_bookings WHERE slot_id=? AND user_id=? AND status='BOOKED')+(SELECT count(*) FROM service_trade_orders WHERE slot_id=? AND user_id=? AND capacity_state='HELD')",Integer.class,q.get("slot_id"),a.userId(),q.get("slot_id"),a.userId())>0)throw new Failure(409,"BOOKING_ALREADY_EXISTS");
   if(occupied((UUID)q.get("slot_id"))>=number(slot.get("capacity")))throw new Failure(409,"BOOKING_SLOT_FULL");
   Instant expiry=earlier(clock.instant().plusSeconds(600),((Timestamp)slot.get("starts_at")).toInstant());UUID trade=UUID.randomUUID();
   p.db.update("INSERT INTO service_trade_orders(id,quote_id,slot_id,service_id,store_id,terms_id,user_id,snapshot,terms_sha256,policy_snapshot_sha256,payable_fen,created_at,hold_expires_at) VALUES (?,?,?,?,?,?,?,?::jsonb,?,?,?,?,?)",trade,qid,q.get("slot_id"),q.get("service_id"),q.get("store_id"),q.get("terms_id"),a.userId(),t.get("snapshot").toString(),q.get("terms_sha256"),q.get("policy_snapshot_sha256"),q.get("payable_fen"),now(),Timestamp.from(expiry));record(a,"service.trade.reserve",trade,r);return tradeView(trade);
  });
 }
 private Map<String,Object> ownedQuote(Actor a,UUID id){return p.one("SELECT * FROM service_trade_quotes WHERE id=? AND user_id=?",id,a.userId());}
 private int occupied(UUID slot){return p.db.queryForObject("SELECT (SELECT count(*) FROM service_bookings WHERE slot_id=? AND status='BOOKED')+(SELECT count(*) FROM service_trade_orders WHERE slot_id=? AND capacity_state='HELD')",Integer.class,slot,slot);}
 private Map<String,Object> owned(Actor a,UUID id){consumer(a);return p.one("SELECT * FROM service_trade_orders WHERE id=? AND user_id=?",id,a.userId());}
 public Map<String,Object> read(Actor a,UUID id){owned(a,id);return tradeView(id);}
 public List<Map<String,Object>> trades(Actor a,UUID store,UUID after,int size){if(store==null)consumer(a);else staff(a,store,"service.trade.read");limit(size);return p.db.queryForList("SELECT id FROM service_trade_orders WHERE "+(store==null?"user_id":"store_id")+"=? AND id>? ORDER BY id LIMIT ?",store==null?a.userId():store,after,size+1).stream().map(row->tradeView((UUID)row.get("id"))).toList();}
 private Map<String,Object> tradeView(UUID id){var row=p.one("SELECT o.id,o.store_id,o.service_id,o.slot_id,o.terms_id,o.terms_sha256,'CNY' AS currency,o.payable_fen,o.order_state,o.payment_state,o.capacity_state,o.hold_expires_at,s.starts_at,o.version FROM service_trade_orders o JOIN booking_slots s ON s.id=o.slot_id WHERE o.id=?",id);var v=p.view(row);for(String f:List.of("paid_fen","refunded_fen","refund_reserved_fen","commission_fen","commission_reversed_fen","merchant_net_fen"))v.put(f,0);v.put("fulfillment_state","NOT_STARTED");v.put("settlement_state","NOT_PAYABLE");for(String f:List.of("receipt_id","confirmed_at","settlement_buffer_ends_at"))v.put(f,null);v.put("as_of",clock.instant().toString());v.put("open_dispute",false);v.put("unresolved_collection_case",false);v.put("simulated",true);return v;}
 public Map<String,Object> cancel(Actor a,UUID id,String match,String key,HttpServletRequest r){var original=owned(a,id);long v=version(match);return commands.command(a,"service.trade.cancel:"+id,key,Map.of("version",v),()->{consumer(a);p.one("SELECT id FROM booking_slots WHERE id=? FOR UPDATE",original.get("slot_id"));var row=p.one("SELECT * FROM service_trade_orders WHERE id=? FOR UPDATE",id);sameVersion(row,v);if(!"AWAITING_PAYMENT".equals(row.get("order_state")))throw new Failure(409,"SERVICE_TRADE_ALREADY_CLOSED");close(id,"CANCELLED");record(a,"service.trade.cancel",id,r);return tradeView(id);});}
 private void close(UUID id,String state){p.db.update("UPDATE service_trade_orders SET order_state=?,payment_state='CLOSED',capacity_state='RELEASED',closed_at=?,version=version+1 WHERE id=?",state,now(),id);}
 @Scheduled(fixedDelayString="${pawday.service-trade.expiry-delay-ms:30000}") public void expire(){if(!enabled||pilot.paused())return;expireBatch();}
 public int expireBatch(){gate();int count=0;for(var candidate:p.db.queryForList("SELECT id,slot_id FROM service_trade_orders WHERE order_state='AWAITING_PAYMENT' AND hold_expires_at<=? ORDER BY hold_expires_at,id LIMIT 100",now())){
  Boolean changed=tx.execute(status->{p.one("SELECT id FROM booking_slots WHERE id=? FOR UPDATE",candidate.get("slot_id"));var row=p.one("SELECT * FROM service_trade_orders WHERE id=? FOR UPDATE",candidate.get("id"));if(!"AWAITING_PAYMENT".equals(row.get("order_state"))||((Timestamp)row.get("hold_expires_at")).toInstant().isAfter(clock.instant()))return false;close((UUID)row.get("id"),"EXPIRED");record(null,"service.trade.expire",(UUID)row.get("id"),null);return true;});if(Boolean.TRUE.equals(changed))count++;
 }return count;}
 private Timestamp now(){return Timestamp.from(clock.instant());}private static Instant earlier(Instant a,Instant b){return a.isBefore(b)?a:b;}
 private void record(Actor a,String action,UUID id,HttpServletRequest r){audit.write(a,action,"SERVICE_TRADE",id.toString(),Map.of(),Map.of("simulated",true),r);}
}
