package cn.pawday.offer;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.outbox.OutboxWriter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Service
public class OfferService {
 private final JdbcTemplate db; private final AccessGuard guard; private final AuthService auth;
 private final AuditWriter audit; private final OutboxWriter outbox; private final IdempotentCommandExecutor commands;
 private final TransactionTemplate tx; private final Crypto crypto;
 private final JsonMapper json=JsonMapper.builder().build();
 public OfferService(JdbcTemplate db,AccessGuard guard,AuthService auth,AuditWriter audit,OutboxWriter outbox,
   IdempotentCommandExecutor commands,TransactionTemplate tx,Crypto crypto){
  this.db=db;this.guard=guard;this.auth=auth;this.audit=audit;this.outbox=outbox;this.commands=commands;this.tx=tx;this.crypto=crypto;
 }
 public record Page(List<Map<String,Object>> data,String cursor,boolean more) {}
 private static void check(boolean condition){if(!condition)throw new Failure(400,"VALIDATION_ERROR");}
 private static String text(Object x,int max){check(x instanceof String&&!((String)x).isBlank()&&((String)x).length()<=max);return ((String)x).trim();}
 private static UUID id(Object x){try{return UUID.fromString(String.valueOf(x));}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 private static long number(Object x,long min,long max){check(x instanceof Integer||x instanceof Long);long n=((Number)x).longValue();check(n>=min&&n<=max);return n;}
 private static void fields(Map<String,Object> b,String... names){check(b.keySet().equals(Set.of(names)));}
 private static long version(String match){if(match==null||!match.matches("\"[0-9]{1,18}\""))throw new Failure(400,"VERSION_REQUIRED");return Long.parseLong(match.substring(1,match.length()-1));}
 private void permission(Actor a,boolean admin,String code){if(a.realm()!=(admin?Actor.Realm.ADMIN:Actor.Realm.MERCHANT)||!a.permissions().contains(code))throw new Failure(403,"PERMISSION_DENIED");}
 private void scope(Actor a,UUID merchant,UUID store){
  if(a.realm()==Actor.Realm.ADMIN)return;
  if(!merchant.equals(a.merchantId()))throw new Failure(404,"RESOURCE_NOT_FOUND");
  if(store==null){if(!a.permissions().contains("offer.default-scope"))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else guard.store(a,store);
 }
 private Map<String,Object> row(Actor a,UUID offer,boolean lock){
  var rows=db.queryForList("SELECT * FROM offers WHERE id=?"+(lock?" FOR UPDATE":""),offer);
  if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var result=rows.getFirst();scope(a,(UUID)result.get("merchant_id"),(UUID)result.get("store_id"));return result;
 }
 private void current(Map<String,Object> row,long expected){if(((Number)row.get("version")).longValue()!=expected)throw new Failure(409,"CONCURRENT_MODIFICATION");}
 private void merchantActive(UUID merchant){if(db.queryForObject("SELECT count(*) FROM merchant WHERE id=? AND status='ACTIVE'",Integer.class,merchant)==0)throw new Failure(409,"MERCHANT_UNAVAILABLE");}
 private void catalogActive(UUID sku){if(db.queryForObject("SELECT count(*) FROM skus k JOIN spus p ON p.id=k.spu_id JOIN brands b ON b.id=p.brand_id WHERE k.id=? AND k.status='ACTIVE' AND p.status='ACTIVE' AND b.status='ACTIVE' AND EXISTS(SELECT 1 FROM sku_standard_versions v WHERE v.sku_id=k.id AND v.status='PUBLISHED')",Integer.class,sku)==0)throw new Failure(422,"CATALOG_NOT_PUBLISHED");}
 private void prices(Object sale,Object member){long n=number(sale,1,1000000000);if(member!=null)number(member,1,n);}
 private Map<String,Object> snapshot(Map<String,Object> o){var result=new LinkedHashMap<>(o);result.put("inventory",db.queryForMap("SELECT * FROM inventory_balances WHERE offer_id=?",o.get("id")));result.put("sku_code",db.queryForObject("SELECT sku_code FROM skus WHERE id=?",String.class,o.get("sku_id")));result.put("merchant_name",db.queryForObject("SELECT name FROM merchant WHERE id=?",String.class,o.get("merchant_id")));result.put("store_name",o.get("store_id")==null?null:db.queryForObject("SELECT name FROM merchant_store WHERE id=?",String.class,o.get("store_id")));return result;}
 private void changed(Actor a,String action,Map<String,Object> before,Map<String,Object> after,HttpServletRequest r){
  audit.write(a,action,"OFFER",after.get("id").toString(),before,after,r);
  outbox.append("OFFER",after.get("id").toString(),"OfferStateChanged",1,
    Map.of("offer_id",after.get("id").toString(),"sku_id",after.get("sku_id").toString(),"version",after.get("version")),r==null?null:(String)r.getAttribute("correlation_id"));
 }
 public Page list(Actor a,boolean admin,UUID store,String cursor,int limit){
  permission(a,admin,admin?"offer.admin.read":"offer.read");check(limit>0&&limit<=100);UUID after=cursor==null?new UUID(0,0):id(cursor);
  List<Map<String,Object>> rows;
  if(admin)rows=db.queryForList("SELECT * FROM offers WHERE id>? ORDER BY id LIMIT ?",after,limit+1);
  else {if(store!=null)scope(a,a.merchantId(),store);
   rows=db.queryForList("SELECT o.* FROM offers o WHERE o.merchant_id=? AND o.id>? AND (?::uuid IS NULL OR o.store_id=?) AND ((o.store_id IS NULL AND ?) OR EXISTS(SELECT 1 FROM principal_store_scope s WHERE s.principal_id=? AND s.merchant_id=o.merchant_id AND s.store_id=o.store_id)) ORDER BY o.id LIMIT ?",a.merchantId(),after,store,store,a.permissions().contains("offer.default-scope"),a.principalId(),limit+1);
  }
  boolean more=rows.size()>limit;var data=rows.stream().limit(limit).map(this::snapshot).toList();return new Page(data,more?data.getLast().get("id").toString():null,more);
 }
 public Map<String,Object> get(Actor a,boolean admin,UUID offer){permission(a,admin,admin?"offer.admin.read":"offer.read");return tx.execute(s->snapshot(row(a,offer,true)));}
 public Map<String,Object> create(Actor a,Map<String,Object>b,String key,HttpServletRequest r){
  permission(a,false,"offer.write");fields(b,"store_id","sku_id","sale_price_fen","member_price_fen","fulfillment_sla");UUID store=b.get("store_id")==null?null:id(b.get("store_id")),sku=id(b.get("sku_id"));scope(a,a.merchantId(),store);prices(b.get("sale_price_fen"),b.get("member_price_fen"));String sla=text(b.get("fulfillment_sla"),500);
  return commands.command(a,"offer.create",key,b,()->{
   scope(a,a.merchantId(),store);merchantActive(a.merchantId());catalogActive(sku);
   db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","offer:"+a.merchantId()+":"+sku+":"+store);
   if(db.queryForObject("SELECT count(*) FROM offers WHERE merchant_id=? AND sku_id=? AND store_id IS NOT DISTINCT FROM ?::uuid AND sale_status<>'DELISTED'",Integer.class,a.merchantId(),sku,store)>0)throw new Failure(409,"OFFER_ALREADY_EXISTS");
   UUID offer=UUID.randomUUID();db.update("INSERT INTO offers(id,merchant_id,store_id,sku_id,sale_price_fen,member_price_fen,fulfillment_sla) VALUES (?,?,?,?,?,?,?)",offer,a.merchantId(),store,sku,b.get("sale_price_fen"),b.get("member_price_fen"),sla);
   db.update("INSERT INTO inventory_balances(offer_id) VALUES (?)",offer);var result=snapshot(row(a,offer,false));changed(a,"offer.create",Map.of(),result,r);return result;
  });
 }
 private Map<String,Object> patchLocked(Actor a,UUID offer,Map<String,Object>b,long expected,HttpServletRequest r){
  var old=row(a,offer,true);current(old,expected);merchantActive(a.merchantId());
  if(Set.of("FROZEN","DELISTED").contains(old.get("sale_status")))throw new Failure(409,"OFFER_NOT_EDITABLE");
  check(!b.isEmpty()&&Set.of("sale_price_fen","member_price_fen","fulfillment_sla").containsAll(b.keySet()));
  Object sale=b.getOrDefault("sale_price_fen",old.get("sale_price_fen")),member=b.containsKey("member_price_fen")?b.get("member_price_fen"):old.get("member_price_fen");prices(sale,member);
  String sla=b.containsKey("fulfillment_sla")?text(b.get("fulfillment_sla"),500):old.get("fulfillment_sla").toString();
  db.update("UPDATE offers SET sale_price_fen=?,member_price_fen=?,fulfillment_sla=?,version=version+1,updated_at=clock_timestamp() WHERE id=?",sale,member,sla,offer);
  var result=snapshot(row(a,offer,false));changed(a,"offer.patch",old,result,r);return result;
 }
 public Map<String,Object> patch(Actor a,UUID offer,Map<String,Object>b,String match,String key,HttpServletRequest r){
  permission(a,false,"offer.write");row(a,offer,false);long expected=version(match);
  return commands.command(a,"offer.patch:"+offer,key,Map.of("body",b,"version",expected),()->patchLocked(a,offer,b,expected,r));
 }
 public Map<String,Object> batch(Actor a,Map<String,Object>b,String key,HttpServletRequest r){
  permission(a,false,"offer.write");fields(b,"items");check(b.get("items") instanceof List<?>);var input=(List<?>)b.get("items");check(!input.isEmpty()&&input.size()<=50);
  var items=new TreeMap<UUID,Map<String,Object>>();for(Object x:input){check(x instanceof Map<?,?>);var item=(Map<String,Object>)x;fields(item,"offer_id","expected_version","changes");UUID offer=id(item.get("offer_id"));check(items.put(offer,item)==null);row(a,offer,false);number(item.get("expected_version"),0,9007199254740991L);check(item.get("changes") instanceof Map<?,?>);}
  return commands.command(a,"offer.batch",key,b,()->{var result=new ArrayList<Map<String,Object>>();for(var entry:items.entrySet()){var item=entry.getValue();result.add(patchLocked(a,entry.getKey(),(Map<String,Object>)item.get("changes"),((Number)item.get("expected_version")).longValue(),r));}return Map.of("items",result);});
 }
 public Map<String,Object> state(Actor a,boolean admin,UUID offer,String action,Map<String,Object>b,String match,String proof,String key,HttpServletRequest r){
  permission(a,admin,admin?"offer.admin.manage":"offer.write");row(a,offer,false);long expected=version(match);fields(b,"reason");String reason=text(b.get("reason"),2000);
  return commands.command(a,"offer."+action+":"+offer,key,Map.of("version",expected,"reason",reason),()->{
   var old=row(a,offer,true);current(old,expected);String status=old.get("sale_status").toString();String next;
   if(admin){auth.consumeProof(a,"offer.admin.manage",proof);
    next=switch(action){case "freeze"->{if(Set.of("FROZEN","DELISTED").contains(status))throw new Failure(409,"OFFER_STATE_CONFLICT");yield "FROZEN";}case "unfreeze"->{if(!status.equals("FROZEN"))throw new Failure(409,"OFFER_STATE_CONFLICT");yield "PAUSED";}case "delist"->{if(status.equals("DELISTED"))throw new Failure(409,"OFFER_STATE_CONFLICT");yield "DELISTED";}default->throw new Failure(404,"RESOURCE_NOT_FOUND");};
   }else {merchantActive(a.merchantId());next=switch(action){case "activate"->{if(!Set.of("DRAFT","PAUSED").contains(status))throw new Failure(409,"OFFER_STATE_CONFLICT");catalogActive((UUID)old.get("sku_id"));yield "ACTIVE";}case "pause"->{if(!status.equals("ACTIVE"))throw new Failure(409,"OFFER_STATE_CONFLICT");yield "PAUSED";}default->throw new Failure(404,"RESOURCE_NOT_FOUND");};}
   db.update("UPDATE offers SET sale_status=?,version=version+1,updated_at=clock_timestamp() WHERE id=?",next,offer);var result=snapshot(row(a,offer,false));var before=new LinkedHashMap<>(old);before.put("reason",reason);changed(a,"offer."+action,before,result,r);return result;
  });
 }
 public Map<String,Object> adjust(Actor a,UUID offer,Map<String,Object>b,String key,HttpServletRequest r){
  permission(a,false,"inventory.adjust");row(a,offer,false);fields(b,"delta_qty","reason_code","expected_version");long delta=number(b.get("delta_qty"),-1000000000,1000000000),expected=number(b.get("expected_version"),0,9007199254740991L);check(delta!=0);String reason=text(b.get("reason_code"),32);check(Set.of("RESTOCK","COUNT_CORRECTION","DAMAGE").contains(reason));
  if(key==null||key.length()<16||key.length()>128)throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");var canonical=new TreeMap<>(b);canonical.put("offer_id",offer.toString());String hash=crypto.hash(json.writeValueAsString(canonical));
  return tx.execute(s->{
   db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","inventory-adjustment:"+a.merchantId()+":"+key);
   var old=row(a,offer,true);var prior=db.queryForList("SELECT * FROM inventory_adjustments WHERE merchant_id=? AND idempotency_key=?",a.merchantId(),key);
   if(!prior.isEmpty()){if(!hash.equals(prior.getFirst().get("payload_hash")))throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");return adjustmentResult(prior.getFirst());}
   merchantActive(a.merchantId());if(old.get("sale_status").equals("DELISTED"))throw new Failure(409,"OFFER_NOT_EDITABLE");
   var balance=db.queryForMap("SELECT * FROM inventory_balances WHERE offer_id=? FOR UPDATE",offer);current(balance,expected);long before=((Number)balance.get("on_hand_qty")).longValue(),reserved=((Number)balance.get("reserved_qty")).longValue(),after=before+delta;
   if(after<reserved||after>1000000000)throw new Failure(409,"INVENTORY_ADJUSTMENT_CONFLICT");UUID adjustment=UUID.randomUUID();
   db.update("INSERT INTO inventory_adjustments(id,merchant_id,offer_id,delta_qty,reason_code,expected_version,before_on_hand_qty,resulting_on_hand_qty,resulting_reserved_qty,resulting_version,actor_id,idempotency_key,payload_hash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",adjustment,a.merchantId(),offer,delta,reason,expected,before,after,reserved,expected+1,a.principalId(),key,hash);
   db.update("UPDATE inventory_balances SET on_hand_qty=?,version=version+1,updated_at=clock_timestamp() WHERE offer_id=?",after,offer);
   var result=adjustmentResult(db.queryForMap("SELECT * FROM inventory_adjustments WHERE id=?",adjustment));audit.write(a,"inventory.adjust","INVENTORY_ADJUSTMENT",adjustment.toString(),balance,Map.of("reason_code",reason,"delta_qty",delta,"on_hand_qty",after,"reserved_qty",reserved,"version",expected+1),r);
   outbox.append("OFFER",offer.toString(),"InventoryAdjusted",1,Map.of("offer_id",offer.toString(),"sku_id",old.get("sku_id").toString(),"adjustment_id",adjustment.toString(),"inventory_version",expected+1),r==null?null:(String)r.getAttribute("correlation_id"));return result;
  });
 }
 private Map<String,Object> adjustmentResult(Map<String,Object> row){long on=((Number)row.get("resulting_on_hand_qty")).longValue(),reserved=((Number)row.get("resulting_reserved_qty")).longValue();return Map.of("adjustment_id",row.get("id"),"offer_id",row.get("offer_id"),"delta_qty",row.get("delta_qty"),"resulting_on_hand_qty",on,"resulting_reserved_qty",reserved,"resulting_available_qty",on-reserved,"version",row.get("resulting_version"));}
 public Page adjustments(Actor a,boolean admin,UUID offer,String cursor,int limit){permission(a,admin,admin?"offer.admin.read":"offer.read");row(a,offer,false);check(limit>0&&limit<=100);UUID after=cursor==null?new UUID(0,0):id(cursor);var rows=db.queryForList("SELECT id,offer_id,delta_qty,reason_code,expected_version,before_on_hand_qty,resulting_on_hand_qty,resulting_reserved_qty,resulting_version,actor_id,created_at FROM inventory_adjustments WHERE offer_id=? AND id>? ORDER BY id LIMIT ?",offer,after,limit+1);boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Page(data,more?data.getLast().get("id").toString():null,more);}
}
