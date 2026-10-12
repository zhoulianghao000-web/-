package cn.pawday.care;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/consumer/pets/{pet}/food")
public class PetFoodController {
 private final PetFoodService service;private final AccessGuard guard;
 public PetFoodController(PetFoodService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping Object get(@PathVariable String pet,HttpServletRequest r){return Api.ok(service.get(guard.actor(),id(pet)),r);}
 @GetMapping("/history") Object history(@PathVariable String pet,@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.history(guard.actor(),id(pet),cursor(cursor),limit),limit,r);}
 @PutMapping Object start(@PathVariable String pet,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.start(guard.actor(),id(pet),b,match,key,r),r);}
 @PostMapping("/calibrations") Object calibrate(@PathVariable String pet,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.calibrate(guard.actor(),id(pet),b,match,key,r),r);}
 @PostMapping("/stop") Object stop(@PathVariable String pet,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.stop(guard.actor(),id(pet),match,key,r),r);}
}
