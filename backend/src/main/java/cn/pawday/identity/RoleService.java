package cn.pawday.identity;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

@Service
public class RoleService {
    public record Role(UUID id,String name,List<String> permission_codes,long version) {}
    private final JdbcTemplate db; private final TransactionTemplate tx;private final AuthService auth;
    private final AuditWriter audit;private final Crypto crypto;private final JsonMapper json=JsonMapper.builder().build();
    public RoleService(JdbcTemplate db,TransactionTemplate tx,AuthService auth,AuditWriter audit,Crypto crypto){this.db=db;this.tx=tx;this.auth=auth;this.audit=audit;this.crypto=crypto;}
    public List<Role> list() {return db.query("SELECT id,name,version FROM role WHERE scope_type='ADMIN' ORDER BY id",(row,i)->new Role(row.getObject("id",UUID.class),row.getString("name"),permissions(row.getObject("id",UUID.class)),row.getLong("version")));}
    private List<String> permissions(UUID id) {return db.queryForList("SELECT p.code FROM role_permission rp JOIN permission p ON p.id=rp.permission_id WHERE rp.role_id=? ORDER BY p.code",String.class,id);}
    public Role save(Actor actor,UUID id,String name,List<String> requested,Long expected,String proof,String key,HttpServletRequest r) {
        if(key==null || key.length()<16 || key.length()>128) throw new Failure(400,"IDEMPOTENCY_KEY_REQUIRED");
        List<String> codes=new ArrayList<>(new TreeSet<>(requested));
        if(codes.size()!=requested.size()) throw new Failure(400,"VALIDATION_ERROR");
        if(!actor.permissions().containsAll(codes)) throw new Failure(403,"PERMISSION_DENIED");
        String action=id==null?"role.create":"role.update:"+id;
        String hash=crypto.hash(json.writeValueAsString(Arrays.asList(id,name,codes,expected)));
        return tx.execute(s-> {
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",actor.principalId()+":"+action+":"+key);
            var prior=db.queryForList("SELECT payload_hash,result_json FROM identity_command WHERE principal_id=? AND action=? AND idempotency_key=?",actor.principalId(),action,key);
            if(!prior.isEmpty()) {
                if(!hash.equals(prior.getFirst().get("payload_hash"))) throw new Failure(409,"IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD");
                return json.readValue(prior.getFirst().get("result_json").toString(),Role.class);
            }
            auth.consumeProof(actor,"access.role.write",proof);
            Role before=null;long version=0;UUID roleId=id;
            if(roleId!=null) {
                var rows=db.queryForList("SELECT id,name,version FROM role WHERE id=? AND scope_type='ADMIN' FOR UPDATE",roleId);
                if(rows.isEmpty()) throw new Failure(404,"RESOURCE_NOT_FOUND");var row=rows.getFirst();version=((Number)row.get("version")).longValue();
                if(expected==null || expected!=version) throw new Failure(409,"CONCURRENT_MODIFICATION");
                before=new Role(id,(String)row.get("name"),permissions(id),version);version++;
                db.update("UPDATE role SET name=?,version=? WHERE id=?",name,version,id);db.update("DELETE FROM role_permission WHERE role_id=?",id);
            } else {roleId=UUID.randomUUID();db.update("INSERT INTO role(id,scope_type,code,name) VALUES (?,'ADMIN',?,?)",roleId,"custom_"+roleId,name);}
            for(String code:codes) {
                int changed=db.update("INSERT INTO role_permission(role_id,permission_id) SELECT ?,id FROM permission WHERE code=?",roleId,code);
                if(changed!=1) throw new Failure(422,"UNKNOWN_PERMISSION");
            }
            Role result=new Role(roleId,name,codes,version);
            audit.write(actor,"access.role.write","ROLE",roleId.toString(),before==null?Map.of():Map.of("name",before.name(),"permissions",before.permission_codes(),"version",before.version()),Map.of("name",name,"permissions",codes,"version",version),r);
            db.update("INSERT INTO identity_command(principal_id,action,idempotency_key,payload_hash,result_json) VALUES (?,?,?,?,?::jsonb)",actor.principalId(),action,key,hash,json.writeValueAsString(result));return result;
        });
    }
}
