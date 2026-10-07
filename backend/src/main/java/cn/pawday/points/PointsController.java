package cn.pawday.points;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class PointsController {
 private final PointsService service;private final AccessGuard guard;
 public PointsController(PointsService service,AccessGuard guard){this.service=service;this.guard=guard;}
 private UUID cursor(String c){return c==null?new UUID(0,0):guard.id(c);}
 private Object paged(List<Map<String,Object>> rows,int limit,HttpServletRequest r){boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}

 @GetMapping("/consumer/points")Object overview(HttpServletRequest r){return Api.ok(service.overview(guard.actor()),r);}
 @GetMapping("/consumer/points/ledger")Object ledger(@RequestParam(required=false)String entry_type,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.ledger(guard.actor(),entry_type,cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/points/checkins")Object checkins(@RequestParam(defaultValue="31")int limit,HttpServletRequest r){return Api.list(service.checkins(guard.actor(),limit),r);}
 @PostMapping("/consumer/points/checkins")Object checkin(@RequestBody(required=false)Map<String,Object> b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){if(b!=null&&!b.isEmpty())throw new Api.Failure(400,"VALIDATION_ERROR");return Api.ok(service.checkin(guard.actor(),key,r),r);}
 @GetMapping("/consumer/points/rewards")Object rewards(HttpServletRequest r){return Api.list(service.rewards(guard.actor()),r);}
 @PostMapping("/consumer/points/redemptions")Object redeem(@RequestBody Map<String,Object> b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.redeem(guard.actor(),b,key,r),r);}

 @GetMapping("/admin/points-policies")Object policies(HttpServletRequest r){return Api.list(service.policies(guard.actor()),r);}
 @PostMapping("/admin/points-policies")Object createPolicy(@RequestBody Map<String,Object> b,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createPolicy(guard.actor(),b,proof,r),r);}
 @GetMapping("/admin/points-rewards")Object adminRewards(HttpServletRequest r){return Api.list(service.adminRewards(guard.actor()),r);}
 @PostMapping("/admin/points-rewards")Object createReward(@RequestBody Map<String,Object> b,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createReward(guard.actor(),b,proof,r),r);}
 @GetMapping("/admin/users/{id}/points")Object adminOverview(@PathVariable String id,HttpServletRequest r){return Api.ok(service.adminOverview(guard.actor(),guard.id(id)),r);}
 @GetMapping("/admin/users/{id}/points/ledger")Object adminLedger(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.adminLedger(guard.actor(),guard.id(id),cursor(cursor),limit),limit,r);}
 @PostMapping("/admin/users/{id}/points-adjustments")Object adjust(@PathVariable String id,@RequestBody Map<String,Object> b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.adjust(guard.actor(),guard.id(id),b,key,proof,r),r);}
}
