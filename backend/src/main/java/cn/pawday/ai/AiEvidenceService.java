package cn.pawday.ai;
import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.pet.PetService;
import cn.pawday.publishing.PublishingSupport;
import java.util.*;
import java.util.regex.*;
import org.springframework.stereotype.Service;

@Service
public class AiEvidenceService {
 private final PublishingSupport p;private final ConsumerCatalogService catalog;private final PetService pets;
 public AiEvidenceService(PublishingSupport p,ConsumerCatalogService catalog,PetService pets){this.p=p;this.catalog=catalog;this.pets=pets;}
 public record Snapshot(UUID petId,Long petVersion,String neutered,List<Map<String,Object>> cards,List<Map<String,Object>> evidence){}
 @SuppressWarnings("unchecked")
 Snapshot snapshot(Actor a,UUID petId,List<UUID> selected,String text){
    Long budget=null;Matcher m=Pattern.compile("([0-9]{1,6})\\s*元\\s*(以内|以下|内)").matcher(text);if(m.find())budget=Long.parseLong(m.group(1))*100;
  var pet=petId==null?null:pets.get(a,petId);List<UUID> ids=selected;
  if(ids.isEmpty()){
   var candidates=p.db.queryForList("SELECT k.id"+ConsumerCatalogService.PUBLISHED+" AND EXISTS(SELECT 1"+ConsumerCatalogService.ELIGIBLE.replace("o.sku_id=?","o.sku_id=k.id")+" AND i.available_qty>0) ORDER BY k.id LIMIT 60");var picked=new ArrayList<UUID>();
   for(var row:candidates){UUID sku=(UUID)row.get("id");Long ceiling=budget;if(catalog.offers(sku).stream().noneMatch(o->Boolean.TRUE.equals(o.get("in_stock"))&&(ceiling==null||((Number)o.get("sale_price_fen")).longValue()<=ceiling)))continue;if(petId!=null&&catalog.fit(a,sku,petId).get("result").equals("NOT_RECOMMENDED"))continue;picked.add(sku);if(picked.size()==3)break;}ids=picked;
  }
  var cards=new ArrayList<Map<String,Object>>();var evidence=new ArrayList<Map<String,Object>>();
  for(UUID id:ids){var product=catalog.sku(id);var offers=catalog.offers(id);Long ceiling=budget;var available=offers.stream().filter(o->Boolean.TRUE.equals(o.get("in_stock"))&&(ceiling==null||((Number)o.get("sale_price_fen")).longValue()<=ceiling)).toList();
   if(available.isEmpty()){if(!selected.isEmpty())throw new Failure(409,"SKU_NOT_AVAILABLE");continue;}
   var fit=petId==null?null:catalog.fit(a,id,petId);if(fit!=null&&!fit.get("catalog_standard_version_id").equals(product.get("catalog_standard_version_id")))throw new Failure(409,"AI_CONTEXT_VERSION_CONFLICT");
   var offer=available.getFirst();var c=new LinkedHashMap<String,Object>();c.put("sku_id",id);c.put("name",product.get("name"));c.put("catalog_standard_version_id",product.get("catalog_standard_version_id"));c.put("offer_id",offer.get("offer_id"));c.put("offer_version",offer.get("offer_version"));c.put("inventory_version",offer.get("inventory_version"));c.put("price_fen",offer.get("sale_price_fen"));c.put("available_qty",offer.get("available_qty"));
   c.put("ingredients",product.get("ingredients"));c.put("source_refs",product.get("source_refs"));c.put("fit_result",fit==null?"INSUFFICIENT_DATA":fit.get("result"));c.put("hard_conflicts",fit==null?List.of():fit.get("hard_conflicts"));c.put("uncertainties",fit==null?List.of("PERSONALIZATION_NOT_USED"):fit.get("uncertainties"));
   cards.add(c);
   evidence.add(Map.of("id",id+":fit","kind","DETERMINISTIC_FIT","result",c.get("fit_result"),"rule_version",ConsumerCatalogService.FIT_RULE_VERSION));
   evidence.add(Map.of("id",id+":ingredients","kind","PUBLISHED_INGREDIENTS","count",((List<?>)product.get("ingredients")).size()));
   evidence.add(Map.of("id",id+":source","kind","PUBLISHED_SOURCE","count",((List<?>)product.get("source_refs")).size()));
  }
  if(cards.isEmpty())throw new Failure(422,"AI_DATA_INSUFFICIENT");return new Snapshot(petId,pet==null?null:((Number)pet.get("version")).longValue(),pet==null?null:pet.get("neutered_status").toString(),cards,evidence);
 }
 static String proposalValue(String text){if(text.contains("未绝育")||text.contains("没有绝育"))return "NO";if(text.contains("已绝育"))return "YES";return null;}
 String render(Snapshot snapshot,ExplanationProvider.Plan plan){
  var allowed=snapshot.evidence.stream().map(x->x.get("id").toString()).toList();if(plan.evidenceIds()==null||plan.evidenceIds().isEmpty()||plan.evidenceIds().size()>12||new HashSet<>(plan.evidenceIds()).size()!=plan.evidenceIds().size()||!allowed.containsAll(plan.evidenceIds()))throw new Failure(503,"AI_OUTPUT_REJECTED");
  var lines=new ArrayList<String>();lines.add("已根据平台核对过的商品资料整理：");
  // All conclusions and every warning remain visible, even if a model omits their IDs.
  for(var c:snapshot.cards){String label=switch(c.get("fit_result").toString()){case "SUITABLE"->"符合已核对条件";case "NOT_RECOMMENDED"->"不建议作为当前首选";default->"信息不足，不能确定适合";};lines.add(c.get("name")+"："+label+"。");
   if(!((List<?>)c.get("hard_conflicts")).isEmpty())lines.add("存在确定性规则冲突，请先核对过敏或年龄阶段等注意项。");
   if(!((List<?>)c.get("uncertainties")).isEmpty())lines.add("关键资料存在缺失或未核对项，不会用模型知识补齐。");
   if(plan.evidenceIds().contains(c.get("sku_id")+":ingredients"))lines.add("已发布配料项数："+((List<?>)c.get("ingredients")).size()+"；具体配料请查看商品资料。");
   if(plan.evidenceIds().contains(c.get("sku_id")+":source"))lines.add("资料有 "+((List<?>)c.get("source_refs")).size()+" 条来源记录，可在商品详情核对。");
  }
  lines.add("这是商品资料与规则解释，不替代兽医。价格和可售状态以下单前重新核验为准。");return String.join("\n",lines);
 }
}
