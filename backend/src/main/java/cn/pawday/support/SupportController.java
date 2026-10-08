package cn.pawday.support;
import cn.pawday.common.Api;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import cn.pawday.publishing.PublishingMedia;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1")
public class SupportController {
 private final SupportService service;private final NotificationService notifications;private final AccessGuard guard;private final AuthService auth;
 public SupportController(SupportService service,NotificationService notifications,AccessGuard guard,AuthService auth){this.service=service;this.notifications=notifications;this.guard=guard;this.auth=auth;}
 @GetMapping({"/consumer/conversations","/merchant/conversations","/admin/conversations"}) Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,@RequestParam(required=false)String store_id,HttpServletRequest r){return paged(service.list(guard.actor(),store_id==null?null:id(store_id),cursor(cursor),limit),limit,r);}
 @PostMapping("/consumer/conversations") Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.create(guard.actor(),b,key,r),r);}
 @GetMapping({"/consumer/conversations/{id}","/merchant/conversations/{id}","/admin/conversations/{id}"}) Object detail(@PathVariable String id,HttpServletRequest r){return Api.ok(service.detail(guard.actor(),id(id)),r);}
 @PostMapping({"/merchant/conversations/{id}/assignment","/admin/conversations/{id}/assignment"}) Object assign(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(service.assign(guard.actor(),id(id),b,match,key,proof,r),r);}
 @PostMapping({"/consumer/conversations/{id}/status","/merchant/conversations/{id}/status","/admin/conversations/{id}/status"}) Object status(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="If-Match",required=false)String match,HttpServletRequest r){return Api.ok(service.status(guard.actor(),id(id),b,match,key,r),r);}
 @PostMapping({"/consumer/conversations/{id}/messages","/merchant/conversations/{id}/messages","/admin/conversations/{id}/messages"}) Object send(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.send(guard.actor(),id(id),b,key,r),r);}
 @GetMapping({"/consumer/conversations/{id}/messages","/merchant/conversations/{id}/messages","/admin/conversations/{id}/messages"}) Object messages(@PathVariable String id,@RequestParam(defaultValue="0")long after_sequence,@RequestParam(defaultValue="50")int limit,@RequestParam(defaultValue="0")int wait_seconds,HttpServletRequest r){
  if(wait_seconds<0||wait_seconds>20)throw new Failure(400,"VALIDATION_ERROR");long until=System.nanoTime()+wait_seconds*1_000_000_000L;List<Map<String,Object>> rows;
  // No transaction/connection held while waiting. Re-check current session, permissions and assignment each tick.
  do{String header=r.getHeader("Authorization");Actor a=auth.load(header==null||!header.startsWith("Bearer ")?null:header.substring(7)).orElseThrow(()->new Failure(401,"AUTH_REQUIRED"));rows=service.messages(a,id(id),after_sequence,limit);if(!rows.isEmpty()||System.nanoTime()>=until)break;try{Thread.sleep(200);}catch(InterruptedException e){Thread.currentThread().interrupt();throw new Failure(503,"REQUEST_INTERRUPTED");}}while(true);
  boolean more=rows.size()>limit;var data=more?rows.subList(0,limit):rows;return new Api.ListEnvelope<>(data,new Api.Page(more?data.getLast().get("sequence").toString():null,more),Api.meta(r));
 }
 @PostMapping({"/consumer/conversations/{id}/read","/merchant/conversations/{id}/read","/admin/conversations/{id}/read"}) Object read(@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.read(guard.actor(),id(id),b,key),r);}
 @GetMapping({"/consumer/conversations/{id}/messages/{mid}/media/{asset}","/merchant/conversations/{id}/messages/{mid}/media/{asset}","/admin/conversations/{id}/messages/{mid}/media/{asset}"}) Object media(@PathVariable String id,@PathVariable String mid,@PathVariable String asset){return PublishingMedia.response(service.media(guard.actor(),id(id),id(mid),id(asset)));}
 @GetMapping({"/consumer/conversations/{id}/messages/{mid}/card","/merchant/conversations/{id}/messages/{mid}/card","/admin/conversations/{id}/messages/{mid}/card"}) Object card(@PathVariable String id,@PathVariable String mid,HttpServletRequest r){return Api.ok(service.card(guard.actor(),id(id),id(mid)),r);}
 @GetMapping("/consumer/messages") Object notifications(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,@RequestParam(required=false)String category,HttpServletRequest r){return paged(notifications.list(guard.actor(),cursor(cursor),limit,category),limit,r);}
 @GetMapping("/consumer/messages/unread") Object unread(HttpServletRequest r){return Api.ok(notifications.unread(guard.actor()),r);}
 @GetMapping("/consumer/messages/{id}/target") Object notificationTarget(@PathVariable String id,HttpServletRequest r){return Api.ok(notifications.target(guard.actor(),id(id)),r);}
 @PostMapping("/consumer/messages/{id}/read") Object notificationRead(@PathVariable String id,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(notifications.read(guard.actor(),id(id),key),r);}
 @GetMapping("/consumer/notification-preferences") Object preferences(HttpServletRequest r){return Api.list(notifications.preferences(guard.actor()),r);}
 @PutMapping("/consumer/notification-preferences/{category}") Object preference(@PathVariable String category,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(notifications.preference(guard.actor(),category,b,key),r);}
}
