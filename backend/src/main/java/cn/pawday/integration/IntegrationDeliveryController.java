package cn.pawday.integration;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1/merchant/stores/{store_id}/integration-connections/{connection_id}/order-deliveries")
public class IntegrationDeliveryController {
 private final IntegrationDeliveryService service;private final AccessGuard guard;
 public IntegrationDeliveryController(IntegrationDeliveryService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping Object list(@PathVariable String store_id,@PathVariable String connection_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.list(guard.actor(),id(store_id),id(connection_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/{delivery_id}/requery") Object query(@PathVariable String store_id,@PathVariable String connection_id,@PathVariable String delivery_id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String version,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.act(guard.actor(),id(store_id),id(connection_id),id(delivery_id),false,b,version,key,null,r),r);}
 @PostMapping("/{delivery_id}/retry") Object retry(@PathVariable String store_id,@PathVariable String connection_id,@PathVariable String delivery_id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String version,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.act(guard.actor(),id(store_id),id(connection_id),id(delivery_id),true,b,version,key,proof,r),r);}
}
