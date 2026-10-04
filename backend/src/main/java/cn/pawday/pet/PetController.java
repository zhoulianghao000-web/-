package cn.pawday.pet;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/consumer/pets")
public class PetController {
 private final PetService pets;private final AccessGuard guard;
 public PetController(PetService pets,AccessGuard guard){this.pets=pets;this.guard=guard;}
 static long version(String match){try{if(match==null||!match.matches("\"[0-9]+\""))throw new IllegalArgumentException();return Long.parseLong(match.substring(1,match.length()-1));}catch(Exception e){throw new Api.Failure(400,"VERSION_REQUIRED");}}
 @GetMapping Object list(@RequestParam(required=false) String cursor,@RequestParam(defaultValue="50") int limit,HttpServletRequest r){var page=pets.list(guard.actor(),cursor,limit);return new Api.ListEnvelope<>(page.data(),new Api.Page(page.nextCursor(),page.hasMore()),Api.meta(r));}
 @GetMapping("/{pet_id}") Object get(@PathVariable String pet_id,HttpServletRequest r){return Api.ok(pets.get(guard.actor(),guard.id(pet_id)),r);}
 @PostMapping ResponseEntity<?> create(@RequestBody Map<String,Object> b,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){var result=pets.save(guard.actor(),null,null,b,key,r);return ResponseEntity.status(HttpStatus.CREATED).body(Api.ok(result,r));}
 @PatchMapping("/{pet_id}") Object patch(@PathVariable String pet_id,@RequestBody Map<String,Object> b,@RequestHeader(value="If-Match",required=false) String match,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(pets.save(guard.actor(),guard.id(pet_id),version(match),b,key,r),r);}
 @DeleteMapping("/{pet_id}") Object delete(@PathVariable String pet_id,@RequestHeader(value="If-Match",required=false) String match,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(pets.delete(guard.actor(),guard.id(pet_id),version(match),key,r),r);}
 @GetMapping("/{pet_id}/weight-records") Object weights(@PathVariable String pet_id,@RequestParam(required=false) String cursor,@RequestParam(defaultValue="50") int limit,HttpServletRequest r){var page=pets.weights(guard.actor(),guard.id(pet_id),cursor,limit);return new Api.ListEnvelope<>(page.data(),new Api.Page(page.nextCursor(),page.hasMore()),Api.meta(r));}
 @PostMapping("/{pet_id}/weight-records") ResponseEntity<?> weight(@PathVariable String pet_id,@RequestBody Map<String,Object> b,@RequestHeader(value="If-Match",required=false) String match,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return ResponseEntity.status(HttpStatus.CREATED).body(Api.ok(pets.weight(guard.actor(),guard.id(pet_id),version(match),b,key,r),r));}
}
