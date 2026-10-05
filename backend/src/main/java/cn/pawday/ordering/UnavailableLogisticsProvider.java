package cn.pawday.ordering;
import java.util.*;
import org.springframework.stereotype.Component;
/** No production carrier selected: report missing evidence, never fabricate scans. */
@Component public class UnavailableLogisticsProvider implements LogisticsProvider {
 public boolean providerHealth(){return false;}
 public Map<String,Object> queryTracking(String carrier,String tracking,String reference){var result=new LinkedHashMap<String,Object>();result.put("carrier_code",carrier);result.put("tracking_no",tracking);result.put("status","UNKNOWN");result.put("events",List.of());result.put("last_synced_at",null);result.put("stale",true);result.put("provider_reference",reference);return result;}
}
