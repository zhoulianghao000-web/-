package cn.pawday.care;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.Map;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/consumer/favorites")
public class FavoriteController {
 private final FavoriteService service;private final AccessGuard guard;
 public FavoriteController(FavoriteService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @GetMapping Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(service.list(guard.actor(),cursor(cursor),limit),limit,r);}
 @PostMapping Object save(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.save(guard.actor(),b,key,r),r);}
 @DeleteMapping("/{fid}") Object remove(@PathVariable String fid,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(service.remove(guard.actor(),id(fid),key,r),r);}
}
