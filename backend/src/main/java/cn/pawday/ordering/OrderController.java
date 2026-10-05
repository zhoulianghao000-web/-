package cn.pawday.ordering;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class OrderController {
 private final OrderService service;private final AccessGuard guard;
 public OrderController(OrderService service,AccessGuard guard){this.service=service;this.guard=guard;}
 private Object page(List<Map<String,Object>> rows,int limit,HttpServletRequest r){boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}
 private UUID cursor(String c){return c==null?new UUID(0,0):guard.id(c);}
 @PostMapping("/consumer/orders")Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),b,key,r),r);}
 @GetMapping("/consumer/orders")Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return page(service.list(guard.actor(),false,cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/orders/{id}")Object get(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id),false),r);}
 @PostMapping("/consumer/orders/{id}/cancel")Object cancel(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,HttpServletRequest r){return Api.ok(service.cancel(guard.actor(),guard.id(id),b,match,key,r),r);}
 @GetMapping("/merchant/suborders")Object merchantList(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return page(service.merchantList(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/suborders/{id}")Object merchantGet(@PathVariable String id,HttpServletRequest r){return Api.ok(service.merchantGet(guard.actor(),guard.id(id)),r);}
 @GetMapping("/admin/orders")Object adminList(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return page(service.list(guard.actor(),true,cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/orders/{id}")Object adminGet(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id),true),r);}
 @GetMapping("/admin/order-policies")Object policy(HttpServletRequest r){return Api.ok(service.policy(guard.actor()),r);}
 @PostMapping("/admin/order-policies")Object policyPublish(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.publishPolicy(guard.actor(),b,key,proof,r),r);}
}
