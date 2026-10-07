package cn.pawday.settlement;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class SettlementController {
 private final SettlementService service;private final AccessGuard guard;
 public SettlementController(SettlementService service,AccessGuard guard){this.service=service;this.guard=guard;}
 private UUID cursor(String c){return c==null?new UUID(0,0):guard.id(c);}
 private Object paged(List<Map<String,Object>> rows,int limit,HttpServletRequest r){boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}

 @GetMapping("/admin/commission-policies")Object commissionPolicies(HttpServletRequest r){return Api.list(service.commissionPolicies(guard.actor()),r);}
 @PostMapping("/admin/commission-policies")Object createCommissionPolicy(@RequestBody Map<String,Object>b,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createCommissionPolicy(guard.actor(),b,proof,r),r);}
 @GetMapping("/admin/settlement-policies")Object settlementPolicies(HttpServletRequest r){return Api.list(service.settlementPolicies(guard.actor()),r);}
 @PostMapping("/admin/settlement-policies")Object createSettlementPolicy(@RequestBody Map<String,Object>b,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createSettlementPolicy(guard.actor(),b,proof,r),r);}

 @GetMapping({"/admin/settlement-tracks","/merchant/settlement-tracks"})Object tracks(@RequestParam(required=false)String status,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.listTracks(guard.actor(),status,cursor(cursor),limit),limit,r);}
 @GetMapping({"/admin/settlements","/merchant/settlements"})Object settlements(@RequestParam(required=false)String status,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.listSettlements(guard.actor(),status,cursor(cursor),limit),limit,r);}
 @GetMapping({"/admin/settlements/{id}","/merchant/settlements/{id}"})Object settlement(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id)),r);}
 @PostMapping("/admin/merchants/{id}/settlements")Object initiate(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){if(!b.isEmpty())throw new Api.Failure(400,"VALIDATION_ERROR");return Api.ok(service.initiate(guard.actor(),guard.id(id),key,proof,r),r);}
 @PostMapping("/admin/settlements/{id}/retry")Object retry(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){if(!b.isEmpty())throw new Api.Failure(400,"VALIDATION_ERROR");return Api.ok(service.retry(guard.actor(),guard.id(id),key,proof,r),r);}

 @GetMapping("/admin/merchants/{id}/ledger")Object adminLedger(@PathVariable String id,@RequestParam(required=false)String entry_type,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.listEntries(guard.actor(),guard.id(id),entry_type,cursor(cursor),limit),limit,r);}
 @GetMapping("/merchant/ledger")Object merchantLedger(@RequestParam(required=false)String entry_type,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.listEntries(guard.actor(),null,entry_type,cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/merchants/{id}/finance-summary")Object adminSummary(@PathVariable String id,HttpServletRequest r){return Api.ok(service.summary(guard.actor(),guard.id(id)),r);}
 @GetMapping("/merchant/finance-summary")Object merchantSummary(HttpServletRequest r){return Api.ok(service.summary(guard.actor(),null),r);}
 @PostMapping("/admin/merchants/{id}/ledger-adjustments")Object adjust(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.adjust(guard.actor(),guard.id(id),b,key,proof,r),r);}
 @GetMapping("/admin/finance/reconciliation")Object reconcile(HttpServletRequest r){return Api.ok(service.reconcile(guard.actor()),r);}
}
