package cn.pawday.booking;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1")
public class ServiceTradeSettlementController {
 private final ServiceTradeSettlement settlement;private final AccessGuard guard;
 public ServiceTradeSettlementController(ServiceTradeSettlement settlement,AccessGuard guard){this.settlement=settlement;this.guard=guard;}
 @GetMapping("/merchant/stores/{store_id}/service-trade-ledger")
 Object ledger(@PathVariable String store_id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(settlement.ledger(guard.actor(),id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/admin/merchants/{merchant_id}/service-trade-settlement-previews")
 Object preview(@PathVariable String merchant_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(settlement.preview(guard.actor(),id(merchant_id),b,key,r),r);}
 @PostMapping("/admin/merchants/{merchant_id}/service-trade-settlements")
 Object settle(@PathVariable String merchant_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(settlement.settle(guard.actor(),id(merchant_id),b,key,proof,r),r);}
 @GetMapping("/admin/merchants/{merchant_id}/service-trade-reconciliation")
 Object reconcile(@PathVariable String merchant_id,HttpServletRequest r){return Api.ok(settlement.reconcile(guard.actor(),id(merchant_id)),r);}
}
