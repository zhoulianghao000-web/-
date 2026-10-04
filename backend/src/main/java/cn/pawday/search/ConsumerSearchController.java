package cn.pawday.search;
import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@RestController @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class ConsumerSearchController {
 private final OpenSearchClient search;private final ConsumerCatalogService catalog;
 public ConsumerSearchController(OpenSearchClient search,ConsumerCatalogService catalog){this.search=search;this.catalog=catalog;}
 @GetMapping({"/api/v1/public/products","/api/v1/consumer/products"}) Object list(@RequestParam(required=false) String q,@RequestParam(required=false) String pet_category,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="20") int limit,HttpServletRequest r){
  if(q!=null&&q.length()>160)throw new Api.Failure(400,"VALIDATION_ERROR");
  if(limit<1||limit>100||pet_category!=null&&!Set.of("CAT","DOG","AQUATIC","BIRD","SMALL_PET").contains(pet_category))throw new Api.Failure(400,"VALIDATION_ERROR");
  if(cursor!=null)try{UUID.fromString(cursor);}catch(Exception bad){throw new Api.Failure(400,"INVALID_CURSOR");}
  List<Object> filters=new ArrayList<>();filters.add(Map.of("term",Map.of("deleted",false)));if(pet_category!=null)filters.add(Map.of("term",Map.of("pet_category",pet_category)));
  var query=new LinkedHashMap<String,Object>();query.put("size",limit+1);query.put("query",Map.of("bool",Map.of("filter",filters)));query.put("sort",List.of(Map.of("sku_id","asc")));if(cursor!=null)query.put("search_after",List.of(cursor));
  var response=search.request("POST","/"+IndexVersion.READ_ALIAS+"/_search",query);
  var hits=(List<?>)((Map<?,?>)response.get("hits")).get("hits");boolean more=hits.size()>limit;List<Map<String,Object>> data=new ArrayList<>();String last=null;
  for(Object raw:hits.stream().limit(limit).toList()){var hit=(Map<?,?>)raw;UUID id=UUID.fromString(hit.get("_id").toString());last=id.toString();try{var product=catalog.sku(id);if(pet_category!=null&&!pet_category.equals(product.get("pet_category")))continue;if(q!=null&&!((product.get("name")+" "+product.get("brand")+" "+product.get("sku_code")).toLowerCase(Locale.ROOT).contains(q.trim().toLowerCase(Locale.ROOT))))continue;var offers=catalog.offers(id);if(offers.isEmpty())continue;product.put("offers",offers);data.add(product);}catch(Api.Failure retired){if(retired.status!=404)throw retired;}}
  // Sparse pages are deliberate: stale projection hits never expose frozen/retired facts.
  return new Api.ListEnvelope<>(data,new Api.Page(more?last:null,more),Api.meta(r));
 }
}
