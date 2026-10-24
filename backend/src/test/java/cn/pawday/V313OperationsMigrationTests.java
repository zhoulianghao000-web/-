package cn.pawday;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.junit.jupiter.api.Assertions.*;

class V313OperationsMigrationTests {
 @Test void upgradeFromThirtyOneProjectsOnlyExistingConfirmedMoneyAndPreservesFreeIntents()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   var data=pg.getPostgresDatabase();Flyway.configure().dataSource(data).target("30").load().migrate();var db=new JdbcTemplate(data);
   UUID merchant=UUID.randomUUID(),store=UUID.randomUUID(),u=UUID.randomUUID(),other=UUID.randomUUID(),actor=UUID.randomUUID(),service=UUID.randomUUID(),slot=UUID.randomUUID(),terms=UUID.randomUUID();
   db.update("INSERT INTO merchant VALUES (?,'TEST_ONLY B2 upgrade','ACTIVE')",merchant);db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST_ONLY store')",store,merchant);
   db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE'),(?,'ACTIVE')",u,other);db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash) VALUES (?,'ADMIN',?,'TEST_ONLY')",actor,UUID.randomUUID().toString());
   db.update("INSERT INTO booking_services(id,store_id,title,kind,status) VALUES (?,?,'TEST_ONLY old service','GROOMING','ACTIVE')",service,store);
   db.update("INSERT INTO booking_slots(id,service_id,starts_at,ends_at,capacity) VALUES (?,?,now()+interval '1 day',now()+interval '1 day 1 hour',2)",slot,service);
   String snapshot="{\"amount_fen\":101,\"currency\":\"CNY\",\"cancel_cutoff_minutes\":60,\"commission_basis_points\":333,\"settlement_buffer_minutes\":120}";
   db.update("INSERT INTO service_trade_terms(id,service_id,store_id,snapshot,terms_sha256,policy_snapshot_sha256,state,version,created_by,created_at,reviewed_by,reviewed_at) VALUES (?,?,?,?::jsonb,?,?,'REVIEWED',1,?,now(),?,now())",terms,service,store,snapshot,"a".repeat(64),"b".repeat(64),actor,actor);
   var trades=new ArrayList<UUID>();for(UUID user:List.of(u,other)){
    UUID quote=UUID.randomUUID(),trade=UUID.randomUUID();trades.add(trade);
    db.update("INSERT INTO service_trade_quotes(id,terms_id,slot_id,service_id,store_id,user_id,terms_version,service_version,terms_sha256,policy_snapshot_sha256,payable_fen,created_at,expires_at) VALUES (?,?,?,?,?,?,1,0,?,?,101,now(),now()+interval '5 minutes')",quote,terms,slot,service,store,user,"a".repeat(64),"b".repeat(64));
    db.update("INSERT INTO service_trade_orders(id,quote_id,slot_id,service_id,store_id,terms_id,user_id,snapshot,terms_sha256,policy_snapshot_sha256,payable_fen,created_at,hold_expires_at) VALUES (?,?,?,?,?,?,?,?::jsonb,?,?,101,now(),now()+interval '10 minutes')",trade,quote,slot,service,store,terms,user,snapshot,"a".repeat(64),"b".repeat(64));
   }
   db.update("UPDATE service_trade_orders SET order_state='CANCELLED',payment_state='CLOSED',capacity_state='RELEASED',closed_at=now(),version=version+1 WHERE id=?",trades.get(1));
   UUID free=UUID.randomUUID();db.update("INSERT INTO service_bookings(id,slot_id,service_id,store_id,user_id,service_title) VALUES (?,?,?,?,?,'TEST_ONLY old free')",free,slot,service,store,other);
   UUID membership=UUID.randomUUID(),payment=UUID.randomUUID();
   db.update("INSERT INTO membership_orders(id,order_no,user_id,plan_id,plan_snapshot,amount_fen) VALUES (?,?,?,'3c9a1f2e-5b6d-4e7f-8a9b-000000000001','{}',1500)",membership,"M"+membership.toString().replace("-",""),u);
   db.update("INSERT INTO payments(id,payment_no,membership_order_id,amount_fen,currency,expires_at) VALUES (?,?,?,1500,'CNY',now()+interval '10 minutes')",payment,"P"+payment.toString().replace("-",""),membership);
   Flyway.configure().dataSource(data).target("31").load().migrate();
   UUID trade=trades.getFirst(),paid=db.queryForObject("SELECT id FROM payments WHERE service_trade_id=?",UUID.class,trade),attempt=UUID.randomUUID(),receipt=UUID.randomUUID(),event=UUID.randomUUID();
   new org.springframework.transaction.support.TransactionTemplate(new org.springframework.jdbc.datasource.DataSourceTransactionManager(data)).executeWithoutResult(status->{
    db.update("INSERT INTO payment_attempts(id,payment_id,attempt_no,channel,client_platform) VALUES (?,?,?,'SIMULATED_TEST','ANDROID')",attempt,paid,"SA"+attempt.toString().replace("-",""));
    db.update("UPDATE payments SET status='PROCESSING',version=version+1 WHERE id=?",paid);
    db.update("INSERT INTO payment_receipts(id,attempt_id,provider,channel_transaction_id,amount_fen,currency) VALUES (?,?,'SIMULATED_SIMULATED_TEST',?,101,'CNY')",receipt,attempt,"TEST-UPGRADE-"+receipt);
    db.update("UPDATE payment_attempts SET status='CHANNEL_SUCCEEDED',version=version+1 WHERE id=?",attempt);
    db.update("UPDATE payments SET status='SUCCEEDED',successful_attempt_id=?,successful_receipt_id=?,paid_at=now(),version=version+1 WHERE id=?",attempt,receipt,paid);
    db.update("UPDATE service_trade_orders SET order_state='CONFIRMED',payment_state='SUCCEEDED',capacity_state='CONFIRMED',receipt_id=?,confirmed_at=now(),version=version+1 WHERE id=?",receipt,trade);
    db.update("INSERT INTO service_trade_money_events VALUES (?,?,?,?,NULL,'SERVICE_COLLECTION',101,'CNY',now())",event,trade,paid,receipt);
   });
   assertEquals(31,db.queryForObject("SELECT count(*) FROM flyway_schema_history WHERE success",Integer.class));
   Flyway.configure().dataSource(data).load().migrate();
   assertEquals(35,db.queryForObject("SELECT count(*) FROM flyway_schema_history WHERE success",Integer.class));
   assertEquals(1,db.queryForObject("SELECT count(*) FROM service_trade_allocations",Integer.class));
   assertEquals(3,db.queryForObject("SELECT commission_fen FROM service_trade_allocations WHERE trade_id=?",Long.class,trade));
   assertEquals(98,db.queryForObject("SELECT service_trade_balance(?)",Long.class,trade));
   assertEquals(2,db.queryForObject("SELECT count(*) FROM service_trade_ledger_entries",Integer.class));
   assertEquals(1,db.queryForObject("SELECT count(*) FROM service_trade_money_events",Integer.class));
   assertEquals("NOT_STARTED",db.queryForObject("SELECT fulfillment_state FROM service_trade_orders WHERE id=?",String.class,trade));
   assertEquals("NOT_PAYABLE",db.queryForObject("SELECT service_trade_settlement_state(?,now())",String.class,trades.getLast()));
   assertEquals("BOOKED",db.queryForObject("SELECT status FROM service_bookings WHERE id=?",String.class,free));
   assertEquals("PENDING",db.queryForObject("SELECT status FROM payments WHERE id=?",String.class,payment));
   for(String table:List.of("service_trade_fulfillment_events","service_trade_disputes","service_trade_dispute_decisions","service_trade_settlements"))assertEquals(0,db.queryForObject("SELECT count(*) FROM "+table,Integer.class));
  }
 }
}
