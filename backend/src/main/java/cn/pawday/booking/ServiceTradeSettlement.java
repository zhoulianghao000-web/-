package cn.pawday.booking;

import cn.pawday.audit.AuditWriter;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.*;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.payment.ServiceTradeFinance;
import cn.pawday.publishing.PublishingSupport;
import cn.pawday.settlement.DevelopmentDisbursementPolicy;
import static cn.pawday.publishing.PublishingSupport.*;
import jakarta.servlet.http.HttpServletRequest;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/** Atomic database simulator. Its sources can never be consumed by goods settlement. */
@Service
public class ServiceTradeSettlement {
 private final PublishingSupport p;private final ServiceTradeFinance finance;private final TransactionTemplate tx;
 private final IdempotentCommandExecutor commands;private final AccessGuard guard;private final AuthService auth;
 private final Crypto crypto;private final AuditWriter audit;private final OutboxWriter outbox;private final Clock clock;
 private final DevelopmentDisbursementPolicy disbursement;
 public ServiceTradeSettlement(PublishingSupport p,ServiceTradeFinance finance,TransactionTemplate tx,IdempotentCommandExecutor commands,AccessGuard guard,AuthService auth,Crypto crypto,AuditWriter audit,OutboxWriter outbox,Clock clock,DevelopmentDisbursementPolicy disbursement){this.p=p;this.finance=finance;this.tx=tx;this.commands=commands;this.guard=guard;this.auth=auth;this.crypto=crypto;this.audit=audit;this.outbox=outbox;this.clock=clock;this.disbursement=disbursement;}
 private Timestamp now(){return Timestamp.from(clock.instant());}
 private void admin(Actor a,UUID merchant){finance.channelGate();permission(a,Actor.Realm.ADMIN,"service.trade.settle");p.one("SELECT id FROM merchant WHERE id=? AND status='ACTIVE'",merchant);}
 private void staff(Actor a,UUID store){finance.gate();permission(a,Actor.Realm.MERCHANT,"service.trade.ledger.read");guard.store(a,store);p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id WHERE s.id=? AND m.id=? AND m.status='ACTIVE'",store,a.merchantId());}
 public List<Map<String,Object>> ledger(Actor a,UUID store,UUID after,int size){staff(a,store);limit(size);return p.db.queryForList("SELECT e.id,e.trade_id,e.source_event_id,e.settlement_id,e.entry_type,e.direction,e.amount_fen,e.affects_balance,e.occurred_at,true AS simulated FROM service_trade_ledger_entries e JOIN service_trade_orders t ON t.id=e.trade_id WHERE t.store_id=? AND e.id>? ORDER BY e.id LIMIT ?",store,after,size+1).stream().map(p::view).toList();}
 /** All existing merchant slots first, then trades, payments, and financial facts in stable order. */
 private void lockBatch(UUID merchant){
  p.db.queryForList("SELECT s.id FROM booking_slots s JOIN booking_services b ON b.id=s.service_id JOIN merchant_store m ON m.id=b.store_id WHERE m.merchant_id=? ORDER BY s.id FOR UPDATE OF s",merchant);
  var rows=p.db.queryForList("SELECT t.id FROM service_trade_orders t JOIN merchant_store m ON m.id=t.store_id WHERE m.merchant_id=? ORDER BY t.id FOR UPDATE OF t",merchant);
  if(rows.size()>10000)throw new Failure(409,"SERVICE_SETTLEMENT_BATCH_LIMIT");
  p.db.queryForList("SELECT p.id FROM payments p JOIN service_trade_orders t ON t.id=p.service_trade_id JOIN merchant_store m ON m.id=t.store_id WHERE m.merchant_id=? ORDER BY p.id FOR UPDATE OF p",merchant);
 }
 private record Snapshot(Map<String,Object> value,String hash,long net,int count,List<String> reasons,List<Map<String,Object>> items){}
 private Snapshot snapshot(UUID merchant){
  var rows=p.db.queryForList("SELECT t.id,t.version,t.order_state,t.fulfillment_state,t.payment_state,t.policy_snapshot_sha256,a.policy_snapshot_sha256 AS allocation_policy,a.commission_fen,a.settlement_buffer_minutes,p.id AS payment_id,p.status AS payment_status,p.version AS payment_version,service_trade_open_dispute(t.id) AS open_dispute,service_trade_balance(t.id) AS balance_fen,(SELECT max(occurred_at) FROM service_trade_fulfillment_events WHERE trade_id=t.id AND status='COMPLETED') AS completed_at FROM service_trade_orders t JOIN merchant_store m ON m.id=t.store_id JOIN payments p ON p.service_trade_id=t.id LEFT JOIN service_trade_allocations a ON a.trade_id=t.id WHERE m.merchant_id=? ORDER BY t.id",merchant);
  var entries=p.db.queryForList("SELECT id,trade_id,source_event_id,settlement_id,entry_type,direction,amount_fen,affects_balance FROM service_trade_ledger_entries WHERE merchant_id=? ORDER BY id",merchant);
  if(entries.size()>10000)throw new Failure(409,"SERVICE_SETTLEMENT_BATCH_LIMIT");
  var refunds=p.db.queryForList("SELECT f.id,f.trade_id,f.state,f.version FROM service_trade_refunds f JOIN service_trade_orders t ON t.id=f.trade_id JOIN merchant_store m ON m.id=t.store_id WHERE m.merchant_id=? ORDER BY f.id",merchant);
  var attempts=p.db.queryForList("SELECT a.id,a.payment_id,a.status,a.version FROM payment_attempts a JOIN payments p ON p.id=a.payment_id JOIN service_trade_orders t ON t.id=p.service_trade_id JOIN merchant_store m ON m.id=t.store_id WHERE m.merchant_id=? ORDER BY a.id",merchant);
  var cases=p.db.queryForList("SELECT c.id,c.payment_id,c.status FROM payment_cases c JOIN payments p ON p.id=c.payment_id JOIN service_trade_orders t ON t.id=p.service_trade_id JOIN merchant_store m ON m.id=t.store_id WHERE m.merchant_id=? ORDER BY c.id",merchant);
  var reasons=new TreeSet<String>();var items=new ArrayList<Map<String,Object>>();long net=0;
  if(p.db.queryForObject("SELECT coalesce(sum(CASE direction WHEN 'CREDIT' THEN amount_fen ELSE -amount_fen END),0)<0 FROM merchant_finance_balance_sources WHERE merchant_id=? AND business_type='GOODS'",Boolean.class,merchant))reasons.add("CROSS_DOMAIN_DEBT");
  for(var row:rows){long balance=number(row.get("balance_fen"));if(balance==0)continue;UUID trade=(UUID)row.get("id"),payment=(UUID)row.get("payment_id");
   if(row.get("allocation_policy")==null||!Objects.equals(row.get("allocation_policy"),row.get("policy_snapshot_sha256")))reasons.add("TERMS_MISSING");
   if(Boolean.TRUE.equals(row.get("open_dispute")))reasons.add("OPEN_DISPUTE");
   if(refunds.stream().anyMatch(f->trade.equals(f.get("trade_id"))&&!"SUCCEEDED".equals(f.get("state"))))reasons.add("UNKNOWN_REFUND");
   if(attempts.stream().anyMatch(a->payment.equals(a.get("payment_id"))&&Set.of("CREATED","CHANNEL_PENDING","UNKNOWN").contains(a.get("status")))||cases.stream().anyMatch(c->payment.equals(c.get("payment_id"))&&!"REFUNDED".equals(c.get("status"))))reasons.add("UNKNOWN_PAYMENT");
   if(balance>0){
    if(!"CONFIRMED".equals(row.get("order_state"))||!"COMPLETED".equals(row.get("fulfillment_state"))||!"SUCCEEDED".equals(row.get("payment_status")))reasons.add("WAITING_COMPLETION");
    else if(row.get("completed_at")==null||row.get("settlement_buffer_minutes")==null)reasons.add("TERMS_MISSING");
    else if(clock.instant().isBefore(((Timestamp)row.get("completed_at")).toInstant().plusSeconds(number(row.get("settlement_buffer_minutes"))*60)))reasons.add("BUFFER_NOT_DUE");
   }
   net=Math.addExact(net,balance);items.add(Map.of("trade_id",trade.toString(),"net_fen",balance));
  }
  if(net<=0)reasons.add("NON_POSITIVE_BALANCE");if(net>1000000000L)throw new Failure(409,"SERVICE_SETTLEMENT_BATCH_LIMIT");
  var value=new TreeMap<String,Object>();value.put("trades",rows.stream().map(p::view).toList());value.put("ledger",entries.stream().map(p::view).toList());value.put("refunds",refunds.stream().map(p::view).toList());value.put("attempts",attempts.stream().map(p::view).toList());value.put("cases",cases.stream().map(p::view).toList());value.put("items",items);
  value.put("goods_balance_fen",p.db.queryForObject("SELECT coalesce(sum(CASE direction WHEN 'CREDIT' THEN amount_fen ELSE -amount_fen END),0) FROM merchant_finance_balance_sources WHERE merchant_id=? AND business_type='GOODS'",Long.class,merchant));
  return new Snapshot(value,crypto.hash(p.json.writeValueAsString(value)),Math.max(0,net),entries.size(),List.copyOf(reasons),items);
 }
 private Map<String,Object> previewView(UUID id){var v=p.one("SELECT id,merchant_id,net_fen,entry_count,ledger_sha256,expires_at,eligible,blocked_reasons,true AS simulated FROM service_trade_settlement_previews WHERE id=?",id);v.put("blocked_reasons",p.json.readValue(v.get("blocked_reasons").toString(),List.class));return p.view(v);}
 public Map<String,Object> preview(Actor a,UUID merchant,Map<String,Object>b,String key,HttpServletRequest request){admin(a,merchant);fields(b);return commands.command(a,"service.trade.settlement.preview:"+merchant,key,b,()->{admin(a,merchant);lockBatch(merchant);var snap=snapshot(merchant);UUID id=UUID.randomUUID();Timestamp createdAt=now();p.db.update("INSERT INTO service_trade_settlement_previews(id,merchant_id,snapshot,net_fen,ledger_sha256,eligible,blocked_reasons,entry_count,created_by,created_at,expires_at) VALUES (?,?,?::jsonb,?,?,?,?::jsonb,?,?,?,?)",id,merchant,p.json.writeValueAsString(snap.value()),snap.net(),snap.hash(),snap.reasons().isEmpty(),p.json.writeValueAsString(snap.reasons()),snap.count(),a.principalId(),createdAt,Timestamp.from(createdAt.toInstant().plusSeconds(300)));audit.write(a,"service.trade.settlement.preview","MERCHANT",merchant.toString(),Map.of(),Map.of("preview_id",id),request);return previewView(id);});}
 public Map<String,Object> settle(Actor a,UUID merchant,Map<String,Object>b,String key,String proof,HttpServletRequest request){
  admin(a,merchant);disbursement.requireEnabled();fields(b,"preview_id","accepted_ledger_sha256");UUID preview=id(b.get("preview_id"));String hash=text(b.get("accepted_ledger_sha256"),64);if(!hash.matches("[0-9a-f]{64}"))throw new Failure(400,"VALIDATION_ERROR");
  return commands.command(a,"service.trade.settlement.execute:"+merchant,key,b,()->{
   admin(a,merchant);disbursement.requireEnabled();lockBatch(merchant);var old=p.one("SELECT * FROM service_trade_settlement_previews WHERE id=? AND merchant_id=? AND created_by=? FOR UPDATE",preview,merchant,a.principalId());
   if(!((Timestamp)old.get("expires_at")).toInstant().isAfter(clock.instant()))throw new Failure(409,"SERVICE_SETTLEMENT_PREVIEW_EXPIRED");
   if(!p.db.queryForList("SELECT id FROM service_trade_settlements WHERE preview_id=?",preview).isEmpty())throw new Failure(409,"SERVICE_SETTLEMENT_PREVIEW_USED");
   var fresh=snapshot(merchant);if(!hash.equals(old.get("ledger_sha256"))||!hash.equals(fresh.hash()))throw new Failure(409,"SERVICE_SETTLEMENT_PREVIEW_STALE");
   if(!Boolean.TRUE.equals(old.get("eligible"))||!fresh.reasons().isEmpty()||fresh.net()!=number(old.get("net_fen")))throw new Failure(409,"SERVICE_SETTLEMENT_BLOCKED");
   auth.consumeProof(a,"service.trade.settle",proof);UUID id=UUID.randomUUID();p.db.update("INSERT INTO service_trade_settlements(id,preview_id,merchant_id,net_fen,state,channel_reference,ledger_sha256,created_by,settled_at) VALUES (?,?,?,?,'SETTLED',?,?,?,?)",id,preview,merchant,fresh.net(),"SIM-SERVICE-"+id,hash,a.principalId(),now());
   for(var item:fresh.items()){UUID trade=UUID.fromString(item.get("trade_id").toString());long amount=number(item.get("net_fen"));p.db.update("INSERT INTO service_trade_settlement_items VALUES (?,?,?)",id,trade,amount);p.db.update("INSERT INTO service_trade_ledger_entries VALUES (?,?,?,NULL,?,'SERVICE_SETTLEMENT',?,?,true,?)",UUID.randomUUID(),trade,merchant,id,amount>0?"DEBIT":"CREDIT",Math.abs(amount),now());}
   audit.write(a,"service.trade.settlement.execute","SERVICE_SETTLEMENT",id.toString(),Map.of(),Map.of("net_fen",fresh.net(),"simulated",true),request);outbox.append("SERVICE_SETTLEMENT",id.toString(),"ServiceSettlementCompleted",1,Map.of("settlement_id",id,"merchant_id",merchant,"net_fen",fresh.net(),"simulated",true),null);
   return p.view(p.one("SELECT id,merchant_id,net_fen,state,version,true AS simulated FROM service_trade_settlements WHERE id=?",id));
  });
 }
 public Map<String,Object> reconcile(Actor a,UUID merchant){admin(a,merchant);return tx.execute(s->{lockBatch(merchant);
  long goods=p.db.queryForObject("SELECT coalesce(sum(CASE direction WHEN 'CREDIT' THEN amount_fen ELSE -amount_fen END),0) FROM merchant_finance_balance_sources WHERE merchant_id=? AND business_type='GOODS'",Long.class,merchant);
  long service=p.db.queryForObject("SELECT coalesce(sum(CASE direction WHEN 'CREDIT' THEN amount_fen ELSE -amount_fen END),0) FROM merchant_finance_balance_sources WHERE merchant_id=? AND business_type='SERVICE_TRADE'",Long.class,merchant);
  var checks=new ArrayList<Map<String,Object>>();
  checks.add(check("collection_and_commission","SELECT count(*) FROM service_trade_allocations a WHERE a.merchant_id=? AND (a.paid_fen<>(SELECT coalesce(sum(amount_fen),0) FROM service_trade_ledger_entries WHERE trade_id=a.trade_id AND entry_type='SERVICE_COLLECTION') OR a.commission_fen<>(SELECT coalesce(sum(amount_fen),0) FROM service_trade_ledger_entries WHERE trade_id=a.trade_id AND entry_type='SERVICE_COMMISSION'))",merchant));
  checks.add(check("refund_and_cumulative_reversal","SELECT count(*) FROM service_trade_allocations a WHERE a.merchant_id=? AND ((SELECT coalesce(sum(amount_fen),0) FROM service_trade_money_events WHERE trade_id=a.trade_id AND entry_type='SERVICE_REFUND')<>(SELECT coalesce(sum(amount_fen),0) FROM service_trade_ledger_entries WHERE trade_id=a.trade_id AND entry_type='SERVICE_REFUND') OR round(a.commission_fen::numeric*least(a.paid_fen,(SELECT coalesce(sum(amount_fen),0) FROM service_trade_money_events WHERE trade_id=a.trade_id AND entry_type='SERVICE_REFUND'))/a.paid_fen)<>(SELECT coalesce(sum(amount_fen),0) FROM service_trade_ledger_entries WHERE trade_id=a.trade_id AND entry_type='SERVICE_COMMISSION_REVERSAL'))",merchant));
  checks.add(check("payout_conservation","SELECT count(*) FROM service_trade_settlements s WHERE s.merchant_id=? AND s.net_fen<>(SELECT coalesce(sum(CASE direction WHEN 'DEBIT' THEN amount_fen ELSE -amount_fen END),0) FROM service_trade_ledger_entries WHERE settlement_id=s.id)",merchant));
  checks.add(check("domain_owner_isolation","SELECT count(*) FROM merchant_ledger_entries e JOIN service_trade_ledger_entries x ON e.id=x.id WHERE e.merchant_id=?",merchant));
  return Map.of("merchant_id",merchant.toString(),"goods_balance_fen",goods,"service_balance_fen",service,"combined_balance_fen",Math.addExact(goods,service),"consistent",checks.stream().allMatch(c->number(c.get("mismatches"))==0),"checks",checks,"as_of",clock.instant().toString(),"simulated",true);
 });}
 private Map<String,Object> check(String name,String sql,UUID merchant){return Map.of("name",name,"mismatches",p.db.queryForObject(sql,Long.class,merchant));}
}
