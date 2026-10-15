package cn.pawday.pet;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** Pet-specific grants. Commerce, private media and AI retain their original owner boundary. */
@Service
public class HouseholdService {
 private final JdbcTemplate db; private final TransactionTemplate tx; private final AuditWriter audit;
 private final IdempotentCommandExecutor commands; private final Crypto crypto; private final PetService pets;
 public HouseholdService(JdbcTemplate db,TransactionTemplate tx,AuditWriter audit,IdempotentCommandExecutor commands,Crypto crypto,PetService pets){this.db=db;this.tx=tx;this.audit=audit;this.commands=commands;this.crypto=crypto;this.pets=pets;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER||a.userId()==null)throw new Failure(403,"PERMISSION_DENIED");}
 private static void check(boolean valid){if(!valid)throw new Failure(400,"VALIDATION_ERROR");}
 private Map<String,Object> access(Actor a,UUID id,boolean owner,boolean write){
  consumer(a);var rows=db.queryForList("SELECT * FROM pets WHERE id=? AND status='ACTIVE' FOR UPDATE",id);
  if(rows.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var p=rows.getFirst();
  if(a.userId().equals(p.get("owner_user_id")))return p;
  if(owner)throw new Failure(404,"RESOURCE_NOT_FOUND");
  var grants=db.queryForList("SELECT role FROM pet_share_members WHERE pet_id=? AND user_id=? AND status='ACTIVE'",id,a.userId());
  if(grants.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");
  if(write&&!grants.getFirst().get("role").equals("CAREGIVER"))throw new Failure(403,"PERMISSION_DENIED");return p;
 }
 private List<Map<String,Object>> rows(String sql,Object...args){var list=db.queryForList(sql,args);for(var row:list)row.replaceAll((k,val)->val instanceof java.sql.Timestamp t?t.toInstant().toString():val);return list;}
 private String role(Actor a,Map<String,Object> p){return a.userId().equals(p.get("owner_user_id"))?"OWNER":db.queryForObject("SELECT role FROM pet_share_members WHERE pet_id=? AND user_id=? AND status='ACTIVE'",String.class,p.get("id"),a.userId());}
 private Map<String,Object> profile(Actor a,Map<String,Object> p){var out=new LinkedHashMap<>(pets.view(p));out.remove("photo_asset_id");out.put("share_role",role(a,p));return out;}
 public PetService.ResultPage list(Actor a,String cursor,int limit){consumer(a);check(limit>=1&&limit<=100);UUID after=cursor==null?new UUID(0,0):PetService.uuid(cursor);return tx.execute(s->{var ids=db.queryForList("SELECT p.id FROM pets p WHERE p.status='ACTIVE' AND p.id>? AND (p.owner_user_id=? OR EXISTS(SELECT 1 FROM pet_share_members m WHERE m.pet_id=p.id AND m.user_id=? AND m.status='ACTIVE')) ORDER BY p.id LIMIT ?",after,a.userId(),a.userId(),limit+1);boolean more=ids.size()>limit;var data=ids.stream().limit(limit).map(p->profile(a,access(a,(UUID)p.get("id"),false,false))).toList();return new PetService.ResultPage(data,more?data.getLast().get("id").toString():null,more);});}
 public Map<String,Object> overview(Actor a,UUID pet){return tx.execute(s->{var p=access(a,pet,false,false);boolean owner=a.userId().equals(p.get("owner_user_id"));return Map.of("pet",profile(a,p),"members",rows("SELECT user_id,role,status,version,joined_at,ended_at FROM pet_share_members WHERE pet_id=? AND (status='ACTIVE' OR ?) ORDER BY (status='ACTIVE') DESC,joined_at DESC LIMIT 100",pet,owner),"invites",owner?rows("SELECT id,role,CASE WHEN status='PENDING' AND expires_at<=clock_timestamp() THEN 'EXPIRED' ELSE status END AS status,expires_at,created_at FROM pet_share_invites WHERE pet_id=? ORDER BY created_at DESC LIMIT 50",pet):List.of(),"tasks",rows("SELECT id,title,due_on::text,status,created_by,completed_by,version,created_at,ended_at FROM pet_care_tasks WHERE pet_id=? ORDER BY created_at DESC,id DESC LIMIT 100",pet),"entries",rows("SELECT id,actor_user_id,kind,note,recorded_on::text,created_at FROM pet_care_entries WHERE pet_id=? ORDER BY created_at DESC,id DESC LIMIT 100",pet));});}
 private Map<String,Object> command(Actor a,UUID pet,boolean owner,boolean write,String action,String key,Object payload,Supplier<Map<String,Object>> work){
  // Authorization precedes cached idempotency results and is serialized with revoke/leave/delete.
  return tx.execute(s->{access(a,pet,owner,write);return commands.command(a,action+":"+pet,key,payload,work);});
 }
 private void log(Actor a,String action,UUID pet,Map<String,?> after,HttpServletRequest r){audit.write(a,"household."+action,"PET",pet.toString(),Map.of(),after,r);}
 public Map<String,Object> invite(Actor a,UUID pet,Map<String,Object> b,String key,HttpServletRequest r){
  check(b.keySet().equals(Set.of("role")));String role=PetService.text(b.get("role"),16);check(Set.of("VIEWER","CAREGIVER").contains(role));
  var stored=command(a,pet,true,false,"household.invite",key,b,()->{
   if(db.queryForObject("SELECT count(*) FROM pet_share_invites WHERE pet_id=? AND status='PENDING' AND expires_at>clock_timestamp()",Integer.class,pet)>=5)throw new Failure(409,"INVITE_LIMIT_REACHED");
   UUID id=UUID.randomUUID();String token=crypto.token();db.update("INSERT INTO pet_share_invites(id,pet_id,token_hash,role,created_by,expires_at) VALUES (?,?,?,?,?,clock_timestamp()+interval '24 hours')",id,pet,crypto.hash(token),role,a.userId());
   log(a,"invite",pet,Map.of("invite_id",id,"role",role),r);return Map.of("id",id,"role",role,"token_ciphertext",crypto.encrypt(token.getBytes(StandardCharsets.UTF_8)));
  });
  return tx.execute(s->{access(a,pet,true,false);var live=db.queryForList("SELECT expires_at FROM pet_share_invites WHERE id=? AND status='PENDING' AND expires_at>clock_timestamp()",UUID.fromString(stored.get("id").toString()));if(live.isEmpty())throw new Failure(409,"INVITE_UNAVAILABLE");return Map.of("id",stored.get("id"),"role",role,"expires_at",((java.sql.Timestamp)live.getFirst().get("expires_at")).toInstant().toString(),"invite_token",new String(crypto.decrypt(stored.get("token_ciphertext").toString()),StandardCharsets.UTF_8));});
 }
 public Map<String,Object> accept(Actor a,Map<String,Object> b,String key,HttpServletRequest r){
  consumer(a);check(b.keySet().equals(Set.of("invite_token")));String token=PetService.text(b.get("invite_token"),43);check(token.matches("[A-Za-z0-9_-]{43}"));String hash=crypto.hash(token);
  var found=db.queryForList("SELECT pet_id,id FROM pet_share_invites WHERE token_hash=?",hash);if(found.isEmpty())throw new Failure(404,"INVITE_UNAVAILABLE");UUID pet=(UUID)found.getFirst().get("pet_id"),id=(UUID)found.getFirst().get("id");
  return tx.execute(s->{consumer(a);var ps=db.queryForList("SELECT owner_user_id FROM pets WHERE id=? AND status='ACTIVE' FOR UPDATE",pet);if(ps.isEmpty())throw new Failure(404,"INVITE_UNAVAILABLE");if(a.userId().equals(ps.getFirst().get("owner_user_id")))throw new Failure(409,"OWNER_CANNOT_ACCEPT_INVITE");
   var inv=db.queryForList("SELECT *,expires_at>clock_timestamp() AS live FROM pet_share_invites WHERE id=? FOR UPDATE",id).getFirst();
   boolean accepted=a.userId().equals(inv.get("accepted_by"))&&"ACCEPTED".equals(inv.get("status"));
   if(accepted&&db.queryForObject("SELECT count(*) FROM pet_share_members WHERE pet_id=? AND user_id=? AND status='ACTIVE'",Integer.class,pet,a.userId())==0)throw new Failure(404,"INVITE_UNAVAILABLE");
   if(!accepted&&(!"PENDING".equals(inv.get("status"))||!Boolean.TRUE.equals(inv.get("live"))))throw new Failure(404,"INVITE_UNAVAILABLE");
   return commands.command(a,"household.accept:"+id,key,Map.of("token_hash",hash),()->{
    if(accepted)throw new Failure(409,"INVITE_ALREADY_ACCEPTED");
    if(db.queryForObject("SELECT count(*) FROM pet_share_members WHERE pet_id=? AND user_id=? AND status='ACTIVE'",Integer.class,pet,a.userId())>0)throw new Failure(409,"ALREADY_A_MEMBER");
    if(db.queryForObject("SELECT count(*) FROM pet_share_members WHERE pet_id=? AND status='ACTIVE'",Integer.class,pet)>=20)throw new Failure(409,"MEMBER_LIMIT_REACHED");
    db.update("INSERT INTO pet_share_members(pet_id,user_id,role,status) VALUES (?,?,?,'ACTIVE') ON CONFLICT(pet_id,user_id) DO UPDATE SET role=excluded.role,status='ACTIVE',version=pet_share_members.version+1,joined_at=clock_timestamp(),ended_at=NULL",pet,a.userId(),inv.get("role"));
    db.update("UPDATE pet_share_invites SET status='ACCEPTED',accepted_by=?,ended_at=clock_timestamp() WHERE id=?",a.userId(),id);log(a,"accept",pet,Map.of("invite_id",id,"user_id",a.userId(),"role",inv.get("role")),r);return Map.of("pet_id",pet,"role",inv.get("role"));
   });
  });
 }
 public Map<String,Object> revokeInvite(Actor a,UUID pet,UUID id,String key,HttpServletRequest r){return command(a,pet,true,false,"household.revoke-invite:"+id,key,id,()->{int count=db.update("UPDATE pet_share_invites SET status='REVOKED',ended_at=clock_timestamp() WHERE id=? AND pet_id=? AND status='PENDING'",id,pet);if(count==0)throw new Failure(409,"INVITE_UNAVAILABLE");log(a,"revoke-invite",pet,Map.of("invite_id",id),r);return Map.of("id",id,"status","REVOKED");});}
 public Map<String,Object> endMember(Actor a,UUID pet,UUID user,long version,String key,boolean leave,HttpServletRequest r){
  if(leave){consumer(a);user=a.userId();}UUID target=user;
  return command(a,pet,!leave,false,"household.end-member:"+target,key,version,()->{
   var m=db.queryForList("SELECT * FROM pet_share_members WHERE pet_id=? AND user_id=? AND status='ACTIVE'",pet,target);if(m.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");if(((Number)m.getFirst().get("version")).longValue()!=version)throw new Failure(409,"CONCURRENT_MODIFICATION");
   String state=leave?"LEFT":"REVOKED";db.update("UPDATE pet_share_members SET status=?,version=version+1,ended_at=clock_timestamp() WHERE pet_id=? AND user_id=?",state,pet,target);
   db.update("UPDATE pet_share_invites SET status='REVOKED',ended_at=clock_timestamp() WHERE pet_id=? AND status='PENDING'",pet);log(a,leave?"leave":"revoke-member",pet,Map.of("user_id",target,"version",version+1,"status",state),r);return Map.of("user_id",target,"version",version+1,"status",state);
  });
 }
 private LocalDate date(Object raw,boolean future){try{LocalDate day=LocalDate.parse(String.valueOf(raw));LocalDate today=db.queryForObject("SELECT (clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date",java.sql.Date.class).toLocalDate();check(!day.isBefore(today.minusYears(10))&&!day.isAfter(future?today.plusYears(1):today));return day;}catch(Failure f){throw f;}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 public Map<String,Object> task(Actor a,UUID pet,Map<String,Object>b,String key,HttpServletRequest r){check(b.keySet().equals(Set.of("title","due_on")));String title=PetService.text(b.get("title"),160);LocalDate due=date(b.get("due_on"),true);return command(a,pet,false,true,"household.task",key,b,()->{UUID id=UUID.randomUUID();db.update("INSERT INTO pet_care_tasks(id,pet_id,title,due_on,created_by) VALUES (?,?,?,?,?)",id,pet,title,due,a.userId());log(a,"task-create",pet,Map.of("task_id",id),r);return Map.of("id",id,"version",0,"status","OPEN");});}
 public Map<String,Object> finish(Actor a,UUID pet,UUID id,long version,Map<String,Object>b,String key,HttpServletRequest r){check(b.keySet().equals(Set.of("status")));String status=PetService.text(b.get("status"),16);check(Set.of("DONE","CANCELLED").contains(status));return command(a,pet,false,true,"household.finish:"+id,key,Arrays.asList(version,b),()->{var ts=db.queryForList("SELECT * FROM pet_care_tasks WHERE id=? AND pet_id=?",id,pet);if(ts.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");var t=ts.getFirst();if(((Number)t.get("version")).longValue()!=version)throw new Failure(409,"CONCURRENT_MODIFICATION");if(!"OPEN".equals(t.get("status")))throw new Failure(409,"TASK_CLOSED");if(status.equals("CANCELLED")&&!a.userId().equals(t.get("created_by"))&&!a.userId().equals(access(a,pet,false,true).get("owner_user_id")))throw new Failure(403,"PERMISSION_DENIED");db.update("UPDATE pet_care_tasks SET status=?,completed_by=?,version=version+1,ended_at=clock_timestamp() WHERE id=?",status,status.equals("DONE")?a.userId():null,id);log(a,"task-"+status.toLowerCase(Locale.ROOT),pet,Map.of("task_id",id,"version",version+1),r);return Map.of("id",id,"version",version+1,"status",status);});}
 public Map<String,Object> entry(Actor a,UUID pet,Map<String,Object>b,String key,HttpServletRequest r){check(b.keySet().equals(Set.of("kind","note","recorded_on")));String kind=PetService.text(b.get("kind"),16),note=PetService.text(b.get("note"),2000);check(Set.of("FEEDING","WALK","GROOMING","NOTE").contains(kind));LocalDate day=date(b.get("recorded_on"),false);return command(a,pet,false,true,"household.entry",key,b,()->{UUID id=UUID.randomUUID();db.update("INSERT INTO pet_care_entries(id,pet_id,actor_user_id,kind,note,recorded_on) VALUES (?,?,?,?,?,?)",id,pet,a.userId(),kind,note,day);log(a,"entry",pet,Map.of("entry_id",id,"kind",kind),r);return Map.of("id",id,"actor_user_id",a.userId(),"kind",kind);});}
}
