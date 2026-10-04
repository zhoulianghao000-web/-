package cn.pawday.identity;

import cn.pawday.common.Api;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;

@RestController
@RequestMapping("/api/v1/merchant/stores")
public class ScopeController {
    private final JdbcTemplate db; private final AccessGuard guard;
    public ScopeController(JdbcTemplate db,AccessGuard guard){this.db=db;this.guard=guard;}
    @GetMapping Object list(HttpServletRequest r) {
        var actor=guard.require("store.read");
        return Api.list(db.queryForList("SELECT s.id,s.name,s.merchant_id FROM merchant_store s JOIN principal_store_scope p ON p.store_id=s.id AND p.merchant_id=s.merchant_id WHERE p.principal_id=? AND s.merchant_id=? ORDER BY s.id",actor.principalId(),actor.merchantId()),r);
    }
    @GetMapping("/{store_id}") Object get(@PathVariable String store_id,HttpServletRequest r) {
        var actor=guard.require("store.read");var id=guard.id(store_id);guard.store(actor,id);
        return Api.ok(db.queryForMap("SELECT id,name,merchant_id FROM merchant_store WHERE id=? AND merchant_id=?",id,actor.merchantId()),r);
    }
}
