package cn.pawday.ai;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.publishing.PublishingSupport;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class AiQuotaService {
 final PublishingSupport p;final TransactionTemplate tx;final Clock clock;
 public AiQuotaService(PublishingSupport p,TransactionTemplate tx,Clock clock){this.p=p;this.tx=tx;this.clock=clock;}
 Timestamp now(){return Timestamp.from(clock.instant());}
 static void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER||a.userId()==null)throw new Failure(403,"PERMISSION_DENIED");}
 void lock(UUID user){p.one("SELECT id FROM app_user WHERE id=? FOR UPDATE",user);}
 void active(Actor actor){if(p.db.queryForObject("SELECT count(*) FROM auth_session s JOIN identity_principal i ON i.id=s.principal_id JOIN app_user u ON u.id=i.user_id WHERE s.id=? AND i.id=? AND u.id=? AND s.revoked_at IS NULL AND s.expires_at>? AND i.status='ACTIVE' AND u.status='ACTIVE'",Integer.class,actor.sessionId(),actor.principalId(),actor.userId(),now())!=1)throw new Failure(401,"AUTH_REQUIRED");}
 void validateGrant(Map<String,Object> reservation){String bucket=reservation.get("quota_bucket_id").toString();if(bucket.startsWith("MEMBER:")&&grants((UUID)reservation.get("user_id")).stream().noneMatch(g->bucket.equals("MEMBER:"+g.get("membership_order_id"))))throw new Failure(409,"AI_CONTEXT_VERSION_CONFLICT");}
 Map<String,Object> preferences(UUID user){p.db.update("INSERT INTO ai_preferences(user_id) VALUES (?) ON CONFLICT DO NOTHING",user);return p.one("SELECT * FROM ai_preferences WHERE user_id=?",user);}
 Map<String,Object> policy(){return p.one("SELECT v.* FROM ai_policy_versions v JOIN ai_release r ON r.policy_id=v.id");}
 String freeBucket(){return "FREE:"+clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();}
 long used(UUID user,String bucket){return p.db.queryForObject("SELECT count(*) FROM ai_quota_reservations WHERE user_id=? AND quota_bucket_id=? AND (status='CONSUMED' OR status='RESERVED' AND lease_expires_at>?)",Long.class,user,bucket,now());}
 List<Map<String,Object>> grants(UUID user){return p.db.queryForList("SELECT g.* FROM ai_membership_quota_grants g JOIN membership_subscriptions s ON s.user_id=g.user_id WHERE g.user_id=? AND g.starts_at<=? AND g.expires_at>? AND s.status='ACTIVE' AND s.expires_at>? ORDER BY g.expires_at,g.membership_order_id",user,now(),now(),now());}
 long dailyUsed(UUID user){var day=clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate().atStartOfDay(ZoneId.of("Asia/Shanghai")).toInstant();return p.db.queryForObject("SELECT count(*) FROM ai_quota_reservations r JOIN ai_requests q ON q.id=r.id WHERE r.user_id=? AND q.created_at>=? AND (r.status='CONSUMED' OR r.status='RESERVED' AND r.lease_expires_at>?)",Long.class,user,Timestamp.from(day),now());}
 Map<String,Object> quotaLocked(UUID user,Map<String,Object> policy){long free=Math.max(0,((Number)policy.get("ordinary_daily_limit")).longValue()-used(user,freeBucket())),member=0;for(var g:grants(user))member+=Math.max(0,((Number)g.get("units")).longValue()-used(user,"MEMBER:"+g.get("membership_order_id")));member=Math.min(member,Math.max(0,((Number)policy.get("member_daily_ceiling")).longValue()-dailyUsed(user)));return Map.of("ordinary_remaining",free,"membership_remaining",member,"remaining",free+member,"policy_id",policy.get("id"),"ordinary_period","SHANGHAI_DAY","membership_period","PURCHASED_TERM","enabled",policy.get("enabled"));}
 public Map<String,Object> quota(Actor a){consumer(a);return tx.execute(s->{lock(a.userId());clean(a.userId());return quotaLocked(a.userId(),policy());});}
 void transition(UUID request,String state){var row=p.one("SELECT * FROM ai_quota_reservations WHERE id=? FOR UPDATE",request);if(!row.get("status").equals("RESERVED"))return;p.db.update("UPDATE ai_quota_reservations SET status=?,assistant_message_id=?,version=version+1 WHERE id=?",state,state.equals("CONSUMED")?request:null,request);p.db.update("INSERT INTO ai_quota_ledger VALUES (?,?,?, ?,1,?)",UUID.randomUUID(),request,row.get("user_id"),state,now());}
 void reserve(UUID request,UUID user,Map<String,Object> policy){String bucket=freeBucket();Instant end=clock.instant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDate().plusDays(1).atStartOfDay(ZoneId.of("Asia/Shanghai")).toInstant();
  if(used(user,bucket)>=((Number)policy.get("ordinary_daily_limit")).longValue()){
   if(dailyUsed(user)>=((Number)policy.get("member_daily_ceiling")).longValue())throw new Failure(429,"AI_QUOTA_EXHAUSTED");bucket=null;
   for(var g:grants(user)){String candidate="MEMBER:"+g.get("membership_order_id");if(used(user,candidate)<((Number)g.get("units")).longValue()){bucket=candidate;end=((Timestamp)g.get("expires_at")).toInstant();break;}}
   if(bucket==null)throw new Failure(429,"AI_QUOTA_EXHAUSTED");
  }
  Instant lease=clock.instant().plusSeconds(((Number)policy.get("lease_seconds")).intValue());if(lease.isAfter(end))lease=end;
  p.db.update("INSERT INTO ai_quota_reservations(id,user_id,quota_policy_version,quota_bucket_id,status,lease_expires_at) VALUES (?,?,?,?,'RESERVED',?)",request,user,policy.get("id"),bucket,Timestamp.from(lease));
  p.db.update("INSERT INTO ai_quota_ledger VALUES (?,?,?,'RESERVED',1,?)",UUID.randomUUID(),request,user,now());
 }
 void clean(UUID user){
  for(var r:p.db.queryForList("SELECT id FROM ai_quota_reservations WHERE user_id=? AND status='RESERVED' AND lease_expires_at<=? ORDER BY id",user,now()))transition((UUID)r.get("id"),"RELEASED");
  for(var c:p.db.queryForList("SELECT id FROM ai_conversations WHERE user_id=? AND status='ACTIVE' AND expires_at<=? ORDER BY id",user,now()))clear(user,(UUID)c.get("id"),"EXPIRED");
 }
 void clear(UUID user,UUID conversation,String status){
  var c=p.one("SELECT * FROM ai_conversations WHERE id=? AND user_id=? FOR UPDATE",conversation,user);p.db.update("UPDATE ai_conversations SET status=?,pet_id=NULL WHERE id=?",status,c.get("id"));
  for(var r:p.db.queryForList("SELECT q.id FROM ai_requests q JOIN ai_quota_reservations r ON r.id=q.id WHERE q.conversation_id=? AND r.status='RESERVED' ORDER BY q.id",conversation))transition((UUID)r.get("id"),"RELEASED");
  p.db.update("UPDATE ai_messages SET user_text_ciphertext=NULL,result_ciphertext=NULL WHERE conversation_id=?",conversation);
  p.db.update("UPDATE ai_profile_proposals SET status='EXPIRED',pet_id=NULL,before_value=NULL,proposed_value=NULL,version=version+1 WHERE request_id IN (SELECT id FROM ai_requests WHERE conversation_id=?) AND status<>'EXPIRED'",conversation);
 }
 public int sweep(){var users=p.db.queryForList("SELECT DISTINCT user_id FROM ai_quota_reservations WHERE status='RESERVED' AND lease_expires_at<=? UNION SELECT DISTINCT user_id FROM ai_conversations WHERE status='ACTIVE' AND expires_at<=? LIMIT 100",now(),now());for(var u:users)tx.executeWithoutResult(s->{lock((UUID)u.get("user_id"));clean((UUID)u.get("user_id"));});return users.size();}
}
