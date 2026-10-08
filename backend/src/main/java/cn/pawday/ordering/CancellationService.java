package cn.pawday.ordering;
import static cn.pawday.ordering.OrderService.*;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
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
import tools.jackson.databind.json.JsonMapper;

/** Paid cancellation of unshipped quantities: frozen-unit quota occupation, one-time restock, original-route refund intent. */
@Service public class CancellationService {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final IdempotentCommandExecutor commands;private final RefundService refunds;private final OutboxWriter outbox;private final AuditWriter audit;private final cn.pawday.settlement.SettlementService settlement;private final Clock clock;
 private final JsonMapper json=JsonMapper.builder().build();
 public CancellationService(JdbcTemplate db,TransactionTemplate tx,IdempotentCommandExecutor commands,RefundService refunds,OutboxWriter outbox,AuditWriter audit,cn.pawday.settlement.SettlementService settlement,Clock clock){this.db=db;this.tx=tx;this.commands=commands;this.refunds=refunds;this.outbox=outbox;this.audit=audit;this.settlement=settlement;this.clock=clock;}
 private Map<String,Object> one(String q,Object...args){var rows=db.queryForList(q,args);if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return rows.getFirst();}
 private long n(Object v){return ((Number)v).longValue();}
 private Map<String,Object> view(Map<String,Object> r){var v=new LinkedHashMap<String,Object>();r.forEach((k,x)->{if(!k.equals("lease_token")&&!k.equals("lease_until"))v.put(k,x instanceof Timestamp t?t.toInstant().toString():x);});return v;}
 private String correlation(HttpServletRequest r){return r==null?null:(String)r.getAttribute("correlation_id");}
 private Map<String,Object> authorize(Actor a,UUID sub){
  var row=one("SELECT s.*,o.user_id,o.status order_status FROM suborders s JOIN orders o ON o.id=s.order_id WHERE s.id=?",sub);
  if(a.realm()==Actor.Realm.CONSUMER){if(!row.get("user_id").equals(a.userId()))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else if(a.realm()==Actor.Realm.MERCHANT){permission(a,Actor.Realm.MERCHANT,"order.read");if(!row.get("merchant_id").equals(a.merchantId()))throw new Failure(404,"RESOURCE_NOT_FOUND");if(!scoped(a,sub))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else permission(a,Actor.Realm.ADMIN,"order.admin.read");
  return row;
 }
 private boolean scoped(Actor a,UUID sub){return db.queryForObject("SELECT count(*) FROM order_items i WHERE i.suborder_id=? AND ((i.store_id IS NULL AND NOT ?) OR (i.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM principal_store_scope p WHERE p.principal_id=? AND p.merchant_id=i.merchant_id AND p.store_id=i.store_id)))",Integer.class,sub,a.permissions().contains("order.default-scope"),a.principalId())==0;}
 private long claimUnits(UUID item,int qty,String sourceType,UUID sourceItemId){
  var units=db.queryForList("SELECT u.unit_index,u.paid_amount_fen FROM order_item_refund_units u WHERE u.order_item_id=? AND NOT EXISTS(SELECT 1 FROM order_refund_unit_claims c WHERE c.order_item_id=u.order_item_id AND c.unit_index=u.unit_index AND c.status IN ('RESERVED','REFUNDED')) ORDER BY u.unit_index LIMIT ?",item,qty);
  if(units.size()<qty)throw new Failure(409,"REFUND_UNIT_EXHAUSTED");
  long amount=0;for(var u:units){amount+=n(u.get("paid_amount_fen"));db.update("INSERT INTO order_refund_unit_claims(id,order_item_id,unit_index,source_type,source_item_id) VALUES (?,?,?,?,?)",UUID.randomUUID(),item,u.get("unit_index"),sourceType,sourceItemId);}
  return amount;
 }
 private void restock(UUID sourceId,String sourceType,UUID orderItemId,UUID offerId,long qty,String correlation){
  one("SELECT id FROM offers WHERE id=? FOR UPDATE",offerId);
  var stock=one("SELECT * FROM inventory_balances WHERE offer_id=? FOR UPDATE",offerId);
  long before=n(stock.get("on_hand_qty")),version=n(stock.get("version"))+1;
  db.update("UPDATE inventory_balances SET on_hand_qty=?,version=version+1,updated_at=clock_timestamp() WHERE offer_id=?",before+qty,offerId);
  UUID event=UUID.randomUUID();
  db.update("INSERT INTO inventory_restock_events(id,source_type,source_id,order_item_id,offer_id,quantity,before_on_hand_qty,resulting_on_hand_qty,resulting_inventory_version) VALUES (?,?,?,?,?,?,?,?,?)",event,sourceType,sourceId,orderItemId,offerId,qty,before,before+qty,version);
  UUID sku=(UUID)one("SELECT sku_id FROM offers WHERE id=?",offerId).get("sku_id");
  outbox.append("OFFER",offerId.toString(),"InventoryAdjusted",1,Map.of("offer_id",offerId.toString(),"sku_id",sku.toString(),"adjustment_id",event.toString(),"inventory_version",version),correlation);
 }
 private void recompute(UUID order,UUID sub){
  long total=db.queryForObject("SELECT coalesce(sum(quantity-cancelled_qty),0) FROM order_items WHERE suborder_id=?",Long.class,sub),shipped=db.queryForObject("SELECT coalesce(sum(quantity),0) FROM shipment_items WHERE suborder_id=?",Long.class,sub),received=db.queryForObject("SELECT coalesce(sum(i.quantity),0) FROM shipment_items i JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.suborder_id=?",Long.class,sub);
  String state=total==0?"CANCELLED":received==total?"COMPLETED":received>0?"PARTIALLY_COMPLETED":shipped==total?"SHIPPED_WAITING_RECEIPT":shipped>0?"PARTIALLY_SHIPPED":"PAID_WAITING_FULFILLMENT";
  db.update("UPDATE suborders SET fulfillment_status=?,version=version+1 WHERE id=?",state,sub);
  if(state.equals("COMPLETED"))settlement.beginBuffering(sub);else if(state.equals("CANCELLED"))settlement.onSuborderCancelled(sub);
  db.update("UPDATE orders SET version=version+1 WHERE id=?",order);
  if(db.queryForObject("SELECT count(*) FROM suborders WHERE order_id=? AND fulfillment_status<>'CANCELLED'",Integer.class,order)==0)db.update("UPDATE orders SET status='CANCELLED',version=version+1 WHERE id=?",order);
 }
 private void event(UUID cid,String from,String to,String reason){db.update("INSERT INTO order_cancellation_events(id,cancellation_id,from_status,to_status,reason_code) VALUES (?,?,?,?,?)",UUID.randomUUID(),cid,from,to,reason);}

 public Map<String,Object> create(Actor a,UUID sub,Map<String,Object>body,String key,HttpServletRequest r){
  boolean merchant=a.realm()==Actor.Realm.MERCHANT;
  if(merchant)permission(a,Actor.Realm.MERCHANT,"order.cancel.handle");else if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");
  fields(body,"items","reason_code");
  String reason=merchant?"MERCHANT_OUT_OF_STOCK":"CONSUMER_CANCELLED";
  if(!reason.equals(body.get("reason_code")))throw new Failure(400,"VALIDATION_ERROR");
  if(!(body.get("items") instanceof List<?> items)||items.isEmpty()||items.size()>100)throw new Failure(400,"VALIDATION_ERROR");
  var quantities=new TreeMap<UUID,Integer>(Comparator.comparing(UUID::toString));
  for(Object x:items){if(!(x instanceof Map<?,?> m)||!m.keySet().equals(Set.of("order_item_id","quantity"))||!(m.get("quantity") instanceof Number number)||number.longValue()<1||number.longValue()>100000||number.doubleValue()!=number.longValue())throw new Failure(400,"VALIDATION_ERROR");if(quantities.put(id(m.get("order_item_id")),(int)number.longValue())!=null)throw new Failure(400,"VALIDATION_ERROR");}
  authorize(a,sub);
  var held=commands.command(a,"cancellation.create:"+sub,key,body,()->{
   var subrow=one("SELECT s.*,o.user_id,o.status order_status FROM suborders s JOIN orders o ON o.id=s.order_id WHERE s.id=?",sub);
   UUID order=(UUID)subrow.get("order_id");
   if(!subrow.get("order_status").equals("FULFILLING"))throw new Failure(409,"ORDER_NOT_PAID");
   one("SELECT id FROM orders WHERE id=? FOR UPDATE",order);one("SELECT id FROM suborders WHERE id=? FOR UPDATE",sub);
   var payment=one("SELECT * FROM payments WHERE order_id=? FOR UPDATE",order);
   if(!payment.get("status").equals("SUCCEEDED"))throw new Failure(409,"ORDER_NOT_PAID");
   UUID cid=UUID.randomUUID();
   db.update("INSERT INTO order_cancellations(id,order_id,suborder_id,actor_type,actor_id,reason_code,status) VALUES (?,?,?,?,?,?,'ACCEPTED')",cid,order,sub,merchant?"MERCHANT":"CONSUMER",a.principalId(),reason);
   event(cid,"REQUESTED","ACCEPTED",reason);
   record Item(UUID itemId,UUID cancellationItemId,int qty,long amount){}
   var lines=new ArrayList<Item>();long goods=0;
   for(var e:quantities.entrySet()){
    var item=one("SELECT * FROM order_items WHERE id=? AND suborder_id=? FOR UPDATE",e.getKey(),sub);
    long shipped=db.queryForObject("SELECT coalesce(sum(quantity),0) FROM shipment_items WHERE order_item_id=?",Long.class,e.getKey());
    if(e.getValue()>n(item.get("quantity"))-n(item.get("cancelled_qty"))-shipped)throw new Failure(409,"CANCELLATION_QUANTITY_EXCEEDED");
    UUID cancellationItem=UUID.randomUUID();
    long amount=claimUnits(e.getKey(),e.getValue(),"CANCELLATION",cancellationItem);
    lines.add(new Item(e.getKey(),cancellationItem,e.getValue(),amount));goods+=amount;
   }
   // Whole-suborder cancellation of unshipped quantities refunds the frozen shipping share once.
   long requested=quantities.values().stream().mapToLong(Integer::longValue).sum();
   long effective=db.queryForObject("SELECT coalesce(sum(quantity-cancelled_qty),0) FROM order_items WHERE suborder_id=?",Long.class,sub);
   boolean wholeSuborder=effective==requested&&db.queryForObject("SELECT count(*) FROM shipment_items WHERE suborder_id=?",Integer.class,sub)==0;
   long shipping=wholeSuborder?n(subrow.get("payable_amount_fen"))-db.queryForObject("SELECT coalesce(sum(payable_amount_fen),0) FROM order_items WHERE suborder_id=?",Long.class,sub):0;
   long total=goods+shipping;
   UUID refund=refunds.createIntent((UUID)payment.get("id"),cid,null,total);
   boolean shippingAttached=false;
   for(var line:lines){
    long shippingShare=!shippingAttached&&shipping>0?shipping:0;shippingAttached=true;
    db.update("INSERT INTO order_cancellation_items(id,cancellation_id,order_item_id,quantity,item_payable_refund_fen,shipping_refund_fen,allocation_snapshot,refund_id) VALUES (?,?,?,?,?,?,?::jsonb,?)",line.cancellationItemId(),cid,line.itemId(),line.qty(),line.amount(),shippingShare,json.writeValueAsString(Map.of("units_frozen",line.amount(),"shipping_frozen",shippingShare)),refund);
    db.update("UPDATE order_refund_unit_claims SET refund_id=? WHERE source_type='CANCELLATION' AND source_item_id=?",refund,line.cancellationItemId());
    restock(line.cancellationItemId(),"CANCELLATION_ITEM",line.itemId(),(UUID)one("SELECT offer_id FROM order_items WHERE id=?",line.itemId()).get("offer_id"),line.qty(),correlation(r));
    db.update("UPDATE order_items SET cancelled_qty=cancelled_qty+? WHERE id=?",line.qty(),line.itemId());
   }
   if(refund!=null){event(cid,"ACCEPTED","REFUND_PENDING",reason);db.update("UPDATE order_cancellations SET status='REFUND_PENDING',version=version+1 WHERE id=?",cid);}
   else{db.update("UPDATE order_refund_unit_claims SET status='REFUNDED' WHERE source_type='CANCELLATION' AND refund_id IS NULL AND source_item_id IN (SELECT id FROM order_cancellation_items WHERE cancellation_id=?)",cid);event(cid,"ACCEPTED","COMPLETED",reason);db.update("UPDATE order_cancellations SET status='COMPLETED',version=version+1 WHERE id=?",cid);refunds.returnCoupons(cid,order);}
   recompute(order,sub);
   outbox.append("ORDER",order.toString(),"CancellationRecorded",1,Map.of("order_id",order.toString(),"suborder_id",sub.toString(),"cancellation_id",cid.toString(),"amount_fen",total),correlation(r));
   audit.write(a,merchant?"order.cancel.merchant":"order.cancel.paid","ORDER_CANCELLATION",cid.toString(),Map.of(),Map.of("suborder_id",sub,"amount_fen",total,"reason_code",reason),r);
   return Map.of("cancellation_id",cid.toString(),"payment_id",payment.get("id").toString());
  });
  refunds.dueForPayment(UUID.fromString(held.get("payment_id").toString()));
  return get(a,UUID.fromString(held.get("cancellation_id").toString()));
 }
 public Map<String,Object> get(Actor a,UUID cid){
  var row=one("SELECT * FROM order_cancellations WHERE id=?",cid);
  if(row.get("suborder_id")!=null)authorize(a,(UUID)row.get("suborder_id"));else if(a.realm()==Actor.Realm.CONSUMER){if(!one("SELECT user_id FROM orders WHERE id=?",row.get("order_id")).get("user_id").equals(a.userId()))throw new Failure(404,"RESOURCE_NOT_FOUND");}else if(a.realm()==Actor.Realm.MERCHANT)throw new Failure(404,"RESOURCE_NOT_FOUND");else permission(a,Actor.Realm.ADMIN,"order.admin.read");
  return tx.execute(s->{one("SELECT id FROM orders WHERE id=? FOR SHARE",row.get("order_id"));return viewLocked(cid);});
 }
 private Map<String,Object> viewLocked(UUID cid){
  var result=view(one("SELECT * FROM order_cancellations WHERE id=?",cid));
  result.put("items",db.queryForList("SELECT * FROM order_cancellation_items WHERE cancellation_id=? ORDER BY id",cid).stream().map(this::view).toList());
  var refunds=db.queryForList("SELECT r.* FROM refunds r WHERE r.cancellation_id=? ORDER BY r.created_at,r.id",cid);
  result.put("refund",refunds.isEmpty()?null:view(refunds.getFirst()));
  result.put("refund_amount_fen",db.queryForObject("SELECT coalesce(sum(item_payable_refund_fen+shipping_refund_fen),0) FROM order_cancellation_items WHERE cancellation_id=?",Long.class,cid));
  return result;
 }
 public List<Map<String,Object>> list(Actor a,UUID sub){
  var row=authorize(a,sub);
  return tx.execute(s->{one("SELECT id FROM orders WHERE id=? FOR SHARE",row.get("order_id"));return db.queryForList("SELECT id FROM order_cancellations WHERE suborder_id=? ORDER BY created_at,id",sub).stream().map(x->viewLocked((UUID)x.get("id"))).toList();});
 }
 public List<Map<String,Object>> adminList(Actor a,UUID after,int limit){
  permission(a,Actor.Realm.ADMIN,"order.admin.read");if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");
  return db.queryForList("SELECT * FROM order_cancellations WHERE id>? ORDER BY id LIMIT ?",after,limit+1).stream().map(this::view).toList();
 }
}
