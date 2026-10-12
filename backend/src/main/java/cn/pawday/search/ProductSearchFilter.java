package cn.pawday.search;
import cn.pawday.common.Api.Failure;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
/** Closed, canonical filter set shared by search and persisted demand context. Money is integer fen. */
public record ProductSearchFilter(String q,String petCategory,UUID brandId,Long minPrice,Long maxPrice,UUID lifeStage,String foodType,Integer minWeight,Integer maxWeight,String unit,List<UUID> excluded,Boolean inStock,String sort) {
 public static final Set<String> KEYS=Set.of("q","pet_category","brand_id","price_min_fen","price_max_fen","life_stage_id","food_type","weight_min_g","weight_max_g","package_unit","exclude_allergen_ids","in_stock","sort");
 public static final Set<String> SORTS=Set.of("RELEVANCE","PRICE_ASC","PRICE_DESC","SALES_DESC","RATING_DESC");
 public static final Set<String> CATEGORIES=Set.of("CAT","DOG","AQUATIC","BIRD","SMALL_PET");
 public static ProductSearchFilter parse(Map<String,String> raw){
  if(!KEYS.containsAll(raw.keySet()))throw new Failure(400,"VALIDATION_ERROR");
  String q=value(raw,"q",160),cat=value(raw,"pet_category",20),sort=raw.getOrDefault("sort","RELEVANCE"),food=value(raw,"food_type",80),unit=value(raw,"package_unit",40);
  if(cat!=null&&!CATEGORIES.contains(cat)||!SORTS.contains(sort))throw new Failure(400,"VALIDATION_ERROR");
  Long lo=number(raw,"price_min_fen",1000000000L),hi=number(raw,"price_max_fen",1000000000L),wl=number(raw,"weight_min_g",100000000L),wh=number(raw,"weight_max_g",100000000L);
  if(lo!=null&&hi!=null&&lo>hi||wl!=null&&wh!=null&&wl>wh)throw new Failure(400,"VALIDATION_ERROR");
  List<UUID> exclude=new ArrayList<>();String ex=value(raw,"exclude_allergen_ids",800);if(ex!=null){for(String x:ex.split(",",-1))exclude.add(id(x));if(exclude.size()>20||new HashSet<>(exclude).size()!=exclude.size())throw new Failure(400,"VALIDATION_ERROR");exclude.sort(Comparator.naturalOrder());}
  String stock=raw.get("in_stock");if(stock!=null&&!Set.of("true","false").contains(stock))throw new Failure(400,"VALIDATION_ERROR");
  return new ProductSearchFilter(q,cat,uuid(raw,"brand_id"),lo,hi,uuid(raw,"life_stage_id"),food,wl==null?null:wl.intValue(),wh==null?null:wh.intValue(),unit,List.copyOf(exclude),stock==null?null:Boolean.valueOf(stock),sort);
 }
 private static String value(Map<String,String> m,String k,int max){String v=m.get(k);if(v==null)return null;if(v.length()>max||v.isBlank())throw new Failure(400,"VALIDATION_ERROR");return v.trim();}
 private static UUID uuid(Map<String,String>m,String k){return m.containsKey(k)?id(m.get(k)):null;}
 private static Long number(Map<String,String>m,String k,long max){if(!m.containsKey(k))return null;try{String s=m.get(k);if(!s.matches("[0-9]{1,10}"))throw new Exception();long n=Long.parseLong(s);if(n>max)throw new Exception();return n;}catch(Exception bad){throw new Failure(400,"VALIDATION_ERROR");}}
 public Map<String,String> canonical(){var m=new TreeMap<String,String>();m.put("sort",sort);put(m,"q",q);put(m,"pet_category",petCategory);put(m,"brand_id",brandId);put(m,"price_min_fen",minPrice);put(m,"price_max_fen",maxPrice);put(m,"life_stage_id",lifeStage);put(m,"food_type",foodType);put(m,"weight_min_g",minWeight);put(m,"weight_max_g",maxWeight);put(m,"package_unit",unit);if(!excluded.isEmpty())m.put("exclude_allergen_ids",String.join(",",excluded.stream().map(UUID::toString).toList()));put(m,"in_stock",inStock);return m;}
 private static void put(Map<String,String>m,String k,Object v){if(v!=null)m.put(k,v.toString());}
}
