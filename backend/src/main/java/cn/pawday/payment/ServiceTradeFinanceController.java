package cn.pawday.payment;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
import static cn.pawday.publishing.PublishingSupport.*;

@RestController @RequestMapping("/api/v1")
public class ServiceTradeFinanceController {
 private final ServiceTradeFinance finance;private final AccessGuard guard;
 public ServiceTradeFinanceController(ServiceTradeFinance finance,AccessGuard guard){this.finance=finance;this.guard=guard;}
 private UUID cursor(String c){return c==null?new UUID(0,0):id(c);}
 @PostMapping("/consumer/service-trade-orders/{id}/payment-attempts")Object attempt(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(finance.attempt(guard.actor(),id(id),b,match,key,r),r);}
 @GetMapping("/consumer/service-trade-orders/{id}/payment")Object payment(@PathVariable String id,HttpServletRequest r){return Api.ok(finance.readPayment(guard.actor(),id(id)),r);}
 @PostMapping("/consumer/service-trade-orders/{id}/payment-requery")Object requery(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b);return Api.ok(finance.requery(guard.actor(),id(id),match,key,r),r);}
 @PostMapping("/merchant/stores/{store_id}/service-trade-orders/{id}/cancel")Object cancel(@PathVariable String store_id,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b,"reason_code");if(!"SERVICE_UNAVAILABLE".equals(b.get("reason_code")))throw new Api.Failure(400,"VALIDATION_ERROR");return Api.ok(finance.cancel(guard.actor(),id(id),id(store_id),"SERVICE_UNAVAILABLE",match,key,r),r);}
 @GetMapping("/consumer/service-trade-orders/{id}/refunds")Object refunds(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){var rows=finance.refunds(guard.actor(),id(id),cursor(cursor),limit);boolean more=rows.size()>limit;var data=rows.subList(0,Math.min(rows.size(),limit));return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}
 @PostMapping("/admin/service-trade-orders/{id}/refund-assessments")Object assessment(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b);return Api.ok(finance.assess(guard.actor(),id(id),match,key,r),r);}
 @PostMapping("/admin/service-trade-orders/{id}/refund-decisions")Object decision(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(finance.decide(guard.actor(),id(id),b,match,key,proof,r),r);}
}
