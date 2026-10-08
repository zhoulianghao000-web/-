package cn.pawday.nearby;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1")
public class NearbyController {
 private final NearbyService service;private final AccessGuard guard;
 public NearbyController(NearbyService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/merchant/stores/{store_id}/nearby-profile") Object profile(@PathVariable String store_id,HttpServletRequest r){return Api.ok(service.profile(guard.actor(),id(store_id)),r);}
 @PutMapping("/merchant/stores/{store_id}/nearby-profile") Object save(@PathVariable String store_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,HttpServletRequest r){return Api.ok(service.save(guard.actor(),id(store_id),b,match,key,r),r);}
 @GetMapping("/admin/nearby/stores") Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.adminList(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/nearby/stores/{id}") Object adminDetail(@PathVariable String id,HttpServletRequest r){return Api.ok(service.adminDetail(guard.actor(),id(id)),r);}
 @PostMapping("/admin/nearby/stores/{id}/moderation") Object moderate(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.moderate(guard.actor(),id(id),b,match,key,proof,r),r);}
 @GetMapping("/public/nearby/places") Object nearby(@RequestParam(required=false)String city,@RequestParam(required=false)String category,@RequestParam(required=false)Double longitude,@RequestParam(required=false)Double latitude,@RequestParam(required=false)String coordinate_system,@RequestParam(defaultValue="10000")int radius_m,@RequestParam(defaultValue="0")int offset,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){var rows=service.nearby(city,category,longitude,latitude,coordinate_system,radius_m,offset,limit);boolean more=rows.size()>limit&&offset+limit<=10000;return new Api.ListEnvelope<>(rows.size()>limit?rows.subList(0,limit):rows,new Api.Page(more?Integer.toString(offset+limit):null,more),Api.meta(r));}
 @GetMapping("/public/nearby/places/{id}") Object detail(@PathVariable String id,HttpServletRequest r){return Api.ok(service.place(id(id)),r);}
 @PostMapping({"/public/nearby/navigation-intents","/consumer/nearby/navigation-intents"}) Object navigation(@RequestBody Map<String,Object>b,HttpServletRequest r){return Api.ok(service.navigation(b),r);}
}
