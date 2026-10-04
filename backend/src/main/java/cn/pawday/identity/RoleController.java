package cn.pawday.identity;

import cn.pawday.common.Api;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.List;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/admin/access/roles")
public class RoleController {
    public record RoleRequest(@NotBlank @Size(max=160) String name,@NotNull @Size(max=100) List<@NotBlank @Size(max=160) String> permission_codes) {}
    private final RoleService roles;private final AccessGuard guard;
    public RoleController(RoleService roles,AccessGuard guard){this.roles=roles;this.guard=guard;}
    @GetMapping Object list(HttpServletRequest r) {guard.require("access.role.read");return Api.list(roles.list(),r);}
    @PostMapping @ResponseStatus(org.springframework.http.HttpStatus.CREATED)
    Object create(@Valid @RequestBody RoleRequest body,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,HttpServletRequest r) {
        var actor=guard.require("access.role.write");var role=roles.save(actor,null,body.name(),body.permission_codes(),null,proof,key,r);return org.springframework.http.ResponseEntity.created(java.net.URI.create("/api/v1/admin/access/roles/"+role.id())).body(Api.ok(role,r));
    }
    @PatchMapping("/{role_id}") Object update(@PathVariable String role_id,@Valid @RequestBody RoleRequest body,@RequestHeader(value="X-Reverify-Token",required=false) String proof,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestHeader(value="If-Match",required=false) String match,HttpServletRequest r) {
        Long version;
        try {if(match==null || !match.matches("\"[0-9]+\"")) throw new IllegalArgumentException();version=Long.parseLong(match.substring(1,match.length()-1));}catch(Exception e){throw new Api.Failure(400,"VERSION_REQUIRED");}
        var actor=guard.require("access.role.write");return Api.ok(roles.save(actor,guard.id(role_id),body.name(),body.permission_codes(),version,proof,key,r),r);
    }
}
