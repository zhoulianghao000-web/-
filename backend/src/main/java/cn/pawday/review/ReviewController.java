package cn.pawday.review;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import cn.pawday.publishing.*;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.Map;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController @RequestMapping("/api/v1")
public class ReviewController {
 private final ReviewService service;private final AccessGuard guard;
 public ReviewController(ReviewService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping({"/public/spus/{id}/reviews","/consumer/spus/{id}/reviews"}) Object publicList(@PathVariable String id,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.publicList(guard.id(id),cursor(cursor),limit),limit,r);}
 @GetMapping("/public/reviews/{id}") Object publicView(@PathVariable String id,HttpServletRequest r){return Api.ok(service.publicView(guard.id(id)),r);}
 @GetMapping("/consumer/order-items/{id}/review-eligibility") Object eligibility(@PathVariable String id,HttpServletRequest r){return Api.ok(service.eligibility(guard.actor(),guard.id(id)),r);}
 @PostMapping("/consumer/order-items/{id}/reviews") Object create(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),guard.id(id),b,key,r),r);}
 @GetMapping({"/consumer/reviews/{id}","/admin/reviews/{id}"}) Object detail(@PathVariable String id,HttpServletRequest r){return Api.ok(service.privateView(guard.actor(),guard.id(id)),r);}
 @GetMapping({"/consumer/reviews","/admin/reviews","/merchant/reviews"}) Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,@RequestParam(required=false)String store_id,HttpServletRequest r){return paged(service.list(guard.actor(),cursor(cursor),limit,store_id==null?null:guard.id(store_id)),limit,r);}
 @PatchMapping("/consumer/reviews/{id}") Object update(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.update(guard.actor(),guard.id(id),b,match,key,r),r);}
 @PostMapping("/admin/reviews/{id}/moderation") Object moderate(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.moderate(guard.actor(),guard.id(id),b,match,key,proof,r),r);}
 @GetMapping({"/public/reviews/{id}/media/{asset}","/consumer/reviews/{id}/media/{asset}","/admin/reviews/{id}/media/{asset}"}) Object media(@PathVariable String id,@PathVariable String asset,HttpServletRequest r){return PublishingMedia.response(service.content(r.getRequestURI().startsWith("/api/v1/public/")?null:guard.actor(),guard.id(id),guard.id(asset)));}
 @GetMapping("/admin/review-reward-policies") Object policies(HttpServletRequest r){return Api.list(service.policies(guard.actor()),r);}
 @PostMapping("/admin/review-reward-policies") Object policy(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.createPolicy(guard.actor(),b,key,proof,r),r);}
}
