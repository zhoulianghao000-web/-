package cn.pawday.booking;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.payment.ServiceTradeFinance;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** Paid service facts only: no legacy booking credentials or financial decisions. */
@Service
public class ServiceTradeOperations {
 private final PublishingSupport p;
 private final ServiceTradeFinance finance;
 private final TransactionTemplate tx;
 private final IdempotentCommandExecutor commands;
 private final AccessGuard guard;
 private final AuthService auth;
 private final Crypto crypto;
 private final AuditWriter audit;
 private final OutboxWriter outbox;
 private final Clock clock;
 public ServiceTradeOperations(PublishingSupport p,ServiceTradeFinance finance,TransactionTemplate tx,IdempotentCommandExecutor commands,AccessGuard guard,AuthService auth,Crypto crypto,AuditWriter audit,OutboxWriter outbox,Clock clock){
  this.p=p;this.finance=finance;this.tx=tx;this.commands=commands;this.guard=guard;this.auth=auth;this.crypto=crypto;this.audit=audit;this.outbox=outbox;this.clock=clock;
 }
 private Timestamp now(){return Timestamp.from(clock.instant());}
 private Map<String,Object> owned(Actor a,UUID trade){
  finance.gate();if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");
  return p.one("SELECT * FROM service_trade_orders WHERE id=? AND user_id=?",trade,a.userId());
 }
 private void staff(Actor a,UUID store,String code){
  finance.gate();permission(a,Actor.Realm.MERCHANT,code);guard.store(a,store);
  p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND m.id=? AND m.status='ACTIVE'",store,a.merchantId());
 }
 private void scoped(Actor a,UUID trade,UUID store,String code){
  if(store==null)owned(a,trade);
  else{staff(a,store,code);p.one("SELECT id FROM service_trade_orders WHERE id=? AND store_id=?",trade,store);}
 }
 private void record(Actor a,String action,UUID trade,Map<String,Object> data,HttpServletRequest request){
  audit.write(a,action,"SERVICE_TRADE",trade.toString(),Map.of(),data,request);
  outbox.append("SERVICE_TRADE",trade.toString(),action,1,Map.of("trade_id",trade,"simulated",true),request==null?null:(String)request.getAttribute("correlation_id"));
 }
 private void bump(UUID trade){p.db.update("UPDATE service_trade_orders SET version=version+1 WHERE id=?",trade);}
 private boolean open(UUID trade){return Boolean.TRUE.equals(p.db.queryForObject("SELECT service_trade_open_dispute(?)",Boolean.class,trade));}
 private void ready(Map<String,Object> row,Map<String,Object> pay){
  if(!"CONFIRMED".equals(row.get("order_state"))||!"CONFIRMED".equals(row.get("capacity_state"))||!"SUCCEEDED".equals(pay.get("status"))||!Objects.equals(row.get("receipt_id"),pay.get("successful_receipt_id")))throw new Failure(409,"SERVICE_FULFILLMENT_PAYMENT_REQUIRED");
  UUID trade=(UUID)row.get("id"),payment=(UUID)pay.get("id");
  if(open(trade)||p.db.queryForObject("SELECT EXISTS(SELECT 1 FROM service_trade_refunds WHERE trade_id=? AND source_kind<>'COMPENSATION')",Boolean.class,trade)
   ||p.db.queryForObject("SELECT EXISTS(SELECT 1 FROM payment_attempts WHERE payment_id=? AND status IN ('CREATED','CHANNEL_PENDING','UNKNOWN')) OR EXISTS(SELECT 1 FROM payment_cases WHERE payment_id=? AND status<>'REFUNDED')",Boolean.class,payment,payment))throw new Failure(409,"SERVICE_FULFILLMENT_FROZEN");
 }
 private String credential(UUID trade,Object receipt,Instant end){return crypto.otpHash("service-trade-check-in:v1:"+trade+":"+receipt,end.toString());}
 public Map<String,Object> credential(Actor a,UUID trade){
  owned(a,trade);finance.channelGate();
  return tx.execute(s->{var row=finance.lockTrade(trade,false);var pay=p.one("SELECT * FROM payments WHERE service_trade_id=? FOR SHARE",trade);ready(row,pay);
   var slot=p.one("SELECT starts_at,ends_at FROM booking_slots WHERE id=?",row.get("slot_id"));Instant end=((Timestamp)slot.get("ends_at")).toInstant();
   if(!"NOT_STARTED".equals(row.get("fulfillment_state"))||!clock.instant().isBefore(end))throw new Failure(409,"SERVICE_CREDENTIAL_UNAVAILABLE");
   return Map.of("trade_id",trade.toString(),"credential",credential(trade,row.get("receipt_id"),end),"valid_from",((Timestamp)slot.get("starts_at")).toInstant().minusSeconds(1800).toString(),"expires_at",end.toString(),"simulated",true);
  });
 }
 public List<Map<String,Object>> fulfillment(Actor a,UUID trade,UUID store,UUID after,int size){
  scoped(a,trade,store,"service.trade.read");limit(size);
  return p.db.queryForList("SELECT id,trade_id,version,status,reason_code,occurred_at,true AS simulated FROM service_trade_fulfillment_events WHERE trade_id=? AND id>? ORDER BY id LIMIT ?",trade,after,size+1).stream().map(p::view).toList();
 }
 public Map<String,Object> fulfill(Actor a,UUID trade,UUID store,Map<String,Object> body,String match,String key,HttpServletRequest request){
  scoped(a,trade,store,"service.trade.fulfill");finance.channelGate();fields(body,"status","credential","reason_code");
  String status=text(body.get("status"),16),token=body.get("credential") instanceof String t?t:null,reason=body.get("reason_code") instanceof String t?t:null;
  if(!Set.of("CHECKED_IN","COMPLETED","NO_SHOW","EXCEPTION").contains(status)||token==null||reason==null||token.length()>64
   ||(status.equals("CHECKED_IN")?!token.matches("[0-9a-f]{64}"):!token.isEmpty())
   ||(status.equals("EXCEPTION")?!Set.of("SERVICE_UNAVAILABLE","SAFETY_STOP","CUSTOMER_DISPUTE").contains(reason):!reason.isEmpty()))throw new Failure(400,"VALIDATION_ERROR");
  long version=version(match);
  commands.command(a,"service.trade.fulfill:"+trade,key,Map.of("body",body,"version",version),()->{
   scoped(a,trade,store,"service.trade.fulfill");finance.channelGate();var row=finance.lockTrade(trade,true);sameVersion(row,version);var pay=p.one("SELECT * FROM payments WHERE service_trade_id=? FOR UPDATE",trade);ready(row,pay);
   var slot=p.one("SELECT starts_at,ends_at FROM booking_slots WHERE id=?",row.get("slot_id"));Instant start=((Timestamp)slot.get("starts_at")).toInstant(),end=((Timestamp)slot.get("ends_at")).toInstant(),time=clock.instant();String before=row.get("fulfillment_state").toString();
   boolean allowed=switch(status){case "CHECKED_IN"->before.equals("NOT_STARTED")&&!time.isBefore(start.minusSeconds(1800))&&time.isBefore(end);case "COMPLETED"->before.equals("CHECKED_IN")&&!time.isBefore(start);case "NO_SHOW"->before.equals("NOT_STARTED")&&!time.isBefore(end);default->Set.of("NOT_STARTED","CHECKED_IN").contains(before)&&!time.isBefore(start.minusSeconds(1800));};
   if(!allowed)throw new Failure(409,"SERVICE_FULFILLMENT_CONFLICT");
   if(status.equals("CHECKED_IN")&&!crypto.equal(token,credential(trade,row.get("receipt_id"),end)))throw new Failure(409,"SERVICE_CREDENTIAL_INVALID");
   p.db.update("INSERT INTO service_trade_fulfillment_events(id,trade_id,version,status,reason_code,actor_id,occurred_at) VALUES (?,?,?,?,?,?,?)",UUID.randomUUID(),trade,version+1,status,reason,a.principalId(),now());
   p.db.update("UPDATE service_trade_orders SET fulfillment_state=?,version=version+1 WHERE id=?",status,trade);
   record(a,"service.trade.fulfill."+status.toLowerCase(Locale.ROOT),trade,Map.of("status",status,"simulated",true),request);return Map.of("trade_id",trade.toString());
  });return finance.tradeView(trade);
 }
 private void evidence(Object raw){
  if(!(raw instanceof List<?> refs)||refs.isEmpty()||refs.size()>20)throw new Failure(400,"VALIDATION_ERROR");
  for(Object ref:refs)if(!(ref instanceof Map<?,?> m)||!m.keySet().equals(Set.of("kind","reference"))||!"TEST_SCENARIO".equals(m.get("kind"))||!(m.get("reference") instanceof String value)||!value.matches("TEST_ONLY_[A-Z0-9_-]{1,100}"))throw new Failure(400,"SYNTHETIC_EVIDENCE_REQUIRED");
 }
 public Map<String,Object> dispute(Actor a,UUID trade,Map<String,Object> body,String match,String key,HttpServletRequest request){
  owned(a,trade);fields(body,"reason_code","evidence_refs");String reason=text(body.get("reason_code"),32);if(!Set.of("SERVICE_QUALITY","BOOKING_MISMATCH","SAFETY_CONCERN").contains(reason))throw new Failure(400,"VALIDATION_ERROR");evidence(body.get("evidence_refs"));long version=version(match);
  return commands.command(a,"service.trade.dispute.open:"+trade,key,Map.of("body",body,"version",version),()->{
   owned(a,trade);var row=finance.lockTrade(trade,true);sameVersion(row,version);var pay=p.one("SELECT * FROM payments WHERE service_trade_id=? FOR UPDATE",trade);
   if(!"SUCCEEDED".equals(pay.get("status"))||!"SUCCEEDED".equals(row.get("payment_state")))throw new Failure(409,"SERVICE_DISPUTE_PAYMENT_REQUIRED");
   if(open(trade))throw new Failure(409,"SERVICE_DISPUTE_ALREADY_OPEN");UUID id=UUID.randomUUID();
   p.db.update("INSERT INTO service_trade_disputes(id,trade_id,version,reason_code,evidence_refs,opened_by,opened_at) VALUES (?,?,?,?,?::jsonb,?,?)",id,trade,version+1,reason,p.json.writeValueAsString(body.get("evidence_refs")),a.principalId(),now());bump(trade);
   record(a,"service.trade.dispute.open",trade,Map.of("dispute_id",id,"reason_code",reason),request);return disputeView(id);
  });
 }
 private Map<String,Object> disputeView(UUID id){var row=p.one(DISPUTES+" WHERE d.id=?",id);row.put("evidence_refs",p.json.readValue(row.get("evidence_refs").toString(),List.class));return p.view(row);}
 private static final String DISPUTES="SELECT d.id,d.trade_id,d.version,d.reason_code,d.opened_at,d.evidence_refs,CASE WHEN x.id IS NULL THEN 'OPEN' ELSE 'RESOLVED' END AS state,x.decided_at AS resolved_at,true AS simulated FROM service_trade_disputes d LEFT JOIN service_trade_dispute_decisions x ON x.dispute_id=d.id";
 public List<Map<String,Object>> disputes(Actor a,UUID trade,UUID store,boolean admin,UUID after,int size){
  if(admin){finance.gate();permission(a,Actor.Realm.ADMIN,"service.trade.dispute.review");p.one("SELECT id FROM service_trade_orders WHERE id=?",trade);}else scoped(a,trade,store,"service.trade.dispute.read");limit(size);
  return p.db.queryForList(DISPUTES+" WHERE d.trade_id=? AND d.id>? ORDER BY d.id LIMIT ?",trade,after,size+1).stream().map(row->{row.put("evidence_refs",p.json.readValue(row.get("evidence_refs").toString(),List.class));return p.view(row);}).toList();
 }
 public Map<String,Object> resolve(Actor a,UUID trade,UUID dispute,Map<String,Object> body,String match,String key,String proof,HttpServletRequest request){
  finance.gate();permission(a,Actor.Realm.ADMIN,"service.trade.dispute.review");fields(body,"decision","reason_code","evidence_refs");
  if(!"RESOLVE_NO_FINANCIAL_CHANGE".equals(body.get("decision"))||!"TEST_SCENARIO_REVIEWED".equals(body.get("reason_code")))throw new Failure(400,"VALIDATION_ERROR");evidence(body.get("evidence_refs"));long version=version(match);
  return commands.command(a,"service.trade.dispute.resolve:"+dispute,key,Map.of("body",body,"version",version,"trade_id",trade.toString()),()->{
   finance.gate();permission(a,Actor.Realm.ADMIN,"service.trade.dispute.review");sameVersion(finance.lockTrade(trade,true),version);p.one("SELECT id FROM payments WHERE service_trade_id=? FOR UPDATE",trade);p.one("SELECT id FROM service_trade_disputes WHERE id=? AND trade_id=?",dispute,trade);
   if(!p.db.queryForList("SELECT id FROM service_trade_dispute_decisions WHERE dispute_id=?",dispute).isEmpty())throw new Failure(409,"SERVICE_DISPUTE_ALREADY_RESOLVED");
   auth.consumeProof(a,"service.trade.dispute.review",proof);UUID id=UUID.randomUUID();p.db.update("INSERT INTO service_trade_dispute_decisions(id,dispute_id,trade_id,version,decision,reason_code,evidence_refs,decided_by,decided_at) VALUES (?,?,?,?,'RESOLVE_NO_FINANCIAL_CHANGE','TEST_SCENARIO_REVIEWED',?::jsonb,?,?)",id,dispute,trade,version+1,p.json.writeValueAsString(body.get("evidence_refs")),a.principalId(),now());bump(trade);
   record(a,"service.trade.dispute.resolve",trade,Map.of("dispute_id",dispute,"decision_id",id,"financial_change",false),request);return disputeView(dispute);
  });
 }
}
