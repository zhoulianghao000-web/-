package cn.pawday.nearby;

import cn.pawday.common.*;
import cn.pawday.common.Api.Failure;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.*;
import org.springframework.stereotype.Service;

@Service
public class NearbyService {
 private final PublishingSupport p;private final AccessGuard guard;private final IdempotentCommandExecutor commands;
 private final OutboxWriter outbox;private final AuditWriter audit;private final AuthService auth;private final NavigationProvider navigation;
 private static final Set<String> CATEGORIES=Set.of("PET_STORE","VET","GROOMING","BOARDING");
 private static final Set<String> SERVICES=Set.of("SUPPLIES","GROOMING","BOARDING","CONSULTATION","EMERGENCY","PET_FRIENDLY");
 private static final String SELECT="SELECT s.id,s.name,s.merchant_id,p.* FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id JOIN nearby_store_profile p ON p.store_id=s.id ";
 public NearbyService(PublishingSupport p,AccessGuard guard,IdempotentCommandExecutor commands,OutboxWriter outbox,AuditWriter audit,AuthService auth,NavigationProvider navigation){this.p=p;this.guard=guard;this.commands=commands;this.outbox=outbox;this.audit=audit;this.auth=auth;this.navigation=navigation;}
 static BigDecimal coordinate(Object raw,int max){try{if(!(raw instanceof Number n))throw new IllegalArgumentException();var v=new BigDecimal(n.toString());if(v.scale()>6||v.abs().compareTo(BigDecimal.valueOf(max))>0)throw new IllegalArgumentException();return v;}catch(Exception e){throw new Failure(400,"VALIDATION_ERROR");}}
 private Map<String,Object> view(Map<String,Object> row,boolean publicView){var v=p.view(row);v.remove("store_id");if(publicView)v.remove("merchant_id");v.put("services",p.json.readValue(row.get("services").toString(),List.class));return v;}
 private void owned(Actor a,UUID id,String permission){permission(a,Actor.Realm.MERCHANT,permission);guard.store(a,id);p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND s.merchant_id=? AND m.status='ACTIVE'",id,a.merchantId());}
 public Map<String,Object> profile(Actor a,UUID id){owned(a,id,"store.read");return view(p.one(SELECT+"WHERE s.id=?",id),false);}
 public Map<String,Object> adminDetail(Actor a,UUID id){permission(a,Actor.Realm.ADMIN,"nearby.read");return view(p.one(SELECT+"WHERE s.id=?",id),false);}
 public List<Map<String,Object>> adminList(Actor a,UUID after,int limit){permission(a,Actor.Realm.ADMIN,"nearby.read");limit(limit);return p.db.queryForList(SELECT+"WHERE s.id>? ORDER BY s.id LIMIT ?",after,limit+1).stream().map(row->view(row,false)).toList();}
 public Map<String,Object> save(Actor a,UUID sid,Map<String,Object>b,String match,String key,HttpServletRequest r){
  owned(a,sid,"store.nearby.write");fields(b,"city","category","address","phone","business_hours","longitude","latitude","coordinate_system","services");
  String city=text(b.get("city"),80),category=text(b.get("category"),16),address=text(b.get("address"),500),phone=text(b.get("phone"),32),hours=text(b.get("business_hours"),240);
  if(!CATEGORIES.contains(category)||!"WGS84".equals(b.get("coordinate_system"))||!phone.matches("[+0-9 ()-]{3,32}"))throw new Failure(400,"VALIDATION_ERROR");
  BigDecimal lon=coordinate(b.get("longitude"),180),lat=coordinate(b.get("latitude"),90);
  if(!(b.get("services") instanceof List<?> services)||services.size()>6||new HashSet<>(services).size()!=services.size()||!SERVICES.containsAll(services)||!category.equals("VET")&&(services.contains("CONSULTATION")||services.contains("EMERGENCY")))throw new Failure(400,"VALIDATION_ERROR");
  long expected=version(match);
  commands.command(a,"store.nearby.write:"+sid,key,Map.of("body",b,"version",expected),()->{
   p.one("SELECT id FROM merchant_store WHERE id=? FOR UPDATE",sid);owned(a,sid,"store.nearby.write");
   var rows=p.db.queryForList("SELECT version FROM nearby_store_profile WHERE store_id=?",sid);if(rows.isEmpty()){if(expected!=0)throw new Failure(409,"CONCURRENT_MODIFICATION");}else sameVersion(rows.getFirst(),expected);
   p.db.update("INSERT INTO nearby_store_profile(store_id,city,category,address,phone,business_hours,longitude,latitude,services,version) VALUES (?,?,?,?,?,?,?,?,?::jsonb,1) ON CONFLICT(store_id) DO UPDATE SET city=excluded.city,category=excluded.category,address=excluded.address,phone=excluded.phone,business_hours=excluded.business_hours,longitude=excluded.longitude,latitude=excluded.latitude,services=excluded.services,publication_status='DRAFT',claim_status='UNREVIEWED',pawday_certified=false,version=nearby_store_profile.version+1,updated_at=clock_timestamp()",sid,city,category,address,phone,hours,lon,lat,p.json.writeValueAsString(services));
   audit.write(a,"store.nearby.write","STORE",sid.toString(),Map.of("version",expected),Map.of("version",expected+1,"publication_status","DRAFT"),r);outbox.append("STORE",sid.toString(),"NearbyStoreChanged",1,Map.of("store_id",sid.toString(),"version",expected+1),correlation(r));return Map.of("id",sid.toString());
  });return profile(a,sid);
 }
 public Map<String,Object> moderate(Actor a,UUID sid,Map<String,Object>b,String match,String key,String proof,HttpServletRequest r){
  permission(a,Actor.Realm.ADMIN,"nearby.moderate");permission(a,Actor.Realm.ADMIN,"nearby.read");fields(b,"publication_status","claim_status","pawday_certified","reason");String status=text(b.get("publication_status"),16),claim=text(b.get("claim_status"),16),reason=text(b.get("reason"),500);boolean certified=bool(b.get("pawday_certified"));long expected=version(match);
  if(!Set.of("PUBLISHED","HIDDEN").contains(status)||!Set.of("VERIFIED","REJECTED").contains(claim)||(certified||status.equals("PUBLISHED"))&&!claim.equals("VERIFIED"))throw new Failure(400,"VALIDATION_ERROR");
  commands.command(a,"nearby.moderate:"+sid,key,Map.of("body",b,"version",expected),()->{
   p.one("SELECT id FROM merchant_store WHERE id=? FOR UPDATE",sid);var row=p.one(SELECT+"WHERE s.id=? FOR UPDATE OF p",sid);sameVersion(row,expected);
   if(status.equals("PUBLISHED")&&!"ACTIVE".equals(p.one("SELECT status FROM merchant WHERE id=?",row.get("merchant_id")).get("status")))throw new Failure(409,"MERCHANT_UNAVAILABLE");
   auth.consumeProof(a,"nearby.moderate",proof);p.db.update("UPDATE nearby_store_profile SET publication_status=?,claim_status=?,pawday_certified=?,version=version+1,updated_at=clock_timestamp() WHERE store_id=?",status,claim,certified,sid);
   p.db.update("INSERT INTO nearby_moderation_history(id,store_id,principal_id,version,publication_status,claim_status,pawday_certified,reason) VALUES (?,?,?,?,?,?,?,?)",UUID.randomUUID(),sid,a.principalId(),expected+1,status,claim,certified,reason);
   audit.write(a,"nearby.moderate","STORE",sid.toString(),Map.of("version",expected),Map.of("version",expected+1,"publication_status",status,"claim_status",claim,"pawday_certified",certified,"reason",reason),r);outbox.append("STORE",sid.toString(),"NearbyStoreChanged",1,Map.of("store_id",sid.toString(),"version",expected+1),correlation(r));return Map.of("id",sid.toString());
  });return adminDetail(a,sid);
 }
 public Map<String,Object> place(UUID id){return view(p.one(SELECT+"WHERE s.id=? AND m.status='ACTIVE' AND p.publication_status='PUBLISHED'",id),true);}
 public List<Map<String,Object>> nearby(String city,String category,Double lon,Double lat,String system,int radius,int offset,int limit){
  limit(limit);if(offset<0||offset>10000||radius<100||radius>100000||category!=null&&!CATEGORIES.contains(category)||(lon==null)!=(lat==null))throw new Failure(400,"VALIDATION_ERROR");
  if(lon==null){if(city==null||city.isBlank()||city.length()>80||system!=null)throw new Failure(400,"CITY_OR_LOCATION_REQUIRED");}
  else{coordinate(lon,180);coordinate(lat,90);if(!"WGS84".equals(system))throw new Failure(400,"COORDINATE_SYSTEM_UNSUPPORTED");}
  if(city!=null&&(city.isBlank()||city.length()>80))throw new Failure(400,"VALIDATION_ERROR");
  // All inputs are parameters. SQL filters/orders/limits before materializing; no table scan into JVM.
  String distance=lon==null?"NULL::double precision":"6371000*2*asin(sqrt(least(1.0,power(sin(radians(p.latitude-?)/2),2)+cos(radians(?))*cos(radians(p.latitude))*power(sin(radians(p.longitude-?)/2),2))))";
  var args=new ArrayList<Object>();if(lon!=null){args.add(lat);args.add(lat);args.add(lon);}
  String sql="WITH visible AS ("+SELECT.replace("p.*","p.*, "+distance+" AS distance_m")+"WHERE m.status='ACTIVE' AND p.publication_status='PUBLISHED'";
  if(city!=null){sql+=" AND p.city=?";args.add(city);}if(category!=null){sql+=" AND p.category=?";args.add(category);}sql+=") SELECT * FROM visible";
  if(lon!=null){sql+=" WHERE distance_m<=?";args.add(radius);}sql+=lon==null?" ORDER BY id":" ORDER BY distance_m,id";sql+=" LIMIT ? OFFSET ?";args.add(limit+1);args.add(offset);
  return p.db.queryForList(sql,args.toArray()).stream().map(row->{var v=view(row,true);if(lon!=null)v.put("distance_m",Math.round(((Number)row.get("distance_m")).doubleValue()));return v;}).toList();
 }
 public Map<String,Object> navigation(Map<String,Object>b){fields(b,"place_id","mode");return navigation.intent(place(id(b.get("place_id"))),text(b.get("mode"),16));}
 private static String correlation(HttpServletRequest r){return r==null?null:(String)r.getAttribute("correlation_id");}
}
