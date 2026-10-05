package cn.pawday.checkout;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1")
public class CheckoutController {
 private final CheckoutService service;private final AccessGuard guard;
 public CheckoutController(CheckoutService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/consumer/cart") Object cart(HttpServletRequest r){return Api.ok(service.cartView(guard.actor()),r);}
 @GetMapping("/consumer/checkout/benefits") Object benefits(HttpServletRequest r){return Api.ok(service.benefits(guard.actor()),r);}
 @PostMapping("/consumer/cart/items") Object add(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.add(guard.actor(),b,key),r);}
 @PatchMapping("/consumer/cart/items/{id}") Object patch(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.patch(guard.actor(),guard.id(id),b,match,key),r);}
 @DeleteMapping("/consumer/cart/items/{id}") Object delete(@PathVariable String id,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.delete(guard.actor(),guard.id(id),match,key),r);}
 @PostMapping("/consumer/cart/merge-guest-intent") Object merge(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.merge(guard.actor(),b,key),r);}
 @GetMapping("/consumer/addresses") Object addresses(HttpServletRequest r){return Api.list(service.addresses(guard.actor()),r);}
 @PostMapping("/consumer/addresses") Object address(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.saveAddress(guard.actor(),null,b,null,key),r);}
 @PatchMapping("/consumer/addresses/{id}") Object addressPatch(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.saveAddress(guard.actor(),guard.id(id),b,match,key),r);}
 @DeleteMapping("/consumer/addresses/{id}") Object addressDelete(@PathVariable String id,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.deleteAddress(guard.actor(),guard.id(id),match,key),r);}
 @PostMapping("/consumer/checkout/quotes") Object quote(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.quote(guard.actor(),b,key),r);}
 @GetMapping("/consumer/checkout/quotes/{id}") Object quoteGet(@PathVariable String id,HttpServletRequest r){return Api.ok(service.getQuote(guard.actor(),guard.id(id)),r);}
 @GetMapping("/admin/merchants/{id}/shipping-rules") Object shipping(@PathVariable String id,HttpServletRequest r){return Api.ok(service.shipping(guard.actor(),guard.id(id)),r);}
 @PostMapping("/admin/merchants/{id}/shipping-rules") Object shippingPublish(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.publishShipping(guard.actor(),guard.id(id),b,key,proof,r),r);}
}
