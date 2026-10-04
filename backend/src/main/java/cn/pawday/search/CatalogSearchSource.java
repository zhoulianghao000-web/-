package cn.pawday.search;
import cn.pawday.outbox.OutboxWriter;
import java.time.Instant;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Service;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import tools.jackson.databind.json.JsonMapper;

/** Foundation integration seam for M3; deliberately has no public catalog CRUD API. */
@Service @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class CatalogSearchSource {
    public static final Set<String> CHANGE_EVENTS=Set.of("CatalogPublished","OfferChanged","InventoryAvailabilityChanged");
    public record Product(UUID spu_id,UUID sku_id,String brand,String pet_category,String life_stage,String food_type,
        List<String> allergens,long price_min_fen,boolean in_stock,int merchant_count,Instant published_at) {
        public Product {
            if(spu_id==null || sku_id==null || published_at==null || price_min_fen<0 || merchant_count<0 || allergens==null || allergens.size()>50)throw new IllegalArgumentException("Invalid source document");
            for(String value:List.of(brand,pet_category,life_stage,food_type))if(value.isBlank() || value.length()>120)throw new IllegalArgumentException("Invalid source keyword");
            for(String allergen:allergens)if(allergen==null || allergen.isBlank() || allergen.length()>120)throw new IllegalArgumentException("Invalid allergen");
            allergens=List.copyOf(allergens);
        }
        public Map<String,Object> document(long revision,boolean deleted) {
            var data=new LinkedHashMap<String,Object>();data.put("spu_id",spu_id.toString());data.put("sku_id",sku_id.toString());
            data.put("brand",brand);data.put("pet_category",pet_category);data.put("life_stage",life_stage);data.put("food_type",food_type);data.put("allergens",allergens);
            data.put("price_min_fen",price_min_fen);data.put("in_stock",in_stock);data.put("merchant_count",merchant_count);data.put("published_at",published_at.toString());data.put("revision",revision);data.put("deleted",deleted);return data;
        }
    }
    public record Change(UUID event_id,UUID sku_id,long revision){}
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OutboxWriter outbox;private final JsonMapper json=JsonMapper.builder().build();
    public CatalogSearchSource(JdbcTemplate db,TransactionTemplate tx,OutboxWriter outbox){this.db=db;this.tx=tx;this.outbox=outbox;}
    public Change change(Product product,boolean deleted,String eventType,String correlation) {
        if(!CHANGE_EVENTS.contains(eventType))throw new IllegalArgumentException("Unsupported source event");
        return tx.execute(s->{
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","catalog-search-source:"+product.sku_id());
            var rows=db.queryForList("SELECT revision FROM catalog_search_source WHERE sku_id=? FOR UPDATE",product.sku_id());
            long revision=rows.isEmpty()?1:((Number)rows.getFirst().get("revision")).longValue()+1;
            db.update("INSERT INTO catalog_search_source(sku_id,spu_id,revision,document,deleted) VALUES (?,?,?,?::jsonb,?) ON CONFLICT(sku_id) DO UPDATE SET spu_id=excluded.spu_id,revision=excluded.revision,document=excluded.document,deleted=excluded.deleted,updated_at=clock_timestamp()",product.sku_id(),product.spu_id(),revision,json.writeValueAsString(product.document(revision,deleted)),deleted);
            UUID event=outbox.append("CATALOG_SKU",product.sku_id().toString(),eventType,1,Map.of("sku_id",product.sku_id().toString(),"revision",revision),correlation);
            return new Change(event,product.sku_id(),revision);
        });
    }
}
