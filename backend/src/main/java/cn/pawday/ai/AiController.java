package cn.pawday.ai;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1")
public class AiController {
 private final AiService ai;private final AiQuotaService quota;private final AiConfigService config;private final AccessGuard guard;
 public AiController(AiService ai,AiQuotaService quota,AiConfigService config,AccessGuard guard){this.ai=ai;this.quota=quota;this.config=config;this.guard=guard;}
 @GetMapping("/consumer/ai/preferences")Object preferences(HttpServletRequest r){return Api.ok(ai.preferences(guard.actor()),r);}
 @PutMapping("/consumer/ai/preferences")Object preferences(@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(ai.preference(guard.actor(),b,match,key,r),r);}
 @GetMapping("/consumer/ai/quota")Object quota(HttpServletRequest r){return Api.ok(quota.quota(guard.actor()),r);}
 @PostMapping("/consumer/ai/conversations")Object create(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(ai.create(guard.actor(),b,key),r);}
 @GetMapping("/consumer/ai/conversations")Object list(@RequestParam(required=false)String cursor,@RequestParam(defaultValue="50")int limit,HttpServletRequest r){return paged(ai.list(guard.actor(),cursor(cursor),limit),limit,r);}
 @GetMapping("/consumer/ai/conversations/{conversation_id}")Object detail(@PathVariable String conversation_id,HttpServletRequest r){return Api.ok(ai.detail(guard.actor(),id(conversation_id)),r);}
 @DeleteMapping("/consumer/ai/conversations/{conversation_id}")Object clear(@PathVariable String conversation_id,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(ai.clear(guard.actor(),id(conversation_id),key,r),r);}
 @PostMapping("/consumer/ai/conversations/{conversation_id}/messages")Object send(@PathVariable String conversation_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){return Api.ok(ai.send(guard.actor(),id(conversation_id),b,key),r);}
 @GetMapping("/consumer/ai/profile-proposals/{proposal_id}")Object proposal(@PathVariable String proposal_id,HttpServletRequest r){return Api.ok(ai.proposal(guard.actor(),id(proposal_id)),r);}
 @PostMapping("/consumer/ai/profile-proposals/{proposal_id}/{decision:accept|reject}")Object decide(@PathVariable String proposal_id,@PathVariable String decision,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,HttpServletRequest r){fields(b);return Api.ok(ai.decide(guard.actor(),id(proposal_id),decision.equals("accept"),match,key,r),r);}
 @GetMapping("/admin/ai/release")Object release(HttpServletRequest r){return Api.ok(config.release(guard.actor()),r);}
 @GetMapping("/admin/ai/rules")Object rules(HttpServletRequest r){return Api.ok(config.rules(guard.actor()),r);}
 @GetMapping("/admin/ai/prompts")Object prompts(HttpServletRequest r){return Api.list(config.prompts(guard.actor()),r);}
 @GetMapping("/admin/ai/policies")Object policies(HttpServletRequest r){return Api.list(config.policies(guard.actor()),r);}
 @GetMapping("/admin/ai/evaluations")Object evaluations(HttpServletRequest r){return Api.list(config.evaluations(guard.actor()),r);}
 @PostMapping("/admin/ai/prompts/versions")Object prompt(@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(config.prompt(guard.actor(),b,key,proof,r),r);}
 @PostMapping("/admin/ai/prompts/{version_id}/validate")Object validate(@PathVariable String version_id,@RequestBody Map<String,Object>b,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){fields(b);return Api.ok(config.validate(guard.actor(),id(version_id),key,proof,r),r);}
 @PostMapping("/admin/ai/prompts/{version_id}/{action:stage|activate|rollback}")Object publish(@PathVariable String version_id,@PathVariable String action,@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(config.publish(guard.actor(),id(version_id),action,b,match,key,proof,r),r);}
 @PostMapping("/admin/ai/policies/versions")Object policy(@RequestBody Map<String,Object>b,@RequestHeader(value="If-Match",required=false)String match,@RequestHeader(value="Idempotency-Key",required=false)String key,@RequestHeader(value="X-Reverify-Token",required=false)String proof,HttpServletRequest r){return Api.ok(config.policy(guard.actor(),b,match,key,proof,r),r);}
}
