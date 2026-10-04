package cn.pawday.pet;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController
public class TaxonomyController {
 private final TaxonomyService taxonomy;private final AccessGuard guard;
 public TaxonomyController(TaxonomyService taxonomy,AccessGuard guard){this.taxonomy=taxonomy;this.guard=guard;}
 @GetMapping("/api/v1/public/pet-taxonomy") Object species(HttpServletRequest r){return Api.list(taxonomy.species(),r);}
 @GetMapping("/api/v1/public/pet-species/{species_id}/breeds") Object breeds(@PathVariable String species_id,HttpServletRequest r){return Api.list(taxonomy.breeds(guard.id(species_id)),r);}
 @GetMapping("/api/v1/public/allergens") Object allergens(HttpServletRequest r){return Api.list(taxonomy.allergens(),r);}
 @GetMapping("/api/v1/admin/pet-taxonomy") Object admin(HttpServletRequest r){guard.require("pet.taxonomy.read");return Api.list(taxonomy.species(),r);}
 @PostMapping("/api/v1/admin/pet-taxonomy/{type}") ResponseEntity<?> create(@PathVariable String type,@RequestBody Map<String,Object> b,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){var a=guard.require("pet.taxonomy.write");var result=type.equals("life-stage-rules")?taxonomy.publish(a,b,proof,key,r):taxonomy.create(a,type,b,proof,key,r);return ResponseEntity.status(HttpStatus.CREATED).body(Api.ok(result,r));}
 @PostMapping("/api/v1/admin/pet-taxonomy/{type}/{id}/retire") Object retire(@PathVariable String type,@PathVariable String id,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(taxonomy.retire(guard.require("pet.taxonomy.write"),type,guard.id(id),proof,key,r),r);}
}
