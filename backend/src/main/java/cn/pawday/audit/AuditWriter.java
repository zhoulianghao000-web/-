package cn.pawday.audit;

import cn.pawday.identity.Actor;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

@Component
public class AuditWriter {
    private static final Set<String> SENSITIVE_FIELDS=Set.of("password","passwordhash","accesstoken","refreshtoken","reverifytoken","uploadtoken","token","secret","deliverysecretciphertext","mfasecretciphertext","otp","otpcode","totp","totpcode","verificationcode","smscode","credential","credentials","authorization","cookie","signature","privatekey","identitycard","bankcard","address","shippingaddress");
    private final JdbcTemplate jdbc;
    private final JsonMapper json=JsonMapper.builder().build();
    public AuditWriter(JdbcTemplate jdbc) { this.jdbc=jdbc; }
    public Object redact(Object value) {
        if(value instanceof Map<?,?> map) {
            Map<String,Object> out=new LinkedHashMap<>();
            map.forEach((k,v)-> {
                String key=String.valueOf(k),normalized=key.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]","");
                if(SENSITIVE_FIELDS.contains(normalized)) out.put(key,"[REDACTED]");
                else if(normalized.contains("phone")) out.put(key,v==null?null:"***"+String.valueOf(v).substring(Math.max(0,String.valueOf(v).length()-4)));
                else out.put(key,redact(v));
            });return out;
        }
        if(value instanceof Collection<?> c) return c.stream().map(this::redact).toList();
        return value;
    }
    public void write(Actor actor,String action,String type,String id,Map<String,?> before,Map<String,?> after,HttpServletRequest r) {
        // Call sites submit selected business fields, never raw request bodies or credential DTOs.
        jdbc.update("""
            INSERT INTO audit_event(actor_type,actor_id,actor_role_snapshot,action,object_type,object_id,before_json,after_json,request_id,correlation_id,source_ip,session_id)
            VALUES (?,?,?::jsonb,?,?,?,?::jsonb,?::jsonb,?,?,?::inet,?)
            """,actor==null?"ANONYMOUS":actor.realm().name(),actor==null?null:actor.principalId().toString(),
            json.writeValueAsString(actor==null?List.of():actor.roleCodes()),action,type,id,
            json.writeValueAsString(redact(before)),json.writeValueAsString(redact(after)),
            r==null?null:r.getAttribute("request_id"),r==null?null:r.getAttribute("correlation_id"),maskedIp(r),actor==null?null:actor.sessionId());
    }
    private String maskedIp(HttpServletRequest r) {
        if(r==null) return null;
        try {byte[] bytes=java.net.InetAddress.getByName(r.getRemoteAddr()).getAddress();
            java.util.Arrays.fill(bytes,bytes.length==4?3:8,bytes.length,(byte)0);return java.net.InetAddress.getByAddress(bytes).getHostAddress();
        }catch(Exception ignored){return null;}
    }
}
