package cn.pawday.offer;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
public class OfferController {
 private final OfferService service; private final AccessGuard guard;
 public OfferController(OfferService service,AccessGuard guard){this.service=service;this.guard=guard;}
 private boolean admin(HttpServletRequest r){return r.getRequestURI().startsWith("/api/v1/admin/");}
 @GetMapping({"/api/v1/merchant/offers","/api/v1/admin/offers"})
 Object list(@RequestParam(required=false)String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){var p=service.list(guard.actor(),admin(r),store_id==null?null:guard.id(store_id),cursor,limit);return new Api.ListEnvelope<>(p.data(),new Api.Page(p.cursor(),p.more()),Api.meta(r));}
 @GetMapping({"/api/v1/merchant/offers/{id}","/api/v1/admin/offers/{id}"})
 Object get(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),admin(r),guard.id(id)),r);}
 @PostMapping("/api/v1/merchant/offers")
 Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return ResponseEntity.status(201).body(Api.ok(service.create(guard.actor(),b,key,r),r));}
 @PatchMapping("/api/v1/merchant/offers/{id}")
 Object patch(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.patch(guard.actor(),guard.id(id),b,match,key,r),r);}
 @PostMapping("/api/v1/merchant/offers/batch")
 Object batch(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.batch(guard.actor(),b,key,r),r);}
 @PostMapping({"/api/v1/merchant/offers/{id}/activate","/api/v1/merchant/offers/{id}/pause","/api/v1/admin/offers/{id}/freeze","/api/v1/admin/offers/{id}/unfreeze","/api/v1/admin/offers/{id}/delist"})
 Object state(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="X-Reverify-Token",required=false)String proof,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){String action=r.getRequestURI().substring(r.getRequestURI().lastIndexOf('/')+1);return Api.ok(service.state(guard.actor(),admin(r),guard.id(id),action,b,match,proof,key,r),r);}
 @PostMapping("/api/v1/merchant/offers/{id}/inventory-adjustments")
 Object adjust(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return ResponseEntity.status(201).body(Api.ok(service.adjust(guard.actor(),guard.id(id),b,key,r),r));}
 @GetMapping({"/api/v1/merchant/offers/{id}/inventory-adjustments","/api/v1/admin/offers/{id}/inventory-adjustments"})
 Object adjustments(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){var p=service.adjustments(guard.actor(),admin(r),guard.id(id),cursor,limit);return new Api.ListEnvelope<>(p.data(),new Api.Page(p.cursor(),p.more()),Api.meta(r));}
}
