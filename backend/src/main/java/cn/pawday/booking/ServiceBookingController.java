package cn.pawday.booking;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import static cn.pawday.publishing.PublishingSupport.*;

@RestController @RequestMapping("/api/v1")
public class ServiceBookingController {
 private final ServiceBookingService service;private final AccessGuard guard;
 public ServiceBookingController(ServiceBookingService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/consumer/service-bookings/{id}/credential") Object credential(@PathVariable String id,HttpServletRequest r,jakarta.servlet.http.HttpServletResponse response){response.setHeader("Cache-Control","no-store");return Api.ok(service.credential(guard.actor(),id(id)),r);}
 @GetMapping("/consumer/service-bookings/{id}/fulfillment") Object history(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.fulfillment(guard.actor(),id(id),null,cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/stores/{store_id}/service-bookings/{id}/fulfillment") Object historyByStore(@PathVariable String store_id,@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.fulfillment(guard.actor(),id(id),id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/merchant/stores/{store_id}/service-bookings/{id}/fulfillment") Object fulfill(@PathVariable String store_id,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.fulfill(guard.actor(),id(id),id(store_id),b,match,key,r),r);}
 @GetMapping("/merchant/stores/{store_id}/booking-services") Object merchantServices(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.services(guard.actor(),id(store_id),true,cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/stores/{store_id}/booking-services") Object consumerServices(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.services(guard.actor(),id(store_id),false,cursor(cursor),limit),limit,r);}
 @PostMapping("/merchant/stores/{store_id}/booking-services") Object create(@PathVariable String store_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),id(store_id),b,key,r),r);}
 @PutMapping("/merchant/booking-services/{id}/state") Object state(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.state(guard.actor(),id(id),b,match,key,r),r);}
 @PostMapping("/merchant/booking-services/{id}/slots") Object createSlot(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.slot(guard.actor(),id(id),b,key,r),r);}
 @GetMapping("/merchant/booking-services/{id}/slots") Object merchantSlots(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.slots(guard.actor(),id(id),true,cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/booking-services/{id}/slots") Object consumerSlots(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.slots(guard.actor(),id(id),false,cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/service-bookings") Object book(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.book(guard.actor(),b,key,r),r);}
 @GetMapping("/consumer/service-bookings") Object mine(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.bookings(guard.actor(),null,cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/stores/{store_id}/service-bookings") Object bookings(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.bookings(guard.actor(),id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/service-bookings/{id}/cancel") Object cancel(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b);return Api.ok(service.cancel(guard.actor(),id(id),null,match,key,r),r);}
 @PostMapping("/merchant/stores/{store_id}/service-bookings/{id}/cancel") Object cancelByStore(@PathVariable String store_id,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b);return Api.ok(service.cancel(guard.actor(),id(id),id(store_id),match,key,r),r);}
}
