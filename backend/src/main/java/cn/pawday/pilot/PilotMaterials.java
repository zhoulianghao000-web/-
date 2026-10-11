package cn.pawday.pilot;

import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.stereotype.Component;

/** Trust is tied to an immutable, generated snapshot, never a caller-supplied source label. */
@Component
public class PilotMaterials {
 public static final String VERSION="cq-v1";
 private final PilotPolicy policy;
 public PilotMaterials(PilotPolicy policy){this.policy=policy;}
 public static UUID id(String name){return UUID.nameUUIDFromBytes(("pawday-pilot:cq-v1:"+name).getBytes(StandardCharsets.UTF_8));}
 public static UUID demo(String name){return UUID.nameUUIDFromBytes(("pawday-local-demo:"+name).getBytes(StandardCharsets.UTF_8));}
 public static int number(UUID sku){for(int n=1;n<=20;n++)if(id("sku-"+n).equals(sku))return n;return 0;}
 public static UUID media(int n){return id("media-"+(n%2==1?"a":"b"));}
 public void validateSources(List<?> refs){
  if(!policy.enabled()&&refs.stream().anyMatch(x->String.valueOf(x).trim().toLowerCase(Locale.ROOT).startsWith("pawday-pilot")))throw new cn.pawday.common.Api.Failure(400,"PILOT_SOURCE_NOT_ALLOWED");
 }
 public Map<String,Object> describe(UUID sku,UUID standard,List<?> refs){
  validateSources(refs);if(!policy.enabled())return null;
  int n=number(sku);boolean registered=n>0&&id("standard-"+n).equals(standard);
  boolean synthetic=registered&&n<=16&&refs.contains("pawday-pilot:cq-v1:SYNTHETIC:"+n);
  var result=new LinkedHashMap<String,Object>();
  result.put("kind",synthetic?"SYNTHETIC":"UNVERIFIED");
  result.put("label",synthetic?"合成测试商品，非真实商品依据":"未核验，仅供测试");
  result.put("generated_fixture",registered);result.put("production_approved",false);
  result.put("baseline_version",VERSION);
  result.put("media_path",registered&&refs.contains("pawday-pilot-media:"+media(n))?"/api/v1/consumer/pilot/skus/"+sku+"/media":null);
  return result;
 }
}
