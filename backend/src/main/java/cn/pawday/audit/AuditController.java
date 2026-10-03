package cn.pawday.audit;

import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;

@RestController
public class AuditController {
    private final JdbcTemplate db;private final AccessGuard guard;
    public AuditController(JdbcTemplate db,AccessGuard guard){this.db=db;this.guard=guard;}
    @GetMapping("/api/v1/admin/audit") Object audit(@RequestParam(defaultValue="20") int limit,HttpServletRequest r) {
        guard.require("audit.read");if(limit<1 || limit>100) throw new Api.Failure(400,"VALIDATION_ERROR");
        var rows=db.queryForList("SELECT id,actor_type,actor_id,action,object_type,object_id,before_json,after_json,request_id,correlation_id,created_at FROM audit_event ORDER BY created_at DESC,id DESC LIMIT ?",limit);
        var mapper=tools.jackson.databind.json.JsonMapper.builder().build();
        rows.forEach(row->{for(String key:java.util.List.of("before_json","after_json")){Object value=row.get(key);row.put(key,value==null?null:mapper.readTree(value.toString()));}});
        return Api.list(rows,r);
    }
}
