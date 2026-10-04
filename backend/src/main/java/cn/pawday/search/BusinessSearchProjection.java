package cn.pawday.search;
import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api.Failure;
import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class BusinessSearchProjection {
 private final JdbcTemplate db;private final CatalogSearchSource source;private final ConsumerCatalogService catalog;private final TransactionTemplate tx;
 private final JsonMapper json=JsonMapper.builder().build();
 public BusinessSearchProjection(JdbcTemplate db,CatalogSearchSource source,ConsumerCatalogService catalog,TransactionTemplate tx){this.db=db;this.source=source;this.catalog=catalog;this.tx=tx;}
 public void refresh(UUID sku,String eventType,String correlation){tx.executeWithoutResult(s->{
  // Serialize derivation before reading facts, rather than merely locking at write time.
  db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","catalog-search-source:"+sku);
  Map<String,Object> product;
  try{product=catalog.sku(sku);}catch(Failure unavailable){
   if(unavailable.status!=404)throw unavailable;
   var old=db.queryForList("SELECT document FROM catalog_search_source WHERE sku_id=?",sku);
   if(old.isEmpty())return;
   var d=json.readValue(old.getFirst().get("document").toString(),Map.class);
   if(Boolean.TRUE.equals(d.get("deleted")))return;
   source.change(new CatalogSearchSource.Product(UUID.fromString(d.get("spu_id").toString()),sku,d.get("brand").toString(),d.get("pet_category").toString(),d.get("life_stage").toString(),d.get("food_type").toString(),(List<String>)d.get("allergens"),((Number)d.get("price_min_fen")).longValue(),false,0,Instant.parse(d.get("published_at").toString())),true,eventType,correlation);return;
  }
  var offers=catalog.offers(sku);long price=offers.stream().mapToLong(o->((Number)o.get("sale_price_fen")).longValue()).min().orElse(0);
  int merchants=(int)offers.stream().map(o->o.get("merchant_id")).distinct().count();boolean stock=offers.stream().anyMatch(o->Boolean.TRUE.equals(o.get("in_stock")));
  List<String> allergens=((List<?>)product.get("allergens")).stream().map(a->((Map<?,?>)a).get("id").toString()).toList();
  // A v1 keyword may contain multiple immutable stage references; fit reads the full source standard.
  String stage=((List<?>)product.get("life_stage_ids")).size()==1?((List<?>)product.get("life_stage_ids")).getFirst().toString():"MULTIPLE_OR_UNKNOWN";
  var derived=new CatalogSearchSource.Product((UUID)product.get("spu_id"),sku,product.get("brand").toString(),product.get("pet_category").toString(),stage,product.get("category").toString(),allergens,price,stock,merchants,((java.sql.Timestamp)product.get("published_at")).toInstant());
  var old=db.queryForList("SELECT document FROM catalog_search_source WHERE sku_id=?",sku);
  if(!old.isEmpty()){var previous=new LinkedHashMap<>(json.readValue(old.getFirst().get("document").toString(),Map.class));previous.remove("revision");var next=new LinkedHashMap<>(derived.document(1,offers.isEmpty()));next.remove("revision");if(json.readTree(json.writeValueAsString(previous)).equals(json.readTree(json.writeValueAsString(next))))return;}
  source.change(derived,offers.isEmpty(),eventType,correlation);
 });}
}
