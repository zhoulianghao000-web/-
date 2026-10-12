package cn.pawday.care;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class PurchaseRequestController {
 private final PurchaseRequestService service;private final AccessGuard guard;public PurchaseRequestController(PurchaseRequestService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping({"/consumer/purchase-requests","/admin/purchase-requests"})Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,@RequestParam(required=false)String status,HttpServletRequest r){return paged(service.list(guard.actor(),cursor(cursor),limit,status),limit,r);}
 @GetMapping({"/consumer/purchase-requests/{id}","/admin/purchase-requests/{id}"})Object detail(@PathVariable String id,HttpServletRequest r){return Api.ok(service.detail(guard.actor(),id(id),r),r);}
 @GetMapping({"/consumer/purchase-requests/{id}/history","/admin/purchase-requests/{id}/history"})Object history(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.history(guard.actor(),id(id),cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/purchase-requests")Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),b,key,r),r);}
 @PostMapping("/consumer/purchase-requests/{id}/cancel")Object cancel(@PathVariable String id,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.cancel(guard.actor(),id(id),match,key,r),r);}
 @PostMapping("/admin/purchase-requests/{id}/decision")Object handle(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.handle(guard.actor(),id(id),b,match,key,proof,r),r);}
}
