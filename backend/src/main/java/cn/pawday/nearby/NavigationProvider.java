package cn.pawday.nearby;

import java.util.Map;
/** Destination handoff only. Providers must not accept arbitrary client URLs or coordinates. */
public interface NavigationProvider {
 Map<String,Object> intent(Map<String,Object> destination,String mode);
}
