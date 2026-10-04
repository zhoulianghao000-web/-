package cn.pawday.search;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/admin/operations/search")
@ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchController {
    public record Request(@NotBlank @Pattern(regexp="[A-Z0-9_]{4,80}") String reason_code){}
    private final SearchOperations operations;private final AccessGuard guard;
    public SearchController(SearchOperations operations,AccessGuard guard){this.operations=operations;this.guard=guard;}
    @GetMapping Object status(HttpServletRequest r){guard.require("search.read");return Api.ok(operations.status(),r);}
    @PostMapping("/rebuild") @ResponseStatus(HttpStatus.ACCEPTED) Object rebuild(@Valid @RequestBody Request body,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(operations.rebuild(guard.require("search.manage"),body.reason_code(),proof,key,r),r);}
    @PostMapping("/reconcile") @ResponseStatus(HttpStatus.ACCEPTED) Object reconcile(@Valid @RequestBody Request body,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(operations.reconcile(guard.require("search.manage"),body.reason_code(),proof,key,r),r);}
    @PostMapping("/retry") @ResponseStatus(HttpStatus.ACCEPTED) Object retry(@Valid @RequestBody Request body,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r){return Api.ok(operations.retry(guard.require("search.manage"),body.reason_code(),proof,key,r),r);}
}
