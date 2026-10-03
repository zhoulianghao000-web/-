package cn.pawday.outbox;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/admin/operations/outbox")
public class OutboxController {
    public record ReplayRequest(@NotNull @Min(0) Integer expected_generation,@NotBlank @Pattern(regexp="[A-Z0-9_]{4,80}") String reason_code) {}
    private final OutboxOperations operations;private final AccessGuard guard;
    public OutboxController(OutboxOperations operations,AccessGuard guard){this.operations=operations;this.guard=guard;}
    @GetMapping Object list(@RequestParam(defaultValue="20") int limit,HttpServletRequest r){guard.require("outbox.read");return Api.list(operations.list(limit),r);}
    @GetMapping("/stats") Object stats(HttpServletRequest r){guard.require("outbox.read");return Api.ok(operations.stats(),r);}
    @PostMapping("/{event_id}/replay") Object replay(@PathVariable String event_id,@Valid @RequestBody ReplayRequest body,
        @RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){var actor=guard.require("outbox.replay");return Api.ok(operations.replay(actor,guard.id(event_id),body.expected_generation(),body.reason_code(),proof,key,r),r);}
}
