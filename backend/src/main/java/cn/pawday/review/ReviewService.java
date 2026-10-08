package cn.pawday.review;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.points.PointsService;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import java.sql.Date;
import java.time.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;

@Service
public class ReviewService {
 private final PublishingSupport p;private final AccessGuard guard;private final IdempotentCommandExecutor commands;
 private final AuthService auth;private final AuditWriter audit;private final OutboxWriter outbox;private final PointsService points;private final Clock clock;
 public ReviewService(PublishingSupport p,AccessGuard guard,IdempotentCommandExecutor commands,AuthService auth,AuditWriter audit,OutboxWriter outbox,PointsService points,Clock clock){this.p=p;this.guard=guard;this.commands=commands;this.auth=auth;this.audit=audit;this.outbox=outbox;this.points=points;this.clock=clock;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 private Map<String,Object> item(UUID id){return p.one("SELECT i.*,s.order_id,o.user_id,k.spu_id FROM order_items i JOIN suborders s ON s.id=i.suborder_id JOIN orders o ON o.id=s.order_id JOIN skus k ON k.id=i.sku_id WHERE i.id=?",id);}
 private Map<String,Object> ownedItem(Actor a,UUID id){consumer(a);var row=item(id);if(!a.userId().equals(row.get("user_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");return row;}
 private void lock(Map<String,Object> row){p.one("SELECT id FROM orders WHERE id=? FOR UPDATE",row.get("order_id"));p.one("SELECT id FROM suborders WHERE id=? FOR UPDATE",row.get("suborder_id"));}
 private boolean eligible(Map<String,Object> row){
  UUID id=(UUID)row.get("id");long effective=number(row.get("quantity"))-number(row.get("cancelled_qty"));
  long received=p.db.queryForObject("SELECT coalesce(sum(i.quantity),0) FROM shipment_items i JOIN shipment_receipts r ON r.shipment_id=i.shipment_id WHERE i.order_item_id=?",Long.class,id);
  long reserved=p.db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE order_item_id=? AND source_type='AFTERSALE' AND status='RESERVED'",Long.class,id);
  long refunded=p.db.queryForObject("SELECT count(*) FROM order_refund_unit_claims WHERE order_item_id=? AND source_type='AFTERSALE' AND status='REFUNDED'",Long.class,id);
  return effective>0&&received==effective&&refunded<received&&reserved==0&&p.db.queryForObject("SELECT count(*) FROM payments WHERE order_id=? AND status='SUCCEEDED'",Integer.class,row.get("order_id"))==1;
 }
 public Map<String,Object> eligibility(Actor a,UUID id){var row=ownedItem(a,id);var existing=p.db.queryForList("SELECT id FROM reviews WHERE order_item_id=?",id);var frozen=p.db.queryForList("SELECT p.* FROM review_reward_grants g JOIN review_reward_policies p ON p.id=g.policy_id WHERE g.order_id=?",row.get("order_id"));boolean eligible=eligible(row);var result=new LinkedHashMap<String,Object>();result.put("order_item_id",id);result.put("spu_id",row.get("spu_id"));result.put("eligible",eligible);result.put("existing_review_id",existing.isEmpty()?null:existing.getFirst().get("id"));result.put("reason",eligible?null:"ITEM_NOT_REVIEWABLE");result.put("reward_policy",frozen.isEmpty()?policy():p.view(frozen.getFirst()));return result;}
 private Map<String,Object> review(UUID id){return p.one("SELECT * FROM reviews WHERE id=?",id);}
 private Map<String,Object> owned(Actor a,UUID id){consumer(a);var row=review(id);if(!a.userId().equals(row.get("user_id")))throw new Failure(404,"RESOURCE_NOT_FOUND");return row;}
 private void validate(Map<String,Object>b){fields(b,"rating","service_rating","body","asset_ids","pet_id","share_pet_label");integer(b.get("rating"),1,5);if(b.get("service_rating")!=null)integer(b.get("service_rating"),1,5);text(b.get("body"),2000);ids(b.get("asset_ids"),6);boolean share=bool(b.get("share_pet_label"));if(b.get("pet_id")!=null)id(b.get("pet_id"));if(share&&b.get("pet_id")==null)throw new Failure(400,"PET_REQUIRED_FOR_LABEL");if(!share&&b.get("pet_id")!=null)throw new Failure(400,"PET_CONSENT_REQUIRED");}
 private Map<String,Object> label(Actor a,UUID id){
  var row=p.one("SELECT t.*,s.name AS species_name,b.name AS breed_name FROM pets t JOIN pet_species s ON s.id=t.species_id LEFT JOIN pet_breeds b ON b.id=t.breed_id WHERE t.id=? AND t.owner_user_id=? AND t.status='ACTIVE' FOR SHARE OF t",id,a.userId());
  String age=null;if(row.get("birth_date") instanceof Date d){int years=Period.between(d.toLocalDate(),clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate()).getYears();age=Math.max(0,years)+"岁";}else if(row.get("age_estimate_months") instanceof Number n)age="约"+(n.intValue()/12)+"岁";
  var result=new LinkedHashMap<String,Object>();result.put("species_name",row.get("species_name"));result.put("breed_name",row.get("breed_name"));result.put("age_label",age);return result;
 }
 private UUID revision(Actor a,UUID review,Map<String,Object>b){
  UUID id=UUID.randomUUID(),pet=b.get("pet_id")==null?null:id(b.get("pet_id"));var label=pet==null?null:label(a,pet);var assets=ids(b.get("asset_ids"),6);
  int v=p.db.queryForObject("SELECT coalesce(max(revision_no),0)+1 FROM review_revisions WHERE review_id=?",Integer.class,review);
  p.db.update("INSERT INTO review_revisions(id,review_id,revision_no,rating,service_rating,body,asset_ids,pet_id,pet_label) VALUES (?,?,?,?,?,?,?::jsonb,?,?::jsonb)",id,review,v,integer(b.get("rating"),1,5),b.get("service_rating"),b.get("body"),p.json.writeValueAsString(assets),pet,label==null?null:p.json.writeValueAsString(label));
  p.bindMedia(a,"REVIEW",id,assets);return id;
 }
 private void event(Actor a,String event,UUID id,HttpServletRequest r){audit.write(a,"review."+event,"REVIEW",id.toString(),Map.of(),Map.of("version",review(id).get("version")),r);outbox.append("REVIEW",id.toString(),event,1,Map.of("review_id",id.toString(),"version",review(id).get("version")),r==null?null:(String)r.getAttribute("correlation_id"));}
 public Map<String,Object> create(Actor a,UUID itemId,Map<String,Object>b,String key,HttpServletRequest r){validate(b);ownedItem(a,itemId);var result=commands.command(a,"review.create:"+itemId,key,b,()->{
  var row=ownedItem(a,itemId);lock(row);row=ownedItem(a,itemId);if(!eligible(row))throw new Failure(409,"ITEM_NOT_REVIEWABLE");if(!p.db.queryForList("SELECT id FROM reviews WHERE order_item_id=?",itemId).isEmpty())throw new Failure(409,"REVIEW_ALREADY_EXISTS");
  UUID id=UUID.randomUUID();p.db.update("INSERT INTO reviews(id,user_id,order_id,suborder_id,order_item_id,sku_id,spu_id,merchant_id,store_id,share_pet_label) VALUES (?,?,?,?,?,?,?,?,?,?)",id,a.userId(),row.get("order_id"),row.get("suborder_id"),itemId,row.get("sku_id"),row.get("spu_id"),row.get("merchant_id"),row.get("store_id"),b.get("share_pet_label"));
  UUID revision=revision(a,id,b);p.db.update("UPDATE reviews SET current_revision_id=? WHERE id=?",revision,id);event(a,"ReviewSubmitted",id,r);return Map.of("id",id.toString());
 });return privateView(a,UUID.fromString(result.get("id").toString()));}
 public Map<String,Object> update(Actor a,UUID id,Map<String,Object>b,String match,String key,HttpServletRequest r){validate(b);long expected=version(match);owned(a,id);var result=commands.command(a,"review.update:"+id,key,Map.of("body",b,"version",expected),()->{
  var seed=owned(a,id);var item=ownedItem(a,(UUID)seed.get("order_item_id"));lock(item);var row=p.one("SELECT * FROM reviews WHERE id=? FOR UPDATE",id);sameVersion(row,expected);
  UUID revision=revision(a,id,b);p.db.update("UPDATE reviews SET current_revision_id=?,draft_status='PENDING',share_pet_label=?,version=version+1,updated_at=now() WHERE id=?",revision,b.get("share_pet_label"),id);event(a,"ReviewUpdated",id,r);return Map.of("id",id.toString());
 });return privateView(a,UUID.fromString(result.get("id").toString()));}
 private Map<String,Object> snapshot(Map<String,Object> row,UUID revision,String mediaPath,boolean privateData){
  var rev=p.one("SELECT * FROM review_revisions WHERE id=? AND review_id=?",revision,row.get("id"));var result=new LinkedHashMap<String,Object>();for(String k:List.of("rating","service_rating","body"))result.put(k,rev.get(k));result.put("id",row.get("id"));result.put("revision_id",revision);result.put("spu_id",row.get("spu_id"));result.put("sku_id",row.get("sku_id"));result.put("verified_purchase",true);result.put("version",row.get("version"));result.put("created_at",p.view(rev).get("created_at"));result.put("media",p.media(rev.get("asset_ids"),mediaPath));
  boolean consent=Boolean.TRUE.equals(row.get("share_pet_label"))&&revision.equals(row.get("current_revision_id"));boolean active=rev.get("pet_id")!=null&&p.db.queryForObject("SELECT count(*) FROM pets WHERE id=? AND owner_user_id=? AND status='ACTIVE'",Integer.class,rev.get("pet_id"),row.get("user_id"))==1;
  result.put("pet_label",consent&&active&&rev.get("pet_label")!=null?p.json.readValue(rev.get("pet_label").toString(),Map.class):null);
  if(privateData){for(String k:List.of("order_id","suborder_id","order_item_id","user_id","merchant_id","store_id","visibility","draft_status","share_pet_label","published_revision_id"))result.put(k,row.get(k));result.put("pet_id",rev.get("pet_id"));result.put("revision_no",rev.get("revision_no"));result.put("moderation",p.db.queryForList("SELECT decision,reason,created_at FROM review_moderation WHERE review_id=? ORDER BY created_at,id",row.get("id")).stream().map(p::view).toList());}
  return result;
 }
 public Map<String,Object> privateView(Actor a,UUID id){var row=a.realm()==Actor.Realm.CONSUMER?owned(a,id):admin(a,id);return snapshot(row,(UUID)row.get("current_revision_id"),"/api/v1/"+(a.realm()==Actor.Realm.CONSUMER?"consumer":"admin")+"/reviews/"+id+"/media/",true);}
 private Map<String,Object> admin(Actor a,UUID id){permission(a,Actor.Realm.ADMIN,"review.read");return review(id);}
 public Map<String,Object> publicView(UUID id){var row=p.one("SELECT * FROM reviews WHERE id=? AND visibility='PUBLIC' AND published_revision_id IS NOT NULL",id);return snapshot(row,(UUID)row.get("published_revision_id"),"/api/v1/public/reviews/"+id+"/media/",false);}
 public List<Map<String,Object>> publicList(UUID spu,UUID after,int limit){limit(limit);return p.db.queryForList("SELECT id FROM reviews WHERE spu_id=? AND visibility='PUBLIC' AND published_revision_id IS NOT NULL AND id>? ORDER BY id LIMIT ?",spu,after,limit+1).stream().map(row->publicView((UUID)row.get("id"))).toList();}
 public List<Map<String,Object>> list(Actor a,UUID after,int limit,UUID store){limit(limit);String where;var args=new ArrayList<Object>();
  if(a.realm()==Actor.Realm.CONSUMER){where="user_id=?";args.add(a.userId());}
  else if(a.realm()==Actor.Realm.ADMIN){permission(a,Actor.Realm.ADMIN,"review.read");where="true";}
  else{permission(a,Actor.Realm.MERCHANT,"review.merchant.read");if(store==null)throw new Failure(400,"STORE_REQUIRED");guard.store(a,store);where="merchant_id=? AND store_id=? AND visibility='PUBLIC' AND published_revision_id IS NOT NULL";args.add(a.merchantId());args.add(store);}
  args.add(after);args.add(limit+1);return p.db.queryForList("SELECT id FROM reviews WHERE "+where+" AND id>? ORDER BY id LIMIT ?",args.toArray()).stream().map(row->a.realm()==Actor.Realm.MERCHANT?publicView((UUID)row.get("id")):privateView(a,(UUID)row.get("id"))).toList();
 }
 public Map<String,Object> moderate(Actor a,UUID id,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){permission(a,Actor.Realm.ADMIN,"review.moderate");admin(a,id);fields(b,"decision","reason");String decision=text(b.get("decision"),12),reason=text(b.get("reason"),1000);if(!Set.of("APPROVE","REJECT","HIDE").contains(decision))throw new Failure(400,"VALIDATION_ERROR");long expected=version(match);
  var result=commands.command(a,"review.moderate:"+id,key,Map.of("body",b,"version",expected),()->{var seed=review(id);lock(item((UUID)seed.get("order_item_id")));var row=p.one("SELECT * FROM reviews WHERE id=? FOR UPDATE",id);sameVersion(row,expected);auth.consumeProof(a,"review.moderate",proof);
   if(decision.equals("HIDE")){if(!row.get("visibility").equals("PUBLIC"))throw new Failure(409,"REVIEW_NOT_PUBLIC");p.db.update("UPDATE reviews SET visibility='HIDDEN',version=version+1,updated_at=now() WHERE id=?",id);}
   else{if(!row.get("draft_status").equals("PENDING"))throw new Failure(409,"REVIEW_ALREADY_MODERATED");if(decision.equals("APPROVE")){p.db.update("UPDATE reviews SET published_revision_id=current_revision_id,visibility='PUBLIC',draft_status='APPROVED',version=version+1,updated_at=now() WHERE id=?",id);if(eligible(item((UUID)row.get("order_item_id"))))points.recordReviewApproved(id,(UUID)row.get("current_revision_id"));}
    else p.db.update("UPDATE reviews SET draft_status='REJECTED',version=version+1,updated_at=now() WHERE id=?",id);}
   p.db.update("INSERT INTO review_moderation(id,review_id,revision_id,decision,reason,actor_id) VALUES (?,?,?,?,?,?)",UUID.randomUUID(),id,decision.equals("HIDE")?row.get("published_revision_id"):row.get("current_revision_id"),decision,reason,a.principalId());event(a,"ReviewModerated",id,r);return Map.of("id",id.toString());
  });return privateView(a,UUID.fromString(result.get("id").toString()));
 }
 public PublishingSupport.Content content(Actor a,UUID review,UUID asset){Map<String,Object> row;if(a==null)row=p.one("SELECT * FROM reviews WHERE id=? AND visibility='PUBLIC' AND published_revision_id IS NOT NULL",review);else row=a.realm()==Actor.Realm.CONSUMER?owned(a,review):admin(a,review);UUID revision=(UUID)row.get(a==null?"published_revision_id":"current_revision_id");return p.content(p.one("SELECT asset_ids FROM review_revisions WHERE id=?",revision).get("asset_ids"),asset);}
 public Map<String,Object> policy(){return p.view(p.one("SELECT * FROM review_reward_policies ORDER BY policy_version DESC LIMIT 1"));}
 public List<Map<String,Object>> policies(Actor a){permission(a,Actor.Realm.ADMIN,"review.read");return p.db.queryForList("SELECT * FROM review_reward_policies ORDER BY policy_version DESC").stream().map(p::view).toList();}
 public Map<String,Object> createPolicy(Actor a,Map<String,Object>b,String key,String proof,HttpServletRequest r){permission(a,Actor.Realm.ADMIN,"review.policy.manage");fields(b,"base_points","media_bonus_points","refund_strategy");int base=integer(b.get("base_points"),0,10000),media=integer(b.get("media_bonus_points"),0,10000);String strategy=text(b.get("refund_strategy"),24);if(!Set.of("PROPORTIONAL_GOODS","NONE").contains(strategy))throw new Failure(400,"VALIDATION_ERROR");return commands.command(a,"review.policy.create",key,b,()->{
  auth.consumeProof(a,"review.policy.manage",proof);p.db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended('review.policy',0))");int v=p.db.queryForObject("SELECT coalesce(max(policy_version),0)+1 FROM review_reward_policies",Integer.class);UUID id=UUID.randomUUID();p.db.update("INSERT INTO review_reward_policies(id,policy_version,base_points,media_bonus_points,refund_strategy,created_by) VALUES (?,?,?,?,?,?)",id,v,base,media,strategy,a.principalId());audit.write(a,"review.policy.publish","REVIEW_POLICY",id.toString(),Map.of(),Map.of("policy_version",v,"base_points",base,"media_bonus_points",media,"refund_strategy",strategy),r);outbox.append("REVIEW_POLICY",id.toString(),"ReviewPolicyPublished",1,Map.of("policy_id",id.toString(),"policy_version",v),null);return p.view(p.one("SELECT * FROM review_reward_policies WHERE id=?",id));});}
}
