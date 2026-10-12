package cn.pawday.care;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1") public class InvoiceController {
 private final InvoiceService service;private final AccessGuard guard;
 public InvoiceController(InvoiceService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping({"/consumer/invoices","/merchant/invoices","/admin/invoices"})Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.list(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping({"/consumer/invoices/{application}","/merchant/invoices/{application}","/admin/invoices/{application}"})Object get(@PathVariable String application,HttpServletRequest r){return Api.ok(service.detail(guard.actor(),id(application),r),r);}
 @PostMapping("/consumer/invoices")Object apply(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.apply(guard.actor(),b,key,r),r);}
 @PostMapping("/merchant/invoices/{application}/decision")Object handle(@PathVariable String application,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.handle(guard.actor(),id(application),b,match,key,proof,r),r);}
}
