package cn.pawday.booking;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.pilot.PilotPolicy;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

/** V3.1.1: synthetic slot reservation; no payment, refund, redemption or settlement authority. */
@Service
public class ServiceBookingService {
 private final PublishingSupport p;
 private final AccessGuard guard;
 private final IdempotentCommandExecutor commands;
 private final AuditWriter audit;
 private final Clock clock;
 private final PilotPolicy pilot;
 private final boolean enabled;
 public ServiceBookingService(PublishingSupport p,AccessGuard guard,IdempotentCommandExecutor commands,AuditWriter audit,Clock clock,PilotPolicy pilot,Environment env){
  this.p=p;this.guard=guard;this.commands=commands;this.audit=audit;this.clock=clock;this.pilot=pilot;
  enabled=env.getProperty("pawday.booking.simulation-enabled",Boolean.class,false)
   &&Set.of("development","test","pilot").contains(env.getProperty("pawday.deployment-mode","development"))
   &&Arrays.stream(env.getActiveProfiles()).noneMatch(Set.of("production","prod")::contains);
 }
 private void gate(){if(!enabled)throw new Failure(404,"BOOKING_SIMULATION_DISABLED");if(pilot.paused())throw new Failure(503,"PILOT_PAUSED");}
 private void consumer(Actor a){gate();if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 private void staff(Actor a,UUID store,boolean write){gate();permission(a,Actor.Realm.MERCHANT,write?"store.nearby.write":"store.read");guard.store(a,store);
  p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND s.merchant_id=? AND m.status='ACTIVE'",store,a.merchantId());
 }
 private void visible(UUID store){p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id JOIN nearby_store_profile n ON n.store_id=s.id WHERE s.id=? AND m.status='ACTIVE' AND n.publication_status='PUBLISHED' AND n.claim_status='VERIFIED' FOR SHARE OF m,n",store);}
 private Map<String,Object> view(Map<String,Object> row){var result=p.view(row);result.put("simulated",true);return result;}
 private Map<String,Object> service(UUID id){return p.one("SELECT * FROM booking_services WHERE id=?",id);}
 public List<Map<String,Object>> services(Actor a,UUID store,boolean merchant,UUID after,int limit){
  if(merchant)staff(a,store,false);else{consumer(a);visible(store);}limit(limit);
  return p.db.queryForList("SELECT * FROM booking_services WHERE store_id=? AND id>?"+(merchant?"":" AND status='ACTIVE'")+" ORDER BY id LIMIT ?",store,after,limit+1).stream().map(this::view).toList();
 }
 public Map<String,Object> create(Actor a,UUID store,Map<String,Object>b,String key,HttpServletRequest r){
  staff(a,store,true);fields(b,"title","kind");String title=text(b.get("title"),120).trim(),kind=text(b.get("kind"),16);
  if(!Set.of("GROOMING","BOARDING").contains(kind))throw new Failure(400,"VALIDATION_ERROR");
  return commands.command(a,"booking.service.create:"+store,key,b,()->{staff(a,store,true);UUID id=UUID.randomUUID();p.db.update("INSERT INTO booking_services(id,store_id,title,kind) VALUES (?,?,?,?)",id,store,title,kind);audit(a,"booking.service.create",id,r);return view(service(id));});
 }
 public Map<String,Object> state(Actor a,UUID id,Map<String,Object>b,String match,String key,HttpServletRequest r){
  gate();var s=service(id);UUID store=(UUID)s.get("store_id");staff(a,store,true);fields(b,"status");String status=text(b.get("status"),16);long v=version(match);
  if(!Set.of("ACTIVE","PAUSED").contains(status))throw new Failure(400,"VALIDATION_ERROR");
  return commands.command(a,"booking.service.state:"+id,key,Map.of("body",b,"version",v),()->{var row=p.one("SELECT * FROM booking_services WHERE id=? FOR UPDATE",id);staff(a,store,true);sameVersion(row,v);p.db.update("UPDATE booking_services SET status=?,version=version+1 WHERE id=?",status,id);audit(a,"booking.service.state",id,r);return view(service(id));});
 }
 private Instant instant(Object value){try{return Instant.parse(text(value,40));}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 public Map<String,Object> slot(Actor a,UUID service,Map<String,Object>b,String key,HttpServletRequest r){
  gate();var s=service(service);UUID store=(UUID)s.get("store_id");staff(a,store,true);fields(b,"starts_at","ends_at","capacity");Instant start=instant(b.get("starts_at")),end=instant(b.get("ends_at"));int capacity=integer(b.get("capacity"),1,100);
  return commands.command(a,"booking.slot.create:"+service,key,b,()->{
   p.one("SELECT id FROM booking_services WHERE id=? FOR UPDATE",service);staff(a,store,true);
   Instant now=clock.instant();if(!start.isAfter(now)||start.isAfter(now.plus(Duration.ofDays(90)))||!end.isAfter(start)||end.isAfter(start.plus(Duration.ofDays(7))))throw new Failure(400,"INVALID_BOOKING_INTERVAL");
   if(p.db.queryForObject("SELECT count(*) FROM booking_slots WHERE service_id=? AND starts_at<? AND ends_at>?",Integer.class,service,Timestamp.from(end),Timestamp.from(start))>0)throw new Failure(409,"BOOKING_SLOT_OVERLAP");
   UUID id=UUID.randomUUID();p.db.update("INSERT INTO booking_slots(id,service_id,starts_at,ends_at,capacity) VALUES (?,?,?,?,?)",id,service,Timestamp.from(start),Timestamp.from(end),capacity);audit(a,"booking.slot.create",id,r);return slotView(id);
  });
 }
 private static final String SLOTS="SELECT s.*,s.capacity-(SELECT count(*) FROM service_bookings b WHERE b.slot_id=s.id AND b.status='BOOKED') AS remaining FROM booking_slots s ";
 private Map<String,Object> slotView(UUID id){return view(p.one(SLOTS+"WHERE s.id=?",id));}
 public List<Map<String,Object>> slots(Actor a,UUID id,boolean merchant,UUID after,int limit){gate();var s=service(id);UUID store=(UUID)s.get("store_id");if(merchant)staff(a,store,false);else{consumer(a);visible(store);if(!s.get("status").equals("ACTIVE"))throw new Failure(404,"RESOURCE_NOT_FOUND");}limit(limit);
  return p.db.queryForList(SLOTS+"WHERE s.service_id=? AND s.starts_at>? AND s.id>? ORDER BY s.id LIMIT ?",id,Timestamp.from(clock.instant()),after,limit+1).stream().map(this::view).toList();
 }
 public Map<String,Object> book(Actor a,Map<String,Object>b,String key,HttpServletRequest r){consumer(a);fields(b,"slot_id");UUID slot=id(b.get("slot_id"));
  return commands.command(a,"booking.reserve",key,b,()->{
   // All capacity changes lock the same slot; no count/check race or denormalized counter drift.
   var row=p.one("SELECT * FROM booking_slots WHERE id=? FOR UPDATE",slot);var s=p.one("SELECT * FROM booking_services WHERE id=? FOR SHARE",row.get("service_id"));UUID store=(UUID)s.get("store_id");visible(store);
   if(!s.get("status").equals("ACTIVE")||!((Timestamp)row.get("starts_at")).toInstant().isAfter(clock.instant()))throw new Failure(409,"BOOKING_NOT_AVAILABLE");
   if(p.db.queryForObject("SELECT count(*) FROM service_bookings WHERE slot_id=? AND user_id=? AND status='BOOKED'",Integer.class,slot,a.userId())>0)throw new Failure(409,"BOOKING_ALREADY_EXISTS");
   if(p.db.queryForObject("SELECT count(*) FROM service_bookings WHERE slot_id=? AND status='BOOKED'",Integer.class,slot)>=number(row.get("capacity")))throw new Failure(409,"BOOKING_SLOT_FULL");
   UUID id=UUID.randomUUID();p.db.update("INSERT INTO service_bookings(id,slot_id,service_id,store_id,user_id,service_title) VALUES (?,?,?,?,?,?)",id,slot,s.get("id"),store,a.userId(),s.get("title"));audit(a,"booking.reserve",id,r);return bookingView(id);
  });
 }
 private static final String BOOKINGS="SELECT b.id,b.slot_id,b.service_id,b.store_id,b.service_title,b.policy,b.amount_fen,b.status,b.version,b.created_at,b.cancelled_at,s.starts_at,s.ends_at FROM service_bookings b JOIN booking_slots s ON s.id=b.slot_id ";
 private Map<String,Object> bookingView(UUID id){return view(p.one(BOOKINGS+"WHERE b.id=?",id));}
 public List<Map<String,Object>> bookings(Actor a,UUID store,UUID after,int limit){if(store==null)consumer(a);else staff(a,store,false);limit(limit);
  return p.db.queryForList(BOOKINGS+"WHERE "+(store==null?"b.user_id":"b.store_id")+"=? AND b.id>? ORDER BY b.id LIMIT ?",store==null?a.userId():store,after,limit+1).stream().map(this::view).toList();
 }
 public Map<String,Object> cancel(Actor a,UUID id,UUID store,String match,String key,HttpServletRequest r){if(store==null)consumer(a);else staff(a,store,true);long v=version(match);
  // Ownership is checked even on an idempotency replay; do not leak another user's booking.
  var original=p.one("SELECT slot_id FROM service_bookings WHERE id=? AND "+(store==null?"user_id":"store_id")+"=?",id,store==null?a.userId():store);
  return commands.command(a,"booking.cancel:"+id,key,Map.of("version",v),()->{
   p.one("SELECT id FROM booking_slots WHERE id=? FOR UPDATE",original.get("slot_id"));var row=p.one("SELECT * FROM service_bookings WHERE id=? FOR UPDATE",id);if(store!=null)staff(a,store,true);sameVersion(row,v);
   if(!row.get("status").equals("BOOKED"))throw new Failure(409,"BOOKING_ALREADY_CANCELLED");
   var slot=p.one("SELECT starts_at FROM booking_slots WHERE id=?",row.get("slot_id"));if(!((Timestamp)slot.get("starts_at")).toInstant().isAfter(clock.instant()))throw new Failure(409,"BOOKING_ALREADY_STARTED");
   p.db.update("UPDATE service_bookings SET status='CANCELLED',version=version+1,cancelled_at=?,cancelled_by=? WHERE id=?",Timestamp.from(clock.instant()),a.principalId(),id);audit(a,"booking.cancel",id,r);return bookingView(id);
  });
 }
 private void audit(Actor a,String action,UUID id,HttpServletRequest r){audit.write(a,action,"SIMULATED_BOOKING",id.toString(),Map.of(),Map.of("simulated",true,"policy","SIMULATION_NO_CHARGE_V1"),r);}
}
