package cn.pawday.catalog;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1")
public class ConsumerCatalogController {
 private final ConsumerCatalogService catalog;private final AccessGuard guard;
 public ConsumerCatalogController(ConsumerCatalogService catalog,AccessGuard guard){this.catalog=catalog;this.guard=guard;}
 @GetMapping({"/public/spus/{id}","/consumer/spus/{id}"}) Object product(@PathVariable String id,HttpServletRequest r){return Api.ok(catalog.product(guard.id(id)),r);}
 @GetMapping({"/public/skus/{id}","/consumer/skus/{id}"}) Object sku(@PathVariable String id,HttpServletRequest r){return Api.ok(catalog.sku(guard.id(id)),r);}
 @GetMapping({"/public/skus/{id}/offers","/consumer/skus/{id}/offers"}) Object offers(@PathVariable String id,HttpServletRequest r){return Api.list(catalog.offers(guard.id(id)),r);}
 @GetMapping("/consumer/skus/{id}/fit") Object fit(@PathVariable String id,@RequestParam String pet_id,HttpServletRequest r){return Api.ok(catalog.fit(guard.actor(),guard.id(id),guard.id(pet_id)),r);}
 @PostMapping("/consumer/products/compare") Object compare(@RequestBody Map<String,Object> b,HttpServletRequest r){return Api.ok(catalog.compare(guard.actor(),b),r);}
}
