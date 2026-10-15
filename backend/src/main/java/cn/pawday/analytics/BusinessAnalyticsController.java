package cn.pawday.analytics;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDate;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class BusinessAnalyticsController {
    private final BusinessAnalyticsService service;
    private final AccessGuard guard;
    public BusinessAnalyticsController(BusinessAnalyticsService service, AccessGuard guard) { this.service=service; this.guard=guard; }
    @GetMapping("/merchant/business-analytics")
    Object merchant(@RequestParam LocalDate from, @RequestParam LocalDate to, @RequestParam(required=false) UUID store_id, HttpServletRequest r) {
        return Api.ok(service.read(guard.actor(),null,store_id,from,to),r);
    }
    @GetMapping("/admin/merchants/{id}/business-analytics")
    Object admin(@PathVariable UUID id, @RequestParam LocalDate from, @RequestParam LocalDate to, @RequestParam(required=false) UUID store_id, HttpServletRequest r) {
        return Api.ok(service.read(guard.actor(),id,store_id,from,to),r);
    }
}
