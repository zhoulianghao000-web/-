package cn.pawday.booking;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.*;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1")
public class ServiceTradeOperationsController {
 private final ServiceTradeOperations operations;private final AccessGuard guard;
 public ServiceTradeOperationsController(ServiceTradeOperations operations,AccessGuard guard){this.operations=operations;this.guard=guard;}
 @GetMapping("/consumer/service-trade-orders/{id}/credential")
 Object credential(@PathVariable String id,HttpServletRequest r,HttpServletResponse response){response.setHeader("Cache-Control","no-store");return Api.ok(operations.credential(guard.actor(),id(id)),r);}
 @GetMapping("/consumer/service-trade-orders/{id}/fulfillment")
 Object consumerHistory(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(operations.fulfillment(guard.actor(),id(id),null,cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/stores/{store_id}/service-trade-orders/{id}/fulfillment")
 Object merchantHistory(@PathVariable String store_id,@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(operations.fulfillment(guard.actor(),id(id),id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/merchant/stores/{store_id}/service-trade-orders/{id}/fulfillment")
 Object fulfill(@PathVariable String store_id,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(operations.fulfill(guard.actor(),id(id),id(store_id),b,match,key,r),r);}
 @GetMapping("/consumer/service-trade-orders/{id}/disputes")
 Object consumerDisputes(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(operations.disputes(guard.actor(),id(id),null,false,cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/service-trade-orders/{id}/disputes")
 Object openDispute(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(operations.dispute(guard.actor(),id(id),b,match,key,r),r);}
 @GetMapping("/merchant/stores/{store_id}/service-trade-orders/{id}/disputes")
 Object merchantDisputes(@PathVariable String store_id,@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(operations.disputes(guard.actor(),id(id),id(store_id),false,cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/service-trade-orders/{id}/disputes")
 Object adminDisputes(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(operations.disputes(guard.actor(),id(id),null,true,cursor(cursor),limit),limit,r);}
 @PostMapping("/admin/service-trade-orders/{id}/disputes/{dispute_id}/decisions")
 Object resolve(@PathVariable String id,@PathVariable String dispute_id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(operations.resolve(guard.actor(),id(id),id(dispute_id),b,match,key,proof,r),r);}
}
