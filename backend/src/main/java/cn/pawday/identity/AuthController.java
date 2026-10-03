package cn.pawday.identity;

import cn.pawday.common.Api;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;

@RestController
@RequestMapping("/api/v1")
public class AuthController {
    public record CodeRequest(@NotBlank @Pattern(regexp="\\+[1-9][0-9]{6,14}") String phone_e164,@NotBlank @Pattern(regexp="LOGIN|REVERIFY") String purpose) {}
    public record PhoneLogin(@NotBlank @Pattern(regexp="\\+[1-9][0-9]{6,14}") String phone_e164,@NotBlank @Pattern(regexp="[0-9]{6}") String code,@NotBlank @Size(max=128) String device_id) {}
    public record StaffLogin(@NotBlank @Size(max=160) String login_name,@NotBlank @Size(max=200) String password,@Size(max=6) String totp_code,@NotBlank @Size(max=128) String device_id) {}
    public record Refresh(@NotBlank @Size(max=128) String refresh_token) {}
    public record Reverify(@NotBlank @Size(max=160) String action,@Size(max=200) String password,@Size(max=6) String otp_code,@Size(max=6) String totp_code) {}
    private final AuthService auth; private final AccessGuard guard; private final JdbcTemplate db;
    public AuthController(AuthService auth,AccessGuard guard,JdbcTemplate db){this.auth=auth;this.guard=guard;this.db=db;}
    private Actor.Realm realm(String realm) {return Actor.Realm.valueOf(realm.toUpperCase(Locale.ROOT));}
    private Actor optionalActor() {var a=SecurityContextHolder.getContext().getAuthentication();return a!=null && a.getPrincipal() instanceof Actor actor?actor:null;}
    @PostMapping("/consumer/auth/phone/request-code")
    Object code(@Valid @RequestBody CodeRequest body,HttpServletRequest r) {return Api.ok(auth.requestCode(body.phone_e164(),body.purpose(),optionalActor(),r),r);}
    @PostMapping("/consumer/auth/phone/verify")
    Object phone(@Valid @RequestBody PhoneLogin body,HttpServletRequest r) {return Api.ok(auth.consumerLogin(body.phone_e164(),body.code(),body.device_id(),r),r);}
    @PostMapping("/{realm:merchant|admin}/auth/login")
    Object staff(@PathVariable String realm,@Valid @RequestBody StaffLogin body,HttpServletRequest r) {return Api.ok(auth.staffLogin(realm(realm),body.login_name(),body.password(),body.totp_code(),body.device_id(),r),r);}
    @PostMapping("/{realm:consumer|merchant|admin}/auth/refresh")
    Object refresh(@PathVariable String realm,@Valid @RequestBody Refresh body,HttpServletRequest r) {return Api.ok(auth.refresh(realm(realm),body.refresh_token(),r),r);}
    @PostMapping("/{realm:consumer|merchant|admin}/auth/reverify")
    Object reverify(@PathVariable String realm,@Valid @RequestBody Reverify body,HttpServletRequest r) {return Api.ok(auth.reverify(guard.actor(),body.action(),body.password(),body.otp_code(),body.totp_code(),r),r);}
    @PostMapping("/{realm:consumer|merchant|admin}/auth/logout")
    Object logout(HttpServletRequest r) {var actor=guard.actor();auth.revoke(actor,actor.sessionId(),r);return Api.ok(new AuthService.Receipt(actor.sessionId(),0,java.time.Instant.now()),r);}
    @GetMapping("/{realm:consumer|merchant|admin}/me")
    Object me(HttpServletRequest r) {
        var actor=guard.actor();Map<String,Object> data=new LinkedHashMap<>();
        data.put("id",actor.principalId());data.put("realm",actor.realm());data.put("user_id",actor.userId());data.put("merchant_id",actor.merchantId());data.put("session_id",actor.sessionId());data.put("permissions",new TreeSet<>(actor.permissions()));return Api.ok(data,r);
    }
    @GetMapping("/{realm:consumer|merchant|admin}/auth/sessions")
    Object sessions(HttpServletRequest r) {
        var actor=guard.actor();var data=db.queryForList("SELECT id,device_id,created_at,expires_at,revoked_at FROM auth_session WHERE principal_id=? ORDER BY created_at DESC,id",actor.principalId());return Api.list(data,r);
    }
    @DeleteMapping("/{realm:consumer|merchant|admin}/auth/sessions/{session_id}")
    Object revoke(@PathVariable String session_id,HttpServletRequest r) {auth.revoke(guard.actor(),guard.id(session_id),r);return Api.ok(new AuthService.Receipt(guard.id(session_id),0,java.time.Instant.now()),r);}
    @PostMapping("/{realm:consumer|merchant|admin}/auth/sessions/revoke-others")
    Object others(@RequestHeader(value="X-Reverify-Token",required=false) String proof,HttpServletRequest r) {var actor=guard.actor();auth.revokeOthers(actor,proof,r);return Api.ok(new AuthService.Receipt(actor.sessionId(),0,java.time.Instant.now()),r);}
}
