package cn.pawday.payment;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class RefundController {
 private final RefundService service;private final AccessGuard guard;
 public RefundController(RefundService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/admin/refunds")Object list(@RequestParam(required=false)String status,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){UUID after=cursor==null?new UUID(0,0):guard.id(cursor);var rows=service.list(guard.actor(),status,after,limit);boolean more=rows.size()>limit;var data=rows.stream().limit(limit).toList();return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("id").toString():null,more),Api.meta(r));}
}
