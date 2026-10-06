package cn.pawday.ordering;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class CancellationController {
 private final CancellationService service;private final AccessGuard guard;
 public CancellationController(CancellationService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @PostMapping({"/consumer/suborders/{id}/cancellations","/merchant/suborders/{id}/cancellations"})Object create(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),guard.id(id),b,key,r),r);}
 @GetMapping({"/consumer/suborders/{id}/cancellations","/merchant/suborders/{id}/cancellations"})Object list(@PathVariable String id,HttpServletRequest r){return Api.list(service.list(guard.actor(),guard.id(id)),r);}
 @GetMapping({"/consumer/cancellations/{id}","/merchant/cancellations/{id}","/admin/cancellations/{id}"})Object get(@PathVariable String id,HttpServletRequest r){return Api.ok(service.get(guard.actor(),guard.id(id)),r);}
 @GetMapping("/admin/cancellations")Object adminList(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){UUID after=cursor==null?new UUID(0,0):guard.id(cursor);var rows=service.adminList(guard.actor(),after,limit);boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}
}
