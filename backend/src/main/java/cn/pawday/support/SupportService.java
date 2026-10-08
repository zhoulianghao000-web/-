package cn.pawday.support;

import cn.pawday.common.*;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.stereotype.Service;

/** PostgreSQL is the message fact source; only identifiers leave through Outbox. */
@Service
public class SupportService {
 private final PublishingSupport p;private final AccessGuard guard;private final IdempotentCommandExecutor commands;
 private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;
 public SupportService(PublishingSupport p,AccessGuard guard,IdempotentCommandExecutor commands,OutboxWriter outbox,AuditWriter audit,AuthService auth){this.p=p;this.guard=guard;this.commands=commands;this.outbox=outbox;this.audit=audit;this.auth=auth;}
 private void staff(Actor a,String permission){if(a.realm()==Actor.Realm.CONSUMER||!a.permissions().contains(permission))throw new Failure(403,"PERMISSION_DENIED");}
 private Map<String,Object> scoped(Actor a,UUID id,boolean lock,boolean participant){
  var row=p.one("SELECT * FROM conversations WHERE id=?"+(lock?" FOR UPDATE":""),id);
  if(a.realm()==Actor.Realm.CONSUMER){if(!a.principalId().equals(row.get("consumer_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");}
  else{staff(a,"support.read");if(a.realm()==Actor.Realm.ADMIN){if(!row.get("kind").equals("PLATFORM"))throw new Failure(404,"RESOURCE_NOT_FOUND");}
   else{if(!a.merchantId().equals(row.get("merchant_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");guard.store(a,(UUID)row.get("store_id"));}
   if(participant&&!a.principalId().equals(row.get("assigned_principal_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");
  }
  if(participant&&p.db.queryForObject("SELECT count(*) FROM conversation_participants WHERE conversation_id=? AND principal_id=? AND active",Integer.class,id,a.principalId())!=1)throw new Failure(404,"RESOURCE_NOT_FOUND");
  return row;
 }
 private Map<String,Object> view(Actor a,Map<String,Object> row){
  var result=new LinkedHashMap<String,Object>();for(String k:List.of("id","kind","store_id","status","last_sequence","delivered_sequence","version","created_at","updated_at"))result.put(k,row.get(k));
  result.put("assigned_to_me",a.principalId().equals(row.get("assigned_principal_id")));result.put("assigned",row.get("assigned_principal_id")!=null);
  long read=Optional.ofNullable(p.db.queryForList("SELECT read_sequence FROM conversation_participants WHERE conversation_id=? AND principal_id=? AND active",Long.class,row.get("id"),a.principalId()).stream().findFirst().orElse(null)).orElse(0L);
  result.put("read_sequence",read);result.put("unread_count",p.db.queryForObject("SELECT count(*) FROM conversation_messages WHERE conversation_id=? AND sequence>? AND sender_id<>?",Long.class,row.get("id"),read,a.principalId()));return p.view(result);
 }
 public Map<String,Object> detail(Actor a,UUID id){return view(a,scoped(a,id,false,true));}
 public List<Map<String,Object>> list(Actor a,UUID store,UUID after,int limit){limit(limit);String filter;Object owner;
  if(a.realm()==Actor.Realm.CONSUMER){filter="consumer_id=?";owner=a.principalId();}
  else{staff(a,"support.read");if(a.realm()==Actor.Realm.MERCHANT){if(store==null)throw new Failure(400,"STORE_SCOPE_REQUIRED");guard.store(a,store);filter="kind='MERCHANT' AND merchant_id=? AND store_id='"+store+"'";owner=a.merchantId();}else{filter="kind='PLATFORM' AND ?::uuid IS NOT NULL";owner=a.principalId();}}
  return p.db.queryForList("SELECT * FROM conversations WHERE "+filter+" AND id>? ORDER BY id LIMIT ?",owner,after,limit+1).stream().map(row->view(a,row)).toList();
 }
 public Map<String,Object> create(Actor a,Map<String,Object>b,String key,HttpServletRequest r){if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");fields(b,"kind","store_id");String kind=text(b.get("kind"),12);UUID store=b.get("store_id")==null?null:id(b.get("store_id"));if(!Set.of("PLATFORM","MERCHANT").contains(kind)||kind.equals("PLATFORM")!=(store==null))throw new Failure(400,"VALIDATION_ERROR");
  var result=commands.command(a,"support.create",key,b,()->{
   p.db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.principalId()+":"+kind+":"+store);
   UUID merchant=null;if(store!=null)merchant=(UUID)p.one("SELECT s.merchant_id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND m.status='ACTIVE'",store).get("merchant_id");
   var existing=p.db.queryForList("SELECT id FROM conversations WHERE consumer_id=? AND kind=? AND store_id IS NOT DISTINCT FROM ?",a.principalId(),kind,store);UUID cid=existing.isEmpty()?UUID.randomUUID():(UUID)existing.getFirst().get("id");
   if(existing.isEmpty()){p.db.update("INSERT INTO conversations(id,consumer_id,kind,merchant_id,store_id) VALUES (?,?,?,?,?)",cid,a.principalId(),kind,merchant,store);p.db.update("INSERT INTO conversation_participants(conversation_id,principal_id) VALUES (?,?)",cid,a.principalId());audit.write(a,"support.create","CONVERSATION",cid.toString(),Map.of(),Map.of("kind",kind),r);}
   return Map.of("id",cid.toString());});return detail(a,id(result.get("id")));
 }
 public Map<String,Object> assign(Actor a,UUID cid,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){staff(a,"support.assign");fields(b,"principal_id","reason");UUID target=id(b.get("principal_id"));String reason=text(b.get("reason"),500);long expected=version(match);scoped(a,cid,false,false);
  commands.command(a,"support.assign:"+cid,key,Map.of("body",b,"version",expected),()->{var row=scoped(a,cid,true,false);sameVersion(row,expected);
   String realm=a.realm().name();int valid=p.db.queryForObject("SELECT count(*) FROM identity_principal ip WHERE ip.id=? AND ip.realm=? AND ip.status='ACTIVE' AND ip.merchant_id IS NOT DISTINCT FROM ? AND EXISTS (SELECT 1 FROM principal_role pr JOIN role_permission rp ON rp.role_id=pr.role_id JOIN permission pe ON pe.id=rp.permission_id WHERE pr.principal_id=ip.id AND pr.realm=ip.realm AND pe.code='support.read') AND EXISTS (SELECT 1 FROM principal_role pr JOIN role_permission rp ON rp.role_id=pr.role_id JOIN permission pe ON pe.id=rp.permission_id WHERE pr.principal_id=ip.id AND pr.realm=ip.realm AND pe.code='support.reply')",Integer.class,target,realm,a.merchantId());
   if(valid!=1||a.realm()==Actor.Realm.MERCHANT&&p.db.queryForObject("SELECT count(*) FROM principal_store_scope WHERE principal_id=? AND merchant_id=? AND store_id=?",Integer.class,target,a.merchantId(),row.get("store_id"))!=1)throw new Failure(404,"RESOURCE_NOT_FOUND");
   auth.consumeProof(a,"support.assign",proof);p.db.update("UPDATE conversation_participants SET active=false WHERE conversation_id=? AND principal_id<>?",cid,row.get("consumer_id"));p.db.update("INSERT INTO conversation_participants(conversation_id,principal_id) VALUES (?,?) ON CONFLICT(conversation_id,principal_id) DO UPDATE SET active=true",cid,target);p.db.update("UPDATE conversations SET assigned_principal_id=?,version=version+1,updated_at=clock_timestamp() WHERE id=?",target,cid);
   audit.write(a,"support.assign","CONVERSATION",cid.toString(),Map.of("version",expected),Map.of("principal_id",target,"reason",reason,"version",expected+1),r);outbox.append("CONVERSATION",cid.toString(),"SupportAssigned",1,Map.of("conversation_id",cid.toString()),correlation(r));return Map.of("id",cid.toString());});return view(a,scoped(a,cid,false,false));
 }
 public Map<String,Object> status(Actor a,UUID cid,Map<String,Object>b,String match,String key,HttpServletRequest r){fields(b,"status");String next=text(b.get("status"),12);if(!Set.of("OPEN","CLOSED").contains(next))throw new Failure(400,"VALIDATION_ERROR");if(a.realm()!=Actor.Realm.CONSUMER)staff(a,"support.reply");long expected=version(match);scoped(a,cid,false,true);
  commands.command(a,"support.status:"+cid,key,Map.of("body",b,"version",expected),()->{var row=scoped(a,cid,true,true);sameVersion(row,expected);p.db.update("UPDATE conversations SET status=?,version=version+1,updated_at=clock_timestamp() WHERE id=?",next,cid);audit.write(a,"support.status","CONVERSATION",cid.toString(),Map.of("status",row.get("status")),Map.of("status",next),r);return Map.of("id",cid.toString());});return detail(a,cid);
 }
 public Map<String,Object> send(Actor a,UUID cid,Map<String,Object>b,String key,HttpServletRequest r){if(a.realm()!=Actor.Realm.CONSUMER)staff(a,"support.reply");fields(b,"type","body","asset_ids","target_id");String type=text(b.get("type"),12);var assets=ids(b.get("asset_ids"),4);String body=b.get("body")==null?null:text(b.get("body"),2000);UUID target=b.get("target_id")==null?null:id(b.get("target_id"));
  if(!Set.of("TEXT","IMAGE","PRODUCT","ORDER").contains(type)||type.equals("TEXT")&&(body==null||!assets.isEmpty()||target!=null)||type.equals("IMAGE")&&(body!=null||assets.isEmpty()||target!=null)||Set.of("PRODUCT","ORDER").contains(type)&&(body!=null||!assets.isEmpty()||target==null))throw new Failure(400,"VALIDATION_ERROR");scoped(a,cid,false,true);
  var command=commands.command(a,"support.send:"+cid,key,b,()->{var row=scoped(a,cid,true,true);if(!row.get("status").equals("OPEN"))throw new Failure(409,"CONVERSATION_CLOSED");if(target!=null)card(a,row,type,target,true);UUID mid=UUID.randomUUID();long sequence=number(row.get("last_sequence"))+1;
   p.bindMedia(a,"CHAT",mid,assets);p.db.update("INSERT INTO conversation_messages(id,conversation_id,sequence,sender_id,sender_realm,type,body,asset_ids,target_id) VALUES (?,?,?,?,?,?,?,?::jsonb,?)",mid,cid,sequence,a.principalId(),a.realm().name(),type,body,p.json.writeValueAsString(assets),target);
   p.db.update("UPDATE conversations SET last_sequence=?,version=version+1,updated_at=clock_timestamp() WHERE id=?",sequence,cid);
   outbox.append("CONVERSATION",cid.toString(),"SupportMessageCreated",1,Map.of("conversation_id",cid.toString(),"message_id",mid.toString(),"sequence",sequence),correlation(r));return Map.of("id",mid.toString());});scoped(a,cid,false,true);return message(a,p.one("SELECT * FROM conversation_messages WHERE id=? AND conversation_id=?",id(command.get("id")),cid));
 }
 private Map<String,Object> message(Actor a,Map<String,Object> row){var result=new LinkedHashMap<String,Object>();for(String k:List.of("id","conversation_id","sequence","sender_realm","type","body","target_id","created_at"))result.put(k,row.get(k));result.put("outgoing",a.principalId().equals(row.get("sender_id")));result.put("media",p.media(row.get("asset_ids"),"/api/v1/"+a.realm().name().toLowerCase(Locale.ROOT)+"/conversations/"+row.get("conversation_id")+"/messages/"+row.get("id")+"/media/"));return p.view(result);}
 public List<Map<String,Object>> messages(Actor a,UUID cid,long after,int limit){limit(limit);if(after<0||after>9007199254741L)throw new Failure(400,"VALIDATION_ERROR");scoped(a,cid,false,true);return p.db.queryForList("SELECT * FROM conversation_messages WHERE conversation_id=? AND sequence>? ORDER BY sequence LIMIT ?",cid,after,limit+1).stream().map(row->message(a,row)).toList();}
 public Map<String,Object> read(Actor a,UUID cid,Map<String,Object>b,String key){fields(b,"through_sequence");Object n=b.get("through_sequence");if(!(n instanceof Number v)||v.longValue()<0||v.doubleValue()!=v.longValue())throw new Failure(400,"VALIDATION_ERROR");long through=((Number)n).longValue();scoped(a,cid,false,true);commands.command(a,"support.read:"+cid,key,b,()->{var row=scoped(a,cid,true,true);if(through>number(row.get("last_sequence")))throw new Failure(400,"READ_SEQUENCE_AHEAD");p.db.update("UPDATE conversation_participants SET read_sequence=greatest(read_sequence,?) WHERE conversation_id=? AND principal_id=? AND active",through,cid,a.principalId());return Map.of("id",cid.toString());});return detail(a,cid);}
 public PublishingSupport.Content media(Actor a,UUID cid,UUID mid,UUID asset){scoped(a,cid,false,true);return p.content(p.one("SELECT asset_ids FROM conversation_messages WHERE conversation_id=? AND id=?",cid,mid).get("asset_ids"),asset);}
 public Map<String,Object> card(Actor a,UUID cid,UUID mid){var row=scoped(a,cid,false,true);var m=p.one("SELECT type,target_id FROM conversation_messages WHERE conversation_id=? AND id=?",cid,mid);if(!Set.of("PRODUCT","ORDER").contains(m.get("type")))throw new Failure(404,"RESOURCE_NOT_FOUND");return card(a,row,m.get("type").toString(),(UUID)m.get("target_id"),false);}
 private Map<String,Object> card(Actor a,Map<String,Object> conversation,String type,UUID target,boolean sending){
  var result=new LinkedHashMap<String,Object>();result.put("type",type);result.put("target_id",target);
  if(type.equals("PRODUCT")){var rows=p.db.queryForList("SELECT k.id,s.name FROM skus k JOIN spus s ON s.id=k.spu_id WHERE k.id=? AND k.status='ACTIVE' AND s.status='ACTIVE' AND EXISTS (SELECT 1 FROM sku_standard_versions v WHERE v.sku_id=k.id AND v.status='PUBLISHED') AND EXISTS (SELECT 1 FROM offers o WHERE o.sku_id=k.id AND o.sale_status='ACTIVE' AND (?::uuid IS NULL OR o.store_id=?))",target,conversation.get("store_id"),conversation.get("store_id"));if(rows.isEmpty()){if(sending)throw new Failure(404,"RESOURCE_NOT_FOUND");result.put("available",false);result.put("label",null);result.put("destination",null);}else{result.put("available",true);result.put("label",rows.getFirst().get("name"));result.put("destination","/products/"+target);}return result;}
  var orders=p.db.queryForList("SELECT s.id,s.order_id,s.merchant_id,o.user_id FROM suborders s JOIN orders o ON o.id=s.order_id JOIN identity_principal ip ON ip.user_id=o.user_id AND ip.realm='CONSUMER' WHERE s.id=? AND ip.id=?",target,conversation.get("consumer_id"));
  if(orders.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var order=orders.getFirst();if(conversation.get("kind").equals("MERCHANT")&&(!Objects.equals(conversation.get("merchant_id"),order.get("merchant_id"))||p.db.queryForObject("SELECT count(*) FROM order_items WHERE suborder_id=? AND store_id=?",Integer.class,target,conversation.get("store_id"))==0))throw new Failure(404,"RESOURCE_NOT_FOUND");
  if(a.realm()!=Actor.Realm.CONSUMER){if(!a.permissions().contains(a.realm()==Actor.Realm.ADMIN?"order.admin.read":"order.read"))throw new Failure(403,"PERMISSION_DENIED");if(a.realm()==Actor.Realm.MERCHANT&&p.db.queryForObject("SELECT count(*) FROM order_items i WHERE i.suborder_id=? AND ((i.store_id IS NULL AND NOT ?) OR (i.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM principal_store_scope ps WHERE ps.principal_id=? AND ps.merchant_id=i.merchant_id AND ps.store_id=i.store_id)))",Integer.class,target,a.permissions().contains("order.default-scope"),a.principalId())>0)throw new Failure(404,"RESOURCE_NOT_FOUND");}
  result.put("available",true);result.put("label","订单 "+target.toString().substring(0,8));result.put("destination",a.realm()==Actor.Realm.CONSUMER?"/orders/"+order.get("order_id"):"/orders");return result;
 }
 private static String correlation(HttpServletRequest r){return r==null?null:(String)r.getAttribute("correlation_id");}
}
