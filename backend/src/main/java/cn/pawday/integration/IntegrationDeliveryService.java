package cn.pawday.integration;

import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.audit.AuditWriter;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.pilot.PilotPolicy;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** Goods declaration and durable recovery. Collection, stock ACK and shipment are separate facts. */
@Service public class IntegrationDeliveryService {
 private final PublishingSupport p;private final IntegrationPolicy policy;private final PilotPolicy pilot;
 private final AccessGuard guard;private final AuthService auth;private final IdempotentCommandExecutor commands;
 private final AuditWriter audit;private final OutboxWriter outbox;private final TransactionTemplate tx;
 private final Clock clock;private final IntegrationOrderAdapter adapter;
 public IntegrationDeliveryService(PublishingSupport p,IntegrationPolicy policy,PilotPolicy pilot,AccessGuard guard,
 AuthService auth,IdempotentCommandExecutor commands,AuditWriter audit,OutboxWriter outbox,TransactionTemplate tx,
 Clock clock,IntegrationOrderAdapter adapter){this.p=p;this.policy=policy;this.pilot=pilot;this.guard=guard;this.auth=auth;this.commands=commands;this.audit=audit;this.outbox=outbox;this.tx=tx;this.clock=clock;this.adapter=adapter;}
 private Timestamp now(){return Timestamp.from(clock.instant());}
 private void staff(Actor a,UUID store,String permission){
  policy.requireEnabled();if(pilot.paused())throw new Failure(503,"PILOT_PAUSED");permission(a,Actor.Realm.MERCHANT,permission);
  if(p.db.queryForObject("SELECT count(*) FROM principal_role pr JOIN role_permission rp ON rp.role_id=pr.role_id JOIN permission x ON x.id=rp.permission_id JOIN identity_principal i ON i.id=pr.principal_id JOIN auth_session s ON s.principal_id=i.id WHERE pr.principal_id=? AND pr.realm='MERCHANT' AND i.status='ACTIVE' AND s.id=? AND s.revoked_at IS NULL AND s.expires_at>? AND x.code=?",Integer.class,a.principalId(),a.sessionId(),now(),permission)==0)throw new Failure(403,"PERMISSION_DENIED");
  guard.store(a,store);p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND s.merchant_id=? AND m.status='ACTIVE'",store,a.merchantId());
 }
 private Map<String,Object> connection(UUID store,UUID conn){return p.one("SELECT * FROM integration_connections WHERE id=? AND store_id=?",conn,store);}
 private Map<String,Object> owned(UUID conn,UUID delivery){return p.one("SELECT * FROM integration_order_deliveries WHERE id=? AND connection_id=?",delivery,conn);}
 private Map<String,Object> view(UUID delivery){
  return p.view(p.one("SELECT id,connection_id,suborder_id,business_key,payload_sha256,state,attempt_count,state NOT IN ('ACCEPTED','REJECTED') AS responsibility_open,state<>'REJECTED' AS fulfillment_hold_open,version,true AS simulated FROM integration_order_deliveries WHERE id=?",delivery));
 }
 public List<Map<String,Object>> list(Actor a,UUID store,UUID conn,UUID after,int size){staff(a,store,"integration.read");connection(store,conn);limit(size);
  return p.db.queryForList("SELECT id FROM integration_order_deliveries WHERE connection_id=? AND id>? ORDER BY id LIMIT ?",conn,after,size+1).stream().map(r->view((UUID)r.get("id"))).toList();
 }
 /** Original business locks precede connections. Never call this while holding a mapping/stock lock. */
 private Map<String,Object> lock(UUID delivery){var seed=p.one("SELECT * FROM integration_order_deliveries WHERE id=?",delivery);
  p.one("SELECT id FROM orders WHERE id=? FOR UPDATE",seed.get("order_id"));p.one("SELECT id FROM suborders WHERE id=? FOR UPDATE",seed.get("suborder_id"));p.one("SELECT id FROM payments WHERE id=? FOR UPDATE",seed.get("payment_id"));
  p.one("SELECT id FROM integration_connections WHERE id=? FOR UPDATE",seed.get("connection_id"));
  return p.one("SELECT * FROM integration_order_deliveries WHERE id=? FOR UPDATE",delivery);
 }
 private boolean mayDispatch(UUID conn){return !pilot.paused()&&p.db.queryForObject("SELECT count(*) FROM integration_connections c JOIN merchant merchant ON merchant.id=c.merchant_id AND merchant.status='ACTIVE' JOIN identity_principal i ON i.id=c.created_by JOIN principal_store_scope s ON s.principal_id=i.id AND s.store_id=c.store_id AND s.merchant_id=c.merchant_id WHERE c.id=? AND c.state='ACTIVE' AND i.status='ACTIVE' AND EXISTS(SELECT 1 FROM principal_role pr JOIN role_permission rp ON rp.role_id=pr.role_id JOIN permission x ON x.id=rp.permission_id WHERE pr.principal_id=i.id AND pr.realm='MERCHANT' AND x.code='integration.manage')",Integer.class,conn)>0;}
 private void record(Actor a,String action,UUID delivery,HttpServletRequest request){audit.write(a,action,"ERP_WMS_ORDER_DELIVERY",delivery.toString(),Map.of(),Map.of("simulated",true),request);}
 /** No HTTP creation endpoint. Server scans actual paid goods and freezes each mapped connection's lines. */
 UUID declare(UUID sub,UUID conn){policy.requireEnabled();if(pilot.paused())throw new Failure(503,"PILOT_PAUSED");return tx.execute(status->{
  var seed=p.one("SELECT order_id FROM suborders WHERE id=?",sub);p.one("SELECT id FROM orders WHERE id=? FOR UPDATE",seed.get("order_id"));p.one("SELECT id FROM suborders WHERE id=? FOR UPDATE",sub);
  var payment=p.one("SELECT id FROM payments WHERE order_id=? FOR UPDATE",seed.get("order_id"));var c=p.one("SELECT * FROM integration_connections WHERE id=? FOR UPDATE",conn);
  var prior=p.db.queryForList("SELECT id FROM integration_order_deliveries WHERE suborder_id=? AND connection_id=?",sub,conn);if(!prior.isEmpty())return (UUID)prior.getFirst().get("id");
  if(!mayDispatch(conn))throw new Failure(409,"INTEGRATION_INACTIVE");
  p.db.queryForList("SELECT id FROM integration_mappings WHERE connection_id=? AND state='ACTIVE' ORDER BY id FOR UPDATE",conn);
  p.db.queryForList("SELECT f.id FROM offers f JOIN order_items i ON i.offer_id=f.id WHERE i.suborder_id=? ORDER BY f.id FOR UPDATE OF f",sub);
  p.db.queryForList("SELECT b.offer_id FROM inventory_balances b JOIN order_items i ON i.offer_id=b.offer_id WHERE i.suborder_id=? ORDER BY b.offer_id FOR UPDATE OF b",sub);
  p.db.queryForList("SELECT id FROM order_items WHERE suborder_id=? ORDER BY id FOR UPDATE",sub);
  var payload=p.one("SELECT integration_order_payload(?,?) AS payload",sub,conn).get("payload");if(payload==null)throw new Failure(409,"INTEGRATION_GOODS_NOT_ELIGIBLE");
  UUID delivery=UUID.randomUUID();String hash=p.db.queryForObject("SELECT encode(digest(?::jsonb::text,'sha256'),'hex')",String.class,payload.toString());
  p.db.update("INSERT INTO integration_order_deliveries(id,connection_id,order_id,suborder_id,payment_id,merchant_id,store_id,business_key,frozen_payload,payload_sha256,created_at,next_attempt_at) VALUES (?,?,?,?,?,?,?,?,?::jsonb,?,?,?)",delivery,conn,seed.get("order_id"),sub,payment.get("id"),c.get("merchant_id"),c.get("store_id"),"TEST_ONLY_ORDER_"+sub+"_"+conn,payload.toString(),hash,now(),now());
  record(null,"integration.delivery.declare",delivery,null);outbox.append("INTEGRATION",conn.toString(),"IntegrationOrderDeliveryDeclared",1,Map.of("delivery_id",delivery,"connection_id",conn),null);return delivery;
 });}
 public Map<String,Object> act(Actor a,UUID store,UUID conn,UUID delivery,boolean retry,Map<String,Object> body,String match,String key,String proof,HttpServletRequest request){
  String permission=retry?"integration.delivery.retry":"integration.delivery.requery";staff(a,store,permission);connection(store,conn);owned(conn,delivery);
  if(retry){fields(body,"reason_code");if(!"TEST_SCENARIO_RETRY".equals(body.get("reason_code")))throw new Failure(400,"VALIDATION_ERROR");}else fields(body);
  long expected=version(match);
  var held=commands.command(a,permission+":"+delivery,key,Map.of("body",body,"version",expected),()->{
   var d=lock(delivery);staff(a,store,permission);sameVersion(d,expected);
   if(retry)auth.consumeProof(a,permission,proof);
   UUID token=claim(d,retry?"RETRY":"REQUERY",a,request);return Map.of("token",token.toString());
  });
  drive(delivery,UUID.fromString(held.get("token").toString()),retry);
  staff(a,store,permission);return view(delivery);
 }
 private UUID claim(Map<String,Object> d,String action,Actor actor,HttpServletRequest request){UUID id=(UUID)d.get("id");
  if(Set.of("ACCEPTED","REJECTED","NEEDS_REVIEW").contains(d.get("state"))||number(d.get("attempt_count"))>=8)throw new Failure(409,"INTEGRATION_DELIVERY_NOT_RETRYABLE");
  if(d.get("lease_until") instanceof Timestamp until&&until.toInstant().isAfter(clock.instant()))throw new Failure(409,"INTEGRATION_DELIVERY_LEASE_HELD");
  UUID token=UUID.randomUUID();Timestamp created=now(),until=Timestamp.from(created.toInstant().plusSeconds(60));int count=(int)number(d.get("attempt_count"))+1;
  p.db.update("UPDATE integration_order_deliveries SET state='PROCESSING',attempt_count=?,lease_token=?,lease_until=?,version=version+1 WHERE id=?",count,token,until,id);
  p.db.update("INSERT INTO integration_delivery_attempts VALUES (?,?,?,?,?,?,?)",UUID.randomUUID(),id,count,token,action,created,until);
  record(actor,"integration.delivery."+action.toLowerCase(Locale.ROOT),id,request);return token;
 }
 /** Claim commits before the channel query. A restarted worker only receives the same identity. */
 void drive(UUID delivery,UUID token,boolean send){
  policy.requireEnabled();var rows=p.db.queryForList("SELECT * FROM integration_order_deliveries WHERE id=? AND state='PROCESSING' AND lease_token=? AND lease_until>?",delivery,token,now());if(rows.isEmpty())return;var d=rows.getFirst();
  var instruction=new IntegrationOrderAdapter.Instruction((UUID)d.get("connection_id"),(UUID)d.get("merchant_id"),d.get("business_key").toString(),d.get("payload_sha256").toString());
  IntegrationOrderAdapter.Observation observation;
  try{observation=adapter.query(instruction);
   if(send&&valid(instruction,observation)&&"NOT_CREATED".equals(observation.result())&&observation.noExternalOrder()){
    // Pause/revocation prevents NEW dispatch, but querying old responsibility remains permitted.
    boolean allowed=Boolean.TRUE.equals(tx.execute(s->{var current=lock(delivery);return token.equals(current.get("lease_token"))&&((Timestamp)current.get("lease_until")).toInstant().isAfter(clock.instant())&&mayDispatch(instruction.connection());}));
    if(allowed)observation=adapter.submit(instruction);
   }
  }catch(RuntimeException e){observation=new IntegrationOrderAdapter.Observation("UNKNOWN",instruction.connection(),instruction.merchant(),instruction.businessKey(),instruction.payloadSha256(),null,false);}
  settle(delivery,token,observation);
 }
 private boolean valid(IntegrationOrderAdapter.Instruction i,IntegrationOrderAdapter.Observation o){return o!=null&&i.connection().equals(o.connection())&&i.merchant().equals(o.merchant())&&i.businessKey().equals(o.businessKey())&&i.payloadSha256().equals(o.payloadSha256())&&Set.of("ACCEPTED","REJECTED","UNKNOWN","NOT_CREATED").contains(o.result())&&(o.reference()==null||o.reference().matches("TEST_ONLY_[A-Za-z0-9_.:-]{1,100}"))&&(!Set.of("ACCEPTED","REJECTED").contains(o.result())||o.reference()!=null)&&(!o.result().equals("REJECTED")||o.noExternalOrder())&&(!o.result().equals("ACCEPTED")||!o.noExternalOrder());}
 void settle(UUID delivery,UUID token,IntegrationOrderAdapter.Observation observation){tx.executeWithoutResult(status->{var d=lock(delivery);
  if(!token.equals(d.get("lease_token"))||!"PROCESSING".equals(d.get("state"))||!((Timestamp)d.get("lease_until")).toInstant().isAfter(clock.instant()))return;
  var i=new IntegrationOrderAdapter.Instruction((UUID)d.get("connection_id"),(UUID)d.get("merchant_id"),d.get("business_key").toString(),d.get("payload_sha256").toString());boolean matched=valid(i,observation);
  String result=matched?observation.result():"INVALID";boolean terminal=matched&&Set.of("ACCEPTED","REJECTED").contains(result);
  String state=terminal?result:!matched||number(d.get("attempt_count"))>=8?"NEEDS_REVIEW":"UNKNOWN";
  UUID attempt=(UUID)p.one("SELECT id FROM integration_delivery_attempts WHERE delivery_id=? AND lease_token=?",delivery,token).get("id");
  // Store a one-way observation digest, never raw untrusted response/PII.
  String digest=p.db.queryForObject("SELECT encode(digest(?,'sha256'),'hex')",String.class,p.json.writeValueAsString(observation));
  p.db.update("INSERT INTO integration_delivery_receipts VALUES (?,?,?,?,?,?,?,?,?)",UUID.randomUUID(),attempt,delivery,result,digest,matched,matched&&observation.noExternalOrder(),matched?observation.reference():null,now());
  p.db.update("UPDATE integration_order_deliveries SET state=?,lease_token=NULL,lease_until=NULL,next_attempt_at=?,version=version+1 WHERE id=?",state,Timestamp.from(clock.instant().plusSeconds(Math.min(300,5L<<Math.min(6,number(d.get("attempt_count")))))),delivery);
  record(null,"integration.delivery.result",delivery,null);outbox.append("INTEGRATION",d.get("connection_id").toString(),"IntegrationOrderDeliveryObserved",1,Map.of("delivery_id",delivery,"state",state,"simulated",true),null);
 });}
 int recover(){if(!policy.deliveryWorkerEnabled())return 0;int total=0;
  if(!pilot.paused())for(var row:p.db.queryForList("SELECT DISTINCT s.id,m.connection_id FROM suborders s JOIN order_items i ON i.suborder_id=s.id JOIN integration_mappings m ON m.offer_id=i.offer_id AND m.state='ACTIVE' JOIN integration_connections c ON c.id=m.connection_id AND c.state='ACTIVE' JOIN payments p ON p.order_id=s.order_id AND p.status='SUCCEEDED' WHERE s.fulfillment_status='PAID_WAITING_FULFILLMENT' AND NOT EXISTS(SELECT 1 FROM integration_order_deliveries d WHERE d.suborder_id=s.id AND d.connection_id=c.id) ORDER BY s.id,m.connection_id LIMIT 50")){
   try{declare((UUID)row.get("id"),(UUID)row.get("connection_id"));}catch(Failure e){if(e.status!=409&&e.status!=404)throw e;}
  }
  for(var row:p.db.queryForList("SELECT id FROM integration_order_deliveries WHERE state IN ('READY','UNKNOWN','PROCESSING') AND next_attempt_at<=? AND (lease_until IS NULL OR lease_until<=?) ORDER BY next_attempt_at,id LIMIT 50",now(),now())){
   UUID id=(UUID)row.get("id");try{UUID token=tx.execute(s->{var d=lock(id);
    if(Set.of("ACCEPTED","REJECTED","NEEDS_REVIEW").contains(d.get("state"))||((Timestamp)d.get("next_attempt_at")).toInstant().isAfter(clock.instant())||d.get("lease_until") instanceof Timestamp until&&until.toInstant().isAfter(clock.instant()))return null;
    if(number(d.get("attempt_count"))>=8){p.db.update("UPDATE integration_order_deliveries SET state='NEEDS_REVIEW',lease_token=NULL,lease_until=NULL,version=version+1 WHERE id=?",id);record(null,"integration.delivery.exhausted",id,null);return null;}
    return claim(d,"RETRY",null,null);
   });if(token!=null){drive(id,token,true);total++;}}
   catch(RuntimeException e){org.slf4j.LoggerFactory.getLogger(getClass()).warn("Synthetic order responsibility retained: {}",id);}
  }return total;
 }
}
