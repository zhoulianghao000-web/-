package cn.pawday.membership;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class MembershipController {
 private final MembershipService service;private final AccessGuard guard;
 public MembershipController(MembershipService service,AccessGuard guard){this.service=service;this.guard=guard;}
 private UUID cursor(String c){return c==null?new UUID(0,0):guard.id(c);}
 private Object paged(List<Map<String,Object>> rows,int limit,HttpServletRequest r){boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}

 @GetMapping("/consumer/membership/plans")Object plans(HttpServletRequest r){return Api.list(service.plans(guard.actor()),r);}
 @GetMapping("/consumer/membership")Object current(HttpServletRequest r){return Api.ok(service.current(guard.actor()),r);}
 @GetMapping("/consumer/membership/orders")Object orders(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.orders(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/membership/orders/{id}")Object order(@PathVariable String id,HttpServletRequest r){return Api.ok(service.getOrder(guard.actor(),guard.id(id)),r);}
 @PostMapping("/consumer/membership/orders")Object purchase(@RequestBody Map<String,Object> b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.purchase(guard.actor(),b,key,r),r);}

 @GetMapping("/admin/membership-plans")Object adminPlans(HttpServletRequest r){return Api.list(service.adminPlans(guard.actor()),r);}
 @PostMapping("/admin/membership-plans")Object createPlan(@RequestBody Map<String,Object> b,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createPlan(guard.actor(),b,proof,r),r);}
}
