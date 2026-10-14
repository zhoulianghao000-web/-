package cn.pawday.offer;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class PriceHistoryController {
 private final PriceHistoryService history;private final AccessGuard guard;
 public PriceHistoryController(PriceHistoryService history,AccessGuard guard){this.history=history;this.guard=guard;}
 @GetMapping({"/public/offers/{id}/price-history","/consumer/offers/{id}/price-history","/merchant/offers/{id}/price-history","/admin/offers/{id}/price-history"})
 Object get(@PathVariable String id,@RequestParam(defaultValue="30")int days,HttpServletRequest r){
  boolean staff=r.getRequestURI().contains("/merchant/")||r.getRequestURI().contains("/admin/");
  return Api.ok(history.history(guard.id(id),days,staff?guard.actor():null,r.getRequestURI().contains("/admin/")),r);
 }
}
