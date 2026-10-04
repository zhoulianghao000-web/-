package cn.pawday.catalog;

import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.pet.PetService;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** Reads authoritative published standards and currently eligible offers only. */
@Service
public class ConsumerCatalogService {
 public static final String FIT_RULE_VERSION="pawday-fit-1";
 private final JdbcTemplate db; private final PetService pets; private final TransactionTemplate tx;
 private final JsonMapper json=JsonMapper.builder().build();
 public ConsumerCatalogService(JdbcTemplate db,PetService pets,TransactionTemplate tx){this.db=db;this.pets=pets;this.tx=tx;}
 public static final String PUBLISHED=" FROM skus k JOIN spus p ON p.id=k.spu_id JOIN brands b ON b.id=p.brand_id JOIN sku_standard_versions v ON v.sku_id=k.id AND v.status='PUBLISHED' WHERE k.status='ACTIVE' AND p.status='ACTIVE' AND b.status='ACTIVE' ";
 public static final String ELIGIBLE=" FROM offers o JOIN merchant m ON m.id=o.merchant_id JOIN inventory_balances i ON i.offer_id=o.id WHERE o.sku_id=? AND o.sale_status='ACTIVE' AND m.status='ACTIVE' ";
 public Map<String,Object> sku(UUID id){
  var rows=db.queryForList("SELECT k.id,k.spu_id,k.sku_code,k.weight_g,k.package_unit,p.name,p.pet_category,p.category,b.name AS brand,v.id AS catalog_standard_version_id,v.ingredients,v.nutrients,v.allergens_known,v.life_stage_ids,v.source_refs,v.source_updated_on::text,v.published_at"+PUBLISHED+" AND k.id=?",id);
  if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var out=new LinkedHashMap<>(rows.getFirst());
  for(String field:List.of("ingredients","nutrients","life_stage_ids","source_refs"))out.put(field,json.readValue(out.get(field).toString(),List.class));
  out.put("allergens",db.queryForList("SELECT a.id,a.name FROM sku_allergens x JOIN allergens a ON a.id=x.allergen_id WHERE x.standard_version_id=? ORDER BY a.id",out.get("catalog_standard_version_id")));
  return out;
 }
 public List<Map<String,Object>> offers(UUID id){sku(id);return db.queryForList("SELECT o.id AS offer_id,o.merchant_id,m.name AS merchant_name,o.store_id,o.sale_price_fen,o.member_price_fen,o.fulfillment_sla,o.version AS offer_version,i.available_qty,i.version AS inventory_version,(i.available_qty>0) AS in_stock"+ELIGIBLE+" ORDER BY o.sale_price_fen,o.id",id);}
 public Map<String,Object> product(UUID spu){var ids=db.queryForList("SELECT k.id"+PUBLISHED+" AND p.id=? ORDER BY k.id",spu);if(ids.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");return Map.of("spu_id",spu,"skus",ids.stream().map(r->sku((UUID)r.get("id"))).toList());}
 public Map<String,Object> fit(Actor actor,UUID skuId,UUID petId){return tx.execute(s->{
  // Ownership is checked before reading product data; no client supplied pet attributes.
  var pet=pets.get(actor,petId);var product=sku(skuId);var species=db.queryForMap("SELECT category FROM pet_species WHERE id=?",pet.get("species_id"));
  List<Map<String,Object>> conflicts=new ArrayList<>();List<String> uncertainties=new ArrayList<>();
  if(!species.get("category").equals(product.get("pet_category")))conflicts.add(Map.of("type","PET_CATEGORY_MISMATCH","message","商品宠物分类与档案不符"));
  var pa=(List<?>)pet.get("allergens");var sa=(List<?>)product.get("allergens");
  for(Object raw:pa){var allergy=(Map<?,?>)raw;if("YES".equals(allergy.get("status")) && sa.stream().anyMatch(x->String.valueOf(((Map<?,?>)x).get("id")).equals(String.valueOf(allergy.get("allergen_id")))))conflicts.add(Map.of("type","ALLERGEN_CONFLICT","allergen_id",allergy.get("allergen_id"),"message","商品过敏原与宠物档案冲突"));}
  if(!Boolean.TRUE.equals(product.get("allergens_known")))uncertainties.add("PRODUCT_ALLERGENS_UNKNOWN");
  // An empty allergy list is unassessed, not a declaration of no allergies.
  if(pa.isEmpty() || pa.stream().anyMatch(x->"UNKNOWN".equals(((Map<?,?>)x).get("status"))))uncertainties.add("PET_ALLERGIES_UNKNOWN");
  // Every explicitly declared product allergen must have an assessed pet status.
  if(sa.stream().anyMatch(x->pa.stream().noneMatch(y->String.valueOf(((Map<?,?>)y).get("allergen_id")).equals(String.valueOf(((Map<?,?>)x).get("id"))))))uncertainties.add("PET_ALLERGEN_ASSESSMENT_INCOMPLETE");
  var stages=(List<?>)product.get("life_stage_ids");Object stage=pet.get("life_stage_id");
  if(Boolean.TRUE.equals(pet.get("life_stage_unknown")) || stages.isEmpty())uncertainties.add("LIFE_STAGE_INSUFFICIENT");
  else if(stages.stream().noneMatch(x->String.valueOf(x).equals(String.valueOf(stage)))){
   // Stage IDs belong to immutable rule versions. A newer rule cannot silently remap them.
   long current=db.queryForObject("SELECT count(*) FROM pet_life_stage_definitions d JOIN pet_life_stage_rule_versions r ON r.id=d.rule_version_id WHERE d.id=ANY(?::uuid[]) AND r.species_id=? AND r.status='PUBLISHED' AND NOT d.is_unknown",Long.class,"{"+String.join(",",stages.stream().map(String::valueOf).toList())+"}",pet.get("species_id"));
   if(current==0)uncertainties.add("PRODUCT_LIFE_STAGE_EVIDENCE_STALE_OR_OTHER_SPECIES");else conflicts.add(Map.of("type","LIFE_STAGE_MISMATCH","message","商品适用年龄阶段与当前宠物不符"));
  }
  if(!((List<?>)pet.get("avoidance_notes")).isEmpty())uncertainties.add("AVOIDANCE_NOTES_REQUIRE_REVIEW");
  String result=!conflicts.isEmpty()?"NOT_RECOMMENDED":!uncertainties.isEmpty()?"INSUFFICIENT_DATA":"SUITABLE";
  var out=new LinkedHashMap<String,Object>();out.put("sku_id",skuId);out.put("pet_id",petId);out.put("pet_version",pet.get("version"));out.put("result",result);out.put("display_label",result.equals("NOT_RECOMMENDED")?"不建议选择":result.equals("SUITABLE")?"符合已核对条件":"信息不足");out.put("hard_conflicts",conflicts);out.put("uncertainties",uncertainties);out.put("catalog_standard_version_id",product.get("catalog_standard_version_id"));out.put("fit_rule_version",FIT_RULE_VERSION);out.put("life_stage_id",stage);return out;
 });}
 public Map<String,Object> compare(Actor actor,Map<String,Object> body){if(!Set.of("sku_ids","pet_id").containsAll(body.keySet()) || !(body.get("sku_ids") instanceof List<?> ids) || ids.size()<2 || ids.size()>4 || new HashSet<>(ids).size()!=ids.size())throw new Failure(400,"VALIDATION_ERROR");UUID pet=body.get("pet_id")==null?null:PetService.uuid(body.get("pet_id"));return Map.of("items",ids.stream().map(raw->{UUID id=PetService.uuid(raw);var item=new LinkedHashMap<String,Object>();item.put("standard",sku(id));item.put("offers",offers(id));var conclusion=pet==null?null:fit(actor,id,pet);if(conclusion!=null&&!conclusion.get("catalog_standard_version_id").equals(((Map<?,?>)item.get("standard")).get("catalog_standard_version_id")))throw new Failure(409,"STANDARD_CHANGED_REFRESH_REQUIRED");item.put("fit",conclusion);return item;}).toList());}
}
