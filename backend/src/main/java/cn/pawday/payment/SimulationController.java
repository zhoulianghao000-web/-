package cn.pawday.payment;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.*;
@org.springframework.context.annotation.Profile("!production")
@RestController @ConditionalOnProperty(name="pawday.payment.simulation-enabled",havingValue="true")
@RequestMapping("/api/v1/consumer/payments") public class SimulationController {
 private final PaymentService service;private final AccessGuard guard;
 public SimulationController(PaymentService service,AccessGuard guard){this.service=service;this.guard=guard;}
 @PostMapping("/{id}/simulation")Object simulate(@PathVariable String id,@RequestBody java.util.Map<String,Object>b,HttpServletRequest r){return Api.ok(service.simulate(guard.actor(),guard.id(id),b),r);}
}
