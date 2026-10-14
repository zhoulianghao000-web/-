package cn.pawday.pet;
import cn.pawday.common.Api;
import cn.pawday.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/consumer/household")
public class HouseholdController {
 private final HouseholdService service; private final AccessGuard guard; private final AuthService auth;
 public HouseholdController(HouseholdService service,AccessGuard guard,AuthService auth){this.service=service;this.guard=guard;this.auth=auth;}
 @GetMapping("/pets") Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){var p=service.list(guard.actor(),cursor,limit);return new Api.ListEnvelope<>(p.data(),new Api.Page(p.nextCursor(),p.hasMore()),Api.meta(r));}
 @GetMapping("/pets/{pet}") Object overview(@PathVariable String pet,HttpServletRequest r){return Api.ok(service.overview(guard.actor(),guard.id(pet)),r);}
 @PostMapping("/pets/{pet}/invites") @ResponseStatus(HttpStatus.CREATED) Object invite(@PathVariable String pet,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.invite(guard.actor(),guard.id(pet),b,key,r),r);}
 @PostMapping("/accept") Object accept(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){var a=guard.actor();auth.rateLimit("household-accept:"+a.principalId());return Api.ok(service.accept(a,b,key,r),r);}
 @PostMapping("/pets/{pet}/invites/{id}/revoke") Object revoke(@PathVariable String pet,@PathVariable String id,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.revokeInvite(guard.actor(),guard.id(pet),guard.id(id),key,r),r);}
 @PostMapping("/pets/{pet}/members/{user}/revoke") Object member(@PathVariable String pet,@PathVariable String user,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.endMember(guard.actor(),guard.id(pet),guard.id(user),PetController.version(match),key,false,r),r);}
 @PostMapping("/pets/{pet}/leave") Object leave(@PathVariable String pet,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.endMember(guard.actor(),guard.id(pet),null,PetController.version(match),key,true,r),r);}
 @PostMapping("/pets/{pet}/tasks") @ResponseStatus(HttpStatus.CREATED) Object task(@PathVariable String pet,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.task(guard.actor(),guard.id(pet),b,key,r),r);}
 @PostMapping("/pets/{pet}/tasks/{id}/finish") Object finish(@PathVariable String pet,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.finish(guard.actor(),guard.id(pet),guard.id(id),PetController.version(match),b,key,r),r);}
 @PostMapping("/pets/{pet}/entries") @ResponseStatus(HttpStatus.CREATED) Object entry(@PathVariable String pet,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.entry(guard.actor(),guard.id(pet),b,key,r),r);}
}
