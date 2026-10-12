package cn.pawday.search;
import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Crypto;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import tools.jackson.databind.json.JsonMapper;
@Service @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class ProductSearchService {
 private final OpenSearchClient search;private final ConsumerCatalogService catalog;private final JdbcTemplate db;private final Crypto crypto;private final Clock clock;private final int cap;
 private final JsonMapper json=JsonMapper.builder().build();
 public ProductSearchService(OpenSearchClient search,ConsumerCatalogService catalog,JdbcTemplate db,Crypto crypto,Clock clock,@Value("${pawday.search.candidate-limit:10000}")int cap){this.search=search;this.catalog=catalog;this.db=db;this.crypto=crypto;this.clock=clock;if(cap<100||cap>50000)throw new IllegalArgumentException("search candidate limit");this.cap=cap;}
 /** The frozen v1 projection discovers identities; all filters, aggregates and order precede pagination in PostgreSQL. */
 private List<UUID> candidates(){
  var ids=new ArrayList<UUID>();String after=null;
  while(true){var q=new LinkedHashMap<String,Object>();q.put("size",500);q.put("_source",false);q.put("query",Map.of("match_all",Map.of()));q.put("sort",List.of(Map.of("sku_id","asc")));if(after!=null)q.put("search_after",List.of(after));
   var result=search.request("POST","/"+IndexVersion.READ_ALIAS+"/_search",q);var hits=(List<?>)((Map<?,?>)result.get("hits")).get("hits");
   for(Object h:hits){String id=((Map<?,?>)h).get("_id").toString();UUID parsed=UUID.fromString(id);if(after!=null&&id.compareTo(after)<=0)throw new OpenSearchClient.Unavailable("SEARCH_CANDIDATE_ORDER_INVALID");ids.add(parsed);after=id;if(ids.size()>cap)throw new Failure(503,"SEARCH_CANDIDATE_LIMIT");}
   if(hits.size()<500)return ids;
  }
 }
 @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
 public Api.ListEnvelope<Map<String,Object>> list(ProductSearchFilter f,String cursor,int limit,Api.Meta meta){
  if(limit<1||limit>100)throw new Failure(400,"VALIDATION_ERROR");Map<String,Object> prior=null;
  String filterHash=crypto.hash(json.writeValueAsString(f.canonical()));
  if(cursor!=null)try{if(cursor.length()>2048)throw new Exception();prior=json.readValue(new String(crypto.decrypt(cursor),StandardCharsets.UTF_8),Map.class);if(!"PRODUCT_SEARCH_1".equals(prior.get("kind"))||!filterHash.equals(prior.get("filter"))||((Number)prior.get("expires")).longValue()<clock.instant().getEpochSecond())throw new Exception();}catch(Exception invalid){throw new Failure(400,"INVALID_CURSOR");}
  var ids=candidates();List<Map<String,Object>> rows=ids.isEmpty()?List.of():rank(f,ids);
  String digest=crypto.hash(json.writeValueAsString(rows));int offset=0;long expires=clock.instant().getEpochSecond()+300;
  if(prior!=null){if(!digest.equals(prior.get("digest")))throw new Failure(409,"SEARCH_RESULTS_CHANGED");offset=((Number)prior.get("offset")).intValue();expires=((Number)prior.get("expires")).longValue();if(offset<0||offset>=rows.size())throw new Failure(400,"INVALID_CURSOR");}
  List<Map<String,Object>> data=new ArrayList<>();int end=Math.min(rows.size(),offset+limit);
  for(var row:rows.subList(offset,end)){UUID id=(UUID)row.get("id");var product=catalog.sku(id);var offers=catalog.offers(id);if(Boolean.TRUE.equals(f.inStock()))offers=offers.stream().filter(x->Boolean.TRUE.equals(x.get("in_stock"))).toList();product.put("offers",offers);data.add(product);}
  String next=end<rows.size()?crypto.encrypt(json.writeValueAsBytes(Map.of("kind","PRODUCT_SEARCH_1","filter",filterHash,"digest",digest,"offset",end,"expires",expires))):null;
  return new Api.ListEnvelope<>(data,new Api.Page(next,next!=null),meta);
 }
 private List<Map<String,Object>> rank(ProductSearchFilter f,List<UUID> ids){
  String offerWhere=Boolean.TRUE.equals(f.inStock())?" AND i.available_qty>0":"";
  String sql="SELECT k.id,v.id AS standard_id,k.weight_g,k.package_unit,k.sku_code,p.name,p.pet_category,p.category,b.name AS brand,pricing.price,pricing.stock,coalesce(sales.qty,0) AS sales,coalesce(ratings.rating,0) AS rating,coalesce(ratings.service,0) AS service,coalesce(ratings.n,0) AS review_count,v.allergens_known,v.life_stage_ids::text "+
   "FROM skus k JOIN spus p ON p.id=k.spu_id JOIN brands b ON b.id=p.brand_id JOIN sku_standard_versions v ON v.sku_id=k.id AND v.status='PUBLISHED' "+
   "JOIN LATERAL (SELECT min(o.sale_price_fen) AS price,bool_or(i.available_qty>0) AS stock FROM offers o JOIN merchant m ON m.id=o.merchant_id JOIN inventory_balances i ON i.offer_id=o.id WHERE o.sku_id=k.id AND o.sale_status='ACTIVE' AND m.status='ACTIVE'"+offerWhere+") pricing ON pricing.price IS NOT NULL "+
   "LEFT JOIN LATERAL (SELECT sum(it.quantity-(SELECT count(*) FROM order_refund_unit_claims c WHERE c.order_item_id=it.id AND c.status='REFUNDED')) AS qty FROM order_items it JOIN suborders sub ON sub.id=it.suborder_id JOIN payments pay ON pay.order_id=sub.order_id AND pay.status='SUCCEEDED' WHERE it.sku_id=k.id) sales ON true "+
   "LEFT JOIN LATERAL (SELECT avg(rr.rating) AS rating,avg(rr.service_rating) AS service,count(*) AS n FROM reviews rv JOIN review_revisions rr ON rr.id=rv.published_revision_id WHERE rv.sku_id=k.id AND rv.visibility='PUBLIC') ratings ON true "+
   "WHERE k.id=ANY(?::uuid[]) AND k.status='ACTIVE' AND p.status='ACTIVE' AND b.status='ACTIVE'";
  List<Object> args=new ArrayList<>();args.add("{"+String.join(",",ids.stream().map(UUID::toString).toList())+"}");
  String keyword=f.q()==null?"":f.q().toLowerCase(Locale.ROOT);
  if(!keyword.isEmpty()){sql+=" AND (strpos(lower(p.name),?)>0 OR strpos(lower(b.name),?)>0 OR strpos(lower(k.sku_code),?)>0)";args.addAll(List.of(keyword,keyword,keyword));}
  if(f.petCategory()!=null){sql+=" AND p.pet_category=?";args.add(f.petCategory());}if(f.brandId()!=null){sql+=" AND p.brand_id=?";args.add(f.brandId());}
  if(f.minPrice()!=null){sql+=" AND pricing.price>=?";args.add(f.minPrice());}if(f.maxPrice()!=null){sql+=" AND pricing.price<=?";args.add(f.maxPrice());}
  if(f.lifeStage()!=null){sql+=" AND v.life_stage_ids @> ?::jsonb AND EXISTS (SELECT 1 FROM pet_life_stage_definitions d JOIN pet_life_stage_rule_versions lv ON lv.id=d.rule_version_id WHERE d.id=? AND lv.status='PUBLISHED' AND NOT d.is_unknown)";args.add("[\""+f.lifeStage()+"\"]");args.add(f.lifeStage());}
  if(f.foodType()!=null){sql+=" AND p.category=?";args.add(f.foodType());}if(f.minWeight()!=null){sql+=" AND k.weight_g>=?";args.add(f.minWeight());}if(f.maxWeight()!=null){sql+=" AND k.weight_g<=?";args.add(f.maxWeight());}if(f.unit()!=null){sql+=" AND k.package_unit=?";args.add(f.unit());}
  if(Boolean.FALSE.equals(f.inStock()))sql+=" AND NOT pricing.stock";
  if(!f.excluded().isEmpty()){sql+=" AND v.allergens_known AND NOT EXISTS (SELECT 1 FROM sku_allergens a WHERE a.standard_version_id=v.id AND a.allergen_id=ANY(?::uuid[]))";args.add("{"+String.join(",",f.excluded().stream().map(UUID::toString).toList())+"}");}
  var result=db.queryForList(sql,args.toArray());
  Comparator<Map<String,Object>> price=Comparator.comparingLong(x->((Number)x.get("price")).longValue()),sales=Comparator.comparingLong(x->((Number)x.get("sales")).longValue()),rating=Comparator.comparingDouble(x->((Number)x.get("rating")).doubleValue());
  Comparator<Map<String,Object>> ordering=switch(f.sort()){case "PRICE_ASC"->price;case "PRICE_DESC"->price.reversed();case "SALES_DESC"->sales.reversed();case "RATING_DESC"->rating.reversed();default->Comparator.<Map<String,Object>>comparingInt(x->keyword.isEmpty()?0:x.get("name").toString().equalsIgnoreCase(keyword)?3:x.get("name").toString().toLowerCase(Locale.ROOT).contains(keyword)?2:1).reversed().thenComparing(rating.reversed()).thenComparing(Comparator.<Map<String,Object>>comparingDouble(x->((Number)x.get("service")).doubleValue()).reversed()).thenComparing(sales.reversed()).thenComparing(price);};
  result.sort(ordering.thenComparing(x->x.get("id").toString()));return result;
 }
 public Map<String,Object> facets(){
  String published=ConsumerCatalogService.PUBLISHED+" AND EXISTS(SELECT 1 FROM offers o JOIN merchant m ON m.id=o.merchant_id WHERE o.sku_id=k.id AND o.sale_status='ACTIVE' AND m.status='ACTIVE')";
  return Map.of("brands",db.queryForList("SELECT DISTINCT b.id::text AS value,b.name AS label"+published+" ORDER BY label,value"),"food_types",db.queryForList("SELECT DISTINCT p.category AS value,CASE p.category WHEN 'DRY_FOOD' THEN '干粮' WHEN 'WET_FOOD' THEN '湿粮' WHEN 'SNACK' THEN '零食' ELSE p.category END AS label"+published+" ORDER BY value"),"package_units",db.queryForList("SELECT DISTINCT k.package_unit AS value,CASE k.package_unit WHEN 'BAG' THEN '袋' WHEN 'CAN' THEN '罐' WHEN 'BOX' THEN '盒' ELSE k.package_unit END AS label"+published+" ORDER BY value"),"life_stages",db.queryForList("SELECT d.id::text AS value,sp.name||' · '||d.display_name AS label FROM pet_life_stage_definitions d JOIN pet_life_stage_rule_versions v ON v.id=d.rule_version_id JOIN pet_species sp ON sp.id=v.species_id WHERE sp.status='ACTIVE' AND v.status='PUBLISHED' AND NOT d.is_unknown ORDER BY label,value"),"allergens",db.queryForList("SELECT id::text AS value,name AS label FROM allergens WHERE status='ACTIVE' ORDER BY label,value"));
 }
}
