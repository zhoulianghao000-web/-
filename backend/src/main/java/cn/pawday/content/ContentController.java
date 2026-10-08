package cn.pawday.content;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import cn.pawday.publishing.*;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.Map;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1")
public class ContentController {
 private final ContentService service;private final AccessGuard guard;
 public ContentController(ContentService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping("/public/content") Object publicList(@RequestParam(required=false)String category,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.publicList(category,cursor(cursor),limit),limit,r);}
 @GetMapping({"/public/content/{id}","/consumer/content/{id}"}) Object publicView(@PathVariable String id,@RequestParam(required=false)String pet_id,HttpServletRequest r){boolean publicRoute=r.getRequestURI().startsWith("/api/v1/public/");if(publicRoute&&pet_id!=null)throw new Api.Failure(400,"PUBLIC_PET_CONTEXT_NOT_ALLOWED");return Api.ok(service.publicView(guard.id(id),publicRoute?null:guard.actor(),pet_id==null?null:guard.id(pet_id)),r);}
 @GetMapping("/admin/content") Object adminList(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.adminList(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping("/admin/content/{id}") Object adminView(@PathVariable String id,HttpServletRequest r){return Api.ok(service.adminView(guard.actor(),guard.id(id)),r);}
 @PostMapping("/admin/content") Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),b,key,r),r);}
 @PatchMapping("/admin/content/{id}") Object update(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.update(guard.actor(),guard.id(id),b,match,key,r),r);}
 @PostMapping("/admin/content/{id}/submit") Object submit(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.submit(guard.actor(),guard.id(id),b,match,key,r),r);}
 @PostMapping("/admin/content/{id}/moderation") Object moderate(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.moderate(guard.actor(),guard.id(id),b,match,key,proof,r),r);}
 @GetMapping({"/public/content/{id}/media/{asset}","/admin/content/{id}/media/{asset}"}) Object media(@PathVariable String id,@PathVariable String asset,HttpServletRequest r){return PublishingMedia.response(service.content(r.getRequestURI().startsWith("/api/v1/public/")?null:guard.actor(),guard.id(id),guard.id(asset)));}
}
