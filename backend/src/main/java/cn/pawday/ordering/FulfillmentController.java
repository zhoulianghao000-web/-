package cn.pawday.ordering;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class FulfillmentController {
 private final FulfillmentService service;private final AccessGuard guard;
 public FulfillmentController(FulfillmentService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping({"/merchant/suborders/{id}/fulfillment","/consumer/suborders/{id}/fulfillment","/admin/suborders/{id}/fulfillment"})Object get(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id)),r);}
 @GetMapping({"/merchant/shipments/{id}/tracking","/consumer/shipments/{id}/tracking","/admin/shipments/{id}/tracking"})Object tracking(@PathVariable String id,HttpServletRequest r){return Api.ok(service.tracking(guard.actor(),guard.id(id)),r);}
 @PostMapping("/merchant/suborders/{id}/shipments")Object ship(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.ship(guard.actor(),guard.id(id),b,match,key,r),r);}
 @PostMapping("/consumer/suborders/{id}/confirm-receipt")Object receive(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.receive(guard.actor(),guard.id(id),b,match,key,r),r);}
}
