package cn.pawday.ordering;
import java.util.Map;
/** Provider credentials and I/O stay on the server. Tracking never confirms receipt. */
public interface LogisticsProvider {
 Map<String,Object> queryTracking(String carrierCode,String trackingNo,String shipmentReference);
 boolean providerHealth();
}
