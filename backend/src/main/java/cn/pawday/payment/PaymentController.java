package cn.pawday.payment;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class PaymentController {
 private final PaymentService service;private final AccessGuard guard;
 public PaymentController(PaymentService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping({"/consumer/payments/{id}","/consumer/payments/{id}/status"})Object get(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id),false),r);}
 @PostMapping("/consumer/payments/{id}/attempts")Object attempt(@PathVariable String id,@RequestBody java.util.Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.attempt(guard.actor(),guard.id(id),b,key,r),r);}
 @PostMapping("/consumer/payments/{id}/close-attempt")Object close(@PathVariable String id,HttpServletRequest r){return Api.ok(service.close(guard.actor(),guard.id(id)),r);}
 @PostMapping("/consumer/payments/{id}/requery")Object query(@PathVariable String id,HttpServletRequest r){return Api.ok(service.requery(guard.actor(),guard.id(id),false,null,null,r),r);}
 @GetMapping("/admin/payments/{id}")Object admin(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id),true),r);}
 @PostMapping("/admin/payments/{id}/requery")Object adminQuery(@PathVariable String id,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.requery(guard.actor(),guard.id(id),true,key,proof,r),r);}
}
