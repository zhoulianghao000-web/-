package cn.pawday.ordering;
import static cn.pawday.ordering.OrderService.*;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.payment.RefundService;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.Clock;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** After-sale lifecycle: quantity locked through claims, platform arbitration with reverify, restock once on accepted returns. */
@Service public class AfterSaleService {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final IdempotentCommandExecutor commands;private final RefundService refunds;private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;private final Clock clock;
 private final tools.jackson.databind.json.JsonMapper json=tools.jackson.databind.json.JsonMapper.builder().build();
 public AfterSaleService(JdbcTemplate db,TransactionTemplate tx,IdempotentCommandExecutor commands,RefundService refunds,OutboxWriter outbox,AuditWriter audit,AuthService auth,Clock clock){this.db=db;this.tx=tx;this.commands=commands;this.refunds=refunds;this.outbox=outbox;this.audit=audit;this.auth=auth;this.clock=clock;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->v.put(k,x instanceof Timestamp t?t.toInstant().toString():x));return v;}
 private String correlation(HttpServletRequest r){return r==null?null:(String)r.getAttribute("correlation_id");}
 private boolean scoped(Actor a,UUID sub){return db.queryForObject("SELECT count(*) FROM order_items i WHERE i.suborder_id=? AND ((i.store_id IS NULL AND NOT ?) OR (i.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM principal_store_scope p WHERE p.principal_id=? AND p.merchant_id=i.merchant_id AND p.store_id=i.store_id)))",Integer.class,sub,a.permissions().contains("order.default-scope"),a.principalId())==0;}
 private Map<String,Object> authorize(Actor a,UUID aid,boolean mutation){
  var row=one("SELECT a.* FROM aftersales a WHERE a.id=?",aid);
  if(a.realm()==Actor.Realm.CONSUMER){if(mutation||true){if(!row.get("user_id").equals(a.userId()))throw new Failure(404,"RESOURCE_NOT_FOUND");}}
  else if(a.realm()==Actor.Realm.MERCHANT){permission(a,Actor.Realm.MERCHANT,mutation?"aftersale.handle":"order.read");if(!row.get("merchant_id").equals(a.merchantId())||!scoped(a,(UUID)row.get("suborder_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else{if(mutation)permission(a,Actor.Realm.ADMIN,"aftersale.arbitrate");else permission(a,Actor.Realm.ADMIN,"order.admin.read");}
  return row;
 }
 private void event(UUID aid,String from,String to,String actorType,UUID actorId,String reason){db.update("INSERT INTO aftersale_events(id,aftersale_id,from_status,to_status,actor_type,actor_id,reason) VALUES (?,?,?,?,?,?,?)",UUID.randomUUID(),aid,from,to,actorType,actorId,reason);}
 private void move(UUID aid,String from,String to,Actor a,String reason){
  if(db.update("UPDATE aftersales SET status=?,version=version+1 WHERE id=? AND status=?",to,aid,from)!=1)throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
  event(aid,from,to,a==null?"SYSTEM":a.realm().name(),a==null?null:a.principalId(),reason);
 }
 private long claimUnits(UUID item,int qty,UUID aftersaleItemId){
  var units=db.queryForList("SELECT u.unit_index,u.paid_amount_fen FROM order_item_refund_units u WHERE u.order_item_id=? AND NOT EXISTS(SELECT 1 FROM order_refund_unit_claims c WHERE c.order_item_id=u.order_item_id AND c.unit_index=u.unit_index AND c.status IN ('RESERVED','REFUNDED')) ORDER BY u.unit_index LIMIT ?",item,qty);
  if(units.size()<qty)throw new Failure(409,"REFUND_UNIT_EXHAUSTED");
  long amount=0;for(var u:units){amount+=n(u.get("paid_amount_fen"));db.update("INSERT INTO order_refund_unit_claims(id,order_item_id,unit_index,source_type,source_item_id) VALUES (?,?,?,'AFTERSALE',?)",UUID.randomUUID(),item,u.get("unit_index"),aftersaleItemId);}
  return amount;
 }
 private long claimed(UUID aid){return db.queryForObject("SELECT coalesce(sum(item_payable_refund_fen),0) FROM aftersale_items WHERE aftersale_id=?",Long.class,aid);}
 private void release(UUID aid){db.update("UPDATE order_refund_unit_claims SET status='RELEASED' WHERE source_type='AFTERSALE' AND status='RESERVED' AND refund_id IS NULL AND source_item_id IN (SELECT id FROM aftersale_items WHERE aftersale_id=?)",aid);}
 private void restock(UUID aftersaleItemId,UUID orderItemId,UUID offerId,long qty,String correlation){
  one("SELECT id FROM offers WHERE id=? FOR UPDATE",offerId);
  var stock=one("SELECT * FROM inventory_balances WHERE offer_id=? FOR UPDATE",offerId);
  long before=n(stock.get("on_hand_qty")),version=n(stock.get("version"))+1;
  db.update("UPDATE inventory_balances SET on_hand_qty=?,version=version+1,updated_at=clock_timestamp() WHERE offer_id=?",before+qty,offerId);
  UUID eventId=UUID.randomUUID();
  db.update("INSERT INTO inventory_restock_events(id,source_type,source_id,order_item_id,offer_id,quantity,before_on_hand_qty,resulting_on_hand_qty,resulting_inventory_version) VALUES (?,'AFTERSALE_ITEM',?,?,?,?,?,?,?)",eventId,aftersaleItemId,orderItemId,offerId,qty,before,before+qty,version);
  UUID sku=(UUID)one("SELECT sku_id FROM offers WHERE id=?",offerId).get("sku_id");
  outbox.append("OFFER",offerId.toString(),"InventoryAdjusted",1,Map.of("offer_id",offerId.toString(),"sku_id",sku.toString(),"adjustment_id",eventId.toString(),"inventory_version",version),correlation);
 }
 /** Approved refund intent bound to the collected attempt; zero-amount approvals complete without a channel refund. */
 private UUID approveRefund(Actor a,UUID aid,String from,String reason,HttpServletRequest r){
  long amount=claimed(aid);
  UUID order=(UUID)one("SELECT order_id FROM aftersales WHERE id=?",aid).get("order_id");
  var payment=one("SELECT * FROM payments WHERE order_id=? FOR UPDATE",order);
  UUID refund=refunds.createIntent((UUID)payment.get("id"),null,aid,amount);
  if(refund!=null){db.update("UPDATE aftersale_items SET refund_id=? WHERE aftersale_id=?",refund,aid);db.update("UPDATE order_refund_unit_claims SET refund_id=? WHERE source_type='AFTERSALE' AND source_item_id IN (SELECT id FROM aftersale_items WHERE aftersale_id=?)",refund,aid);move(aid,from,"REFUND_PENDING",a,reason);}
  else{db.update("UPDATE order_refund_unit_claims SET status='REFUNDED' WHERE source_type='AFTERSALE' AND refund_id IS NULL AND source_item_id IN (SELECT id FROM aftersale_items WHERE aftersale_id=?)",aid);move(aid,from,"COMPLETED",a,reason);}
  return refund==null?null:(UUID)payment.get("id");
 }
 public Map<String,Object> get(Actor a,UUID aid){var row=authorize(a,aid,false);return tx.execute(s->{one("SELECT id FROM orders WHERE id=? FOR SHARE",row.get("order_id"));return viewLocked(aid);});}
 private Map<String,Object> viewLocked(UUID aid){
  var result=view(one("SELECT * FROM aftersales WHERE id=?",aid));
  result.put("items",db.queryForList("SELECT * FROM aftersale_items WHERE aftersale_id=? ORDER BY id",aid).stream().map(this::view).toList());
  var refunds=db.queryForList("SELECT * FROM refunds WHERE aftersale_id=? ORDER BY created_at,id",aid);
  result.put("refund",refunds.isEmpty()?null:view(refunds.getFirst()));
  result.put("refund_amount_fen",claimed(aid));
  result.put("evidence",db.queryForList("SELECT id,actor_type,kind,content,asset_id,created_at FROM aftersale_evidence WHERE aftersale_id=? ORDER BY created_at,id",aid).stream().map(this::view).toList());
  result.put("decisions",db.queryForList("SELECT id,decision,reason,amount_fen,created_at FROM aftersale_decisions WHERE aftersale_id=? ORDER BY created_at,id",aid).stream().map(this::view).toList());
  return result;
 }
 public List<Map<String,Object>> list(Actor a,UUID sub){
  var srow=one("SELECT s.*,o.user_id FROM suborders s JOIN orders o ON o.id=s.order_id WHERE s.id=?",sub);
  if(a.realm()==Actor.Realm.CONSUMER){if(!srow.get("user_id").equals(a.userId()))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else if(a.realm()==Actor.Realm.MERCHANT){permission(a,Actor.Realm.MERCHANT,"order.read");if(!srow.get("merchant_id").equals(a.merchantId())||!scoped(a,sub))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else permission(a,Actor.Realm.ADMIN,"order.admin.read");
  return tx.execute(s->{one("SELECT id FROM orders WHERE id=? FOR SHARE",srow.get("order_id"));return db.queryForList("SELECT id FROM aftersales WHERE suborder_id=? ORDER BY created_at,id",sub).stream().map(x->viewLocked((UUID)x.get("id"))).toList();});
 }
 public List<Map<String,Object>> adminList(Actor a,String status,UUID after,int limit){
  permission(a,Actor.Realm.ADMIN,"order.admin.read");if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  if(status!=null&&!Set.of("PENDING_MERCHANT","WAITING_RETURN","RETURN_IN_TRANSIT","WAITING_INSPECTION","REFUND_PENDING","PLATFORM_ESCALATED","COMPLETED","REJECTED","CANCELLED").contains(status))throw new Failure(400,"VALIDATION_ERROR");
  return db.queryForList("SELECT * FROM aftersales WHERE id>? "+(status==null?"":"AND status=?")+" ORDER BY id LIMIT ?",status==null?new Object[]{after,limit+1}:new Object[]{after,status,limit+1}).stream().map(this::view).toList();
 }
 public Map<String,Object> apply(Actor a,UUID sub,Map<String,Object>body,String key,HttpServletRequest r){
  consumer(a);fields(body,"type","reason_code","reason_text","items","evidence");
  if(!Set.of("REFUND_ONLY","RETURN_REFUND").contains(body.get("type"))||!Set.of("QUALITY_ISSUE","WRONG_ITEM","DAMAGED","NOT_RECEIVED","CONSUMER_REGRET","OTHER").contains(body.get("reason_code"))||!(body.get("reason_text") instanceof String text)||text.isBlank()||text.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  if(!(body.get("items") instanceof List<?> items)||items.isEmpty()||items.size()>100)throw new Failure(400,"VALIDATION_ERROR");
  if(!(body.get("evidence") instanceof List<?> evidence)||evidence.size()>9)throw new Failure(400,"VALIDATION_ERROR");
  for(Object x:evidence)if(!(x instanceof Map<?,?> m)||!m.keySet().equals(Set.of("content"))||!(m.get("content") instanceof String c)||c.isBlank()||c.length()>1000)throw new Failure(400,"VALIDATION_ERROR");
  var quantities=new TreeMap<UUID,Integer>(Comparator.comparing(UUID::toString));
  for(Object x:items){if(!(x instanceof Map<?,?> m)||!m.keySet().equals(Set.of("order_item_id","quantity"))||!(m.get("quantity") instanceof Number number)||number.longValue()<1||number.longValue()>100000||number.doubleValue()!=number.longValue())throw new Failure(400,"VALIDATION_ERROR");if(quantities.put(id(m.get("order_item_id")),(int)number.longValue())!=null)throw new Failure(400,"VALIDATION_ERROR");}
  var srow=one("SELECT s.*,o.user_id,o.status order_status FROM suborders s JOIN orders o ON o.id=s.order_id WHERE s.id=?",sub);
  if(!srow.get("user_id").equals(a.userId()))throw new Failure(404,"RESOURCE_NOT_FOUND");
  var aid=commands.command(a,"aftersale.apply:"+sub,key,body,()->{
   UUID order=(UUID)srow.get("order_id");
   one("SELECT id FROM orders WHERE id=? FOR UPDATE",order);one("SELECT id FROM suborders WHERE id=? FOR UPDATE",sub);
   if(!one("SELECT status FROM payments WHERE order_id=?",order).get("status").equals("SUCCEEDED"))throw new Failure(409,"ORDER_NOT_PAID");
   UUID id=UUID.randomUUID();
   db.update("INSERT INTO aftersales(id,suborder_id,order_id,user_id,merchant_id,type,reason_code,reason_text) VALUES (?,?,?,?,?,?,?,?)",id,sub,order,a.userId(),srow.get("merchant_id"),body.get("type"),body.get("reason_code"),text);
   for(var e:quantities.entrySet()){
    var item=one("SELECT * FROM order_items WHERE id=? AND suborder_id=? FOR UPDATE",e.getKey(),sub);
    long shipped=db.queryForObject("SELECT coalesce(sum(quantity),0) FROM shipment_items WHERE order_item_id=?",Long.class,e.getKey());
    long locked=db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE order_item_id=? AND source_type='AFTERSALE' AND status IN ('RESERVED','REFUNDED')",Long.class,e.getKey());
    if(e.getValue()>shipped-locked)throw new Failure(409,"AFTERSALE_QUANTITY_EXCEEDED");
    UUID aftersaleItem=UUID.randomUUID();
    long amount=claimUnits(e.getKey(),e.getValue(),aftersaleItem);
    db.update("INSERT INTO aftersale_items(id,aftersale_id,order_item_id,quantity,item_payable_refund_fen) VALUES (?,?,?,?,?)",aftersaleItem,id,e.getKey(),e.getValue(),amount);
   }
   for(Object x:evidence)db.update("INSERT INTO aftersale_evidence(id,aftersale_id,actor_type,actor_id,kind,content) VALUES (?,?,'CONSUMER',?,'TEXT',?)",UUID.randomUUID(),id,a.principalId(),((Map<?,?>)x).get("content"));
   event(id,"NONE","PENDING_MERCHANT","CONSUMER",a.principalId(),body.get("reason_code").toString());
   outbox.append("AFTERSALE",id.toString(),"AfterSaleCreated",1,Map.of("aftersale_id",id.toString(),"suborder_id",sub.toString(),"order_id",order.toString()),correlation(r));
   audit.write(a,"aftersale.apply","AFTERSALE",id.toString(),Map.of(),Map.of("suborder_id",sub,"type",body.get("type"),"reason_code",body.get("reason_code")),r);
   return Map.of("id",id.toString());
  });
  return get(a,UUID.fromString(aid.get("id").toString()));
 }
 private Map<String,Object> mutate(Actor a,UUID aid,Map<String,Object>body,String match,String key,String action,HttpServletRequest r,java.util.function.Function<Map<String,Object>,UUID> work){
  long expected=version(match);authorize(a,aid,true);
  var held=commands.command(a,action+":"+aid,key,Map.of("body",body,"version",expected),()->{
   var row=authorize(a,aid,true);
   one("SELECT id FROM orders WHERE id=? FOR UPDATE",row.get("order_id"));one("SELECT id FROM suborders WHERE id=? FOR UPDATE",row.get("suborder_id"));
   var locked=one("SELECT * FROM aftersales WHERE id=? FOR UPDATE",aid);
   if(n(locked.get("version"))!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");
   return Map.of("payment",Optional.ofNullable(work.apply(locked)).map(Object::toString).orElse(""),"id",aid.toString());
  });
  String payment=held.get("payment").toString();
  if(!payment.isEmpty())refunds.dueForPayment(UUID.fromString(payment));
  return get(a,aid);
 }
 public Map<String,Object> decide(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  fields(body,"action","reason");if(!(body.get("reason") instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.decide",r,locked->{
   String type=locked.get("type").toString(),action=body.get("action").toString();
   if(!locked.get("status").equals("PENDING_MERCHANT"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   UUID payment=null;
   if(action.equals("APPROVE_REFUND")&&type.equals("REFUND_ONLY"))payment=approveRefund(a,aid,"PENDING_MERCHANT",reason,r);
   else if(action.equals("APPROVE_RETURN")&&type.equals("RETURN_REFUND"))move(aid,"PENDING_MERCHANT","WAITING_RETURN",a,reason);
   else if(action.equals("REJECT"))move(aid,"PENDING_MERCHANT","REJECTED",a,reason);
   else throw new Failure(400,"VALIDATION_ERROR");
   outbox.append("AFTERSALE",aid.toString(),"AfterSaleMerchantDecision",1,Map.of("aftersale_id",aid.toString(),"action",action),correlation(r));
   audit.write(a,"aftersale.decide","AFTERSALE",aid.toString(),Map.of("status","PENDING_MERCHANT"),Map.of("action",action,"reason",reason),r);
   return payment;
  });
 }
 public Map<String,Object> cancel(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  if(!body.isEmpty())throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.cancel",r,locked->{
   String from=locked.get("status").toString();
   if(!Set.of("PENDING_MERCHANT","WAITING_RETURN").contains(from))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   release(aid);move(aid,from,"CANCELLED",a,"CONSUMER_WITHDRAWN");
   audit.write(a,"aftersale.cancel","AFTERSALE",aid.toString(),Map.of("status",from),Map.of("status","CANCELLED"),r);
   return null;
  });
 }
 public Map<String,Object> shipReturn(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  fields(body,"carrier_code","tracking_no");
  if(!(body.get("carrier_code") instanceof String carrier)||!carrier.matches("[A-Z0-9_]{2,24}")||!(body.get("tracking_no") instanceof String tracking)||!tracking.matches("[A-Za-z0-9-]{6,80}"))throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.return-shipment",r,locked->{
   if(!locked.get("status").equals("WAITING_RETURN"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   if(db.update("UPDATE aftersales SET status='RETURN_IN_TRANSIT',return_carrier_code=?,return_tracking_no=?,version=version+1 WHERE id=? AND status='WAITING_RETURN'",carrier,tracking,aid)!=1)throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   event(aid,"WAITING_RETURN","RETURN_IN_TRANSIT",a.realm().name(),a.principalId(),"CONSUMER_RETURN_SHIPPED");
   audit.write(a,"aftersale.return-shipment","AFTERSALE",aid.toString(),Map.of(),Map.of("carrier_code",carrier),r);
   return null;
  });
 }
 public Map<String,Object> confirmArrival(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  if(!body.isEmpty())throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.confirm-arrival",r,locked->{
   if(!locked.get("status").equals("RETURN_IN_TRANSIT"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   move(aid,"RETURN_IN_TRANSIT","WAITING_INSPECTION",a,"MERCHANT_ARRIVAL_CONFIRMED");
   audit.write(a,"aftersale.confirm-arrival","AFTERSALE",aid.toString(),Map.of("status","RETURN_IN_TRANSIT"),Map.of("status","WAITING_INSPECTION"),r);
   return null;
  });
 }
 public Map<String,Object> inspect(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  fields(body,"action","reason");if(!(body.get("reason") instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.inspect",r,locked->{
   if(!locked.get("status").equals("WAITING_INSPECTION"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   String action=body.get("action").toString();UUID payment=null;
   if(action.equals("ACCEPT")){
    for(var item:db.queryForList("SELECT * FROM aftersale_items WHERE aftersale_id=? ORDER BY id",aid))restock((UUID)item.get("id"),(UUID)item.get("order_item_id"),(UUID)one("SELECT offer_id FROM order_items WHERE id=?",item.get("order_item_id")).get("offer_id"),n(item.get("quantity")),correlation(r));
    payment=approveRefund(a,aid,"WAITING_INSPECTION",reason,r);
   }else if(action.equals("REJECT"))move(aid,"WAITING_INSPECTION","REJECTED",a,reason);
   else throw new Failure(400,"VALIDATION_ERROR");
   outbox.append("AFTERSALE",aid.toString(),"AfterSaleInspected",1,Map.of("aftersale_id",aid.toString(),"action",action),correlation(r));
   audit.write(a,"aftersale.inspect","AFTERSALE",aid.toString(),Map.of("status","WAITING_INSPECTION"),Map.of("action",action,"reason",reason),r);
   return payment;
  });
 }
 public Map<String,Object> escalate(Actor a,UUID aid,Map<String,Object>body,String match,String key,HttpServletRequest r){
  fields(body,"reason");if(!(body.get("reason") instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.escalate",r,locked->{
   if(!locked.get("status").equals("REJECTED"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   if(!db.queryForList("SELECT id FROM aftersale_decisions WHERE aftersale_id=?",aid).isEmpty())throw new Failure(409,"AFTERSALE_DECIDED");
   db.update("INSERT INTO aftersale_evidence(id,aftersale_id,actor_type,actor_id,kind,content) VALUES (?,?,'CONSUMER',?,'TEXT',?)",UUID.randomUUID(),aid,a.principalId(),reason);
   move(aid,"REJECTED","PLATFORM_ESCALATED",a,reason);
   outbox.append("AFTERSALE",aid.toString(),"AfterSaleEscalated",1,Map.of("aftersale_id",aid.toString()),correlation(r));
   audit.write(a,"aftersale.escalate","AFTERSALE",aid.toString(),Map.of("status","REJECTED"),Map.of("status","PLATFORM_ESCALATED"),r);
   return null;
  });
 }
 public Map<String,Object> arbitrate(Actor a,UUID aid,Map<String,Object>body,String match,String key,String proof,HttpServletRequest r){
  fields(body,"decision","reason");if(!Set.of("REFUND_APPROVED","REJECTED").contains(body.get("decision"))||!(body.get("reason") instanceof String reason)||reason.isBlank()||reason.length()>500)throw new Failure(400,"VALIDATION_ERROR");
  return mutate(a,aid,body,match,key,"aftersale.arbitrate",r,locked->{
   auth.consumeProof(a,"aftersale.arbitrate",proof);
   if(!locked.get("status").equals("PLATFORM_ESCALATED"))throw new Failure(409,"AFTERSALE_STATE_CONFLICT");
   String decision=body.get("decision").toString();UUID payment=null;long amount=claimed(aid);
   if(decision.equals("REFUND_APPROVED"))payment=approveRefund(a,aid,"PLATFORM_ESCALATED",reason,r);
   else{release(aid);move(aid,"PLATFORM_ESCALATED","REJECTED",a,reason);}
   db.update("INSERT INTO aftersale_decisions(id,aftersale_id,decision,decided_by,reason,amount_fen) VALUES (?,?,?,?,?,?)",UUID.randomUUID(),aid,decision,a.principalId(),reason,decision.equals("REFUND_APPROVED")?amount:0);
   outbox.append("AFTERSALE",aid.toString(),"AfterSaleArbitrated",1,Map.of("aftersale_id",aid.toString(),"decision",decision),correlation(r));
   audit.write(a,"aftersale.arbitrate","AFTERSALE",aid.toString(),Map.of("status","PLATFORM_ESCALATED"),Map.of("decision",decision,"amount_fen",amount),r);
   return payment;
  });
 }
}
