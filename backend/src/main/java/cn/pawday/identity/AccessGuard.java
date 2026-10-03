package cn.pawday.identity;

import cn.pawday.common.Api.Failure;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import java.util.UUID;

@Component
public class AccessGuard {
    private final JdbcTemplate jdbc;
    public AccessGuard(JdbcTemplate jdbc) {this.jdbc=jdbc;}
    public Actor actor() {
        var authentication=SecurityContextHolder.getContext().getAuthentication();
        if(authentication==null || !(authentication.getPrincipal() instanceof Actor actor)) throw new Failure(401,"AUTH_REQUIRED");
        return actor;
    }
    public Actor require(String permission) {
        var actor=actor();if(!actor.permissions().contains(permission)) throw new Failure(403,"PERMISSION_DENIED");return actor;
    }
    public UUID id(String raw) {
        try {return UUID.fromString(raw);}catch(IllegalArgumentException e){throw new Failure(404,"RESOURCE_NOT_FOUND");}
    }
    public void store(Actor actor,UUID storeId) {
        int count=jdbc.queryForObject("SELECT count(*) FROM principal_store_scope WHERE principal_id=? AND merchant_id=? AND store_id=?",Integer.class,actor.principalId(),actor.merchantId(),storeId);
        if(count==0) throw new Failure(404,"RESOURCE_NOT_FOUND");
    }
}
