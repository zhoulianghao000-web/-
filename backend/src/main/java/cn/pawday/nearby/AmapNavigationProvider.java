package cn.pawday.nearby;

import cn.pawday.common.Api.Failure;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class AmapNavigationProvider implements NavigationProvider {
 private final boolean enabled;
 public AmapNavigationProvider(@Value("${pawday.nearby.navigation-enabled:true}")boolean enabled){this.enabled=enabled;}
 private static String enc(String v){return URLEncoder.encode(v,StandardCharsets.UTF_8);}
 public Map<String,Object> intent(Map<String,Object> d,String mode){
  if(!enabled)throw new Failure(503,"NAVIGATION_PROVIDER_UNAVAILABLE");
  if(!"DESTINATION".equals(mode))throw new Failure(400,"VALIDATION_ERROR");
  // The official marker URI explicitly supports WGS84. Its map UI owns travel-mode
  // selection/navigation; do not pass WGS84 to route APIs with undocumented coordinate semantics.
  String route="https://uri.amap.com/marker?position="+enc(d.get("longitude")+","+d.get("latitude"))+"&name="+enc(d.get("name").toString())+"&coordinate=wgs84&src=pawday&callnative=";
  return Map.of("provider","AMAP_URI","place_id",d.get("id"),"destination_name",d.get("name"),"longitude",d.get("longitude"),"latitude",d.get("latitude"),"coordinate_system","WGS84","mode",mode,"launch_url",route+"1","fallback_url",route+"0");
 }
}
