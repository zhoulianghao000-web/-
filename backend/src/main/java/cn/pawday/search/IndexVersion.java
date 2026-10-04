package cn.pawday.search;
import java.util.*;
/** V1 strict document shape; tombstones retain external versions permanently. */
public final class IndexVersion {
    private IndexVersion(){}
    public static final int SCHEMA=1;
    public static final String INITIAL="pawday-product-v1-000001",READ_ALIAS="pawday-product-read",WRITE_ALIAS="pawday-product-write";
    public static Map<String,Object> definition() {
        var props=new LinkedHashMap<String,Object>();
        for(String field:List.of("spu_id","sku_id","brand","pet_category","life_stage","food_type","allergens"))props.put(field,Map.of("type","keyword"));
        props.put("price_min_fen",Map.of("type","long"));props.put("merchant_count",Map.of("type","integer"));
        props.put("in_stock",Map.of("type","boolean"));props.put("deleted",Map.of("type","boolean"));
        props.put("published_at",Map.of("type","date"));props.put("revision",Map.of("type","long"));
        return Map.of("settings",Map.of("number_of_shards",1,"number_of_replicas",0),
            "mappings",Map.of("dynamic","strict","_meta",Map.of("pawday_schema_version",SCHEMA),"properties",props));
    }
    @SuppressWarnings("unchecked") public static void validate(OpenSearchClient client,String index) {
        var mapping=client.request("GET","/"+OpenSearchClient.index(index)+"/_mapping",null);
        var mappings=(Map<String,Object>)((Map<String,Object>)mapping.get(index)).get("mappings");
        var meta=(Map<String,Object>)mappings.get("_meta");
        var expected=(Map<String,Object>)definition().get("mappings");
        if(meta==null || ((Number)meta.getOrDefault("pawday_schema_version",0)).intValue()!=SCHEMA || !"strict".equals(mappings.get("dynamic"))
            || !expected.get("properties").equals(mappings.get("properties")))throw new OpenSearchClient.Unavailable("SEARCH_MAPPING_MISMATCH");
    }
    public static void ensure(OpenSearchClient client,String index) {
        client.request("PUT","/"+OpenSearchClient.index(index),definition(),400);validate(client,index);
        // An existing index is accepted only after exact controlled mapping validation.
    }
}
