package cn.pawday.booking;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import static cn.pawday.publishing.PublishingSupport.*;

@RestController @RequestMapping("/api/v1")
public class ServiceTradeController {
 private final ServiceTradeService service;private final AccessGuard guard;
 public ServiceTradeController(ServiceTradeService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/merchant/stores/{store_id}/service-trade-terms") Object terms(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.termsList(guard.actor(),id(store_id),cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/service-trade-terms") Object pending(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.termsList(guard.actor(),null,cursor(cursor),limit),limit,r);}
 @PostMapping("/merchant/stores/{store_id}/service-trade-terms") Object draft(@PathVariable String store_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.draft(guard.actor(),id(store_id),b,key,r),r);}
 @PostMapping("/admin/service-trade-terms/{id}/review") Object review(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.review(guard.actor(),id(id),b,match,key,proof,r),r);}
 @GetMapping("/consumer/service-trade-terms/{id}") Object readTerms(@PathVariable String id,HttpServletRequest r){return Api.ok(service.readTerms(guard.actor(),id(id),false),r);}
 @GetMapping("/consumer/booking-services/{id}/trade-terms") Object currentTerms(@PathVariable String id,HttpServletRequest r){return Api.ok(service.readTerms(guard.actor(),id(id),true),r);}
 @PostMapping("/consumer/service-trade-quotes") Object quote(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.quote(guard.actor(),b,key,r),r);}
 @PostMapping("/consumer/service-trade-orders") Object reserve(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.reserve(guard.actor(),b,key,r),r);}
 @GetMapping("/consumer/service-trade-orders/{id}") Object read(@PathVariable String id,HttpServletRequest r){return Api.ok(service.read(guard.actor(),id(id)),r);}
 @GetMapping("/consumer/service-trade-orders") Object mine(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.trades(guard.actor(),null,cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/stores/{store_id}/service-trade-orders") Object store(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.trades(guard.actor(),id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/service-trade-orders/{id}/cancel") Object cancel(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){if(!b.isEmpty()){fields(b,"reason_code");if(!"CONSUMER_CANCELLED".equals(b.get("reason_code")))throw new Api.Failure(400,"VALIDATION_ERROR");}return Api.ok(service.cancel(guard.actor(),id(id),match,key,r),r);}
}
