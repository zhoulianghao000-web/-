package cn.pawday;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.junit.jupiter.api.Assertions.*;

class V313FinanceMigrationTests {
 @Test void upgradeFromThirtyBackfillsOnlyIntentsAndPreservesClosedTradesAndMembership()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   var data=pg.getPostgresDatabase();Flyway.configure().dataSource(data).target("30").load().migrate();var db=new JdbcTemplate(data);
   UUID merchant=UUID.randomUUID(),store=UUID.randomUUID(),u=UUID.randomUUID(),other=UUID.randomUUID(),actor=UUID.randomUUID(),service=UUID.randomUUID(),slot=UUID.randomUUID(),terms=UUID.randomUUID();
   db.update("INSERT INTO merchant VALUES (?,'TEST_ONLY B2 upgrade','ACTIVE')",merchant);db.update("INSERT INTO merchant_store(id,merchant_id,name) VALUES (?,?,'TEST_ONLY store')",store,merchant);
   db.update("INSERT INTO app_user(id,status) VALUES (?,'ACTIVE'),(?,'ACTIVE')",u,other);db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash) VALUES (?,'ADMIN',?,'TEST_ONLY')",actor,UUID.randomUUID().toString());
   db.update("INSERT INTO booking_services(id,store_id,title,kind,status) VALUES (?,?,'TEST_ONLY old service','GROOMING','ACTIVE')",service,store);
   db.update("INSERT INTO booking_slots(id,service_id,starts_at,ends_at,capacity) VALUES (?,?,now()+interval '1 day',now()+interval '1 day 1 hour',2)",slot,service);
   String snapshot="{\"amount_fen\":101,\"currency\":\"CNY\",\"cancel_cutoff_minutes\":60}";
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
   Flyway.configure().dataSource(data).load().migrate();
   assertEquals("AWAITING_PAYMENT",db.queryForObject("SELECT order_state FROM service_trade_orders WHERE id=?",String.class,trades.getFirst()));
   assertEquals("CANCELLED",db.queryForObject("SELECT order_state FROM service_trade_orders WHERE id=?",String.class,trades.getLast()));
   assertEquals("PENDING",db.queryForObject("SELECT status FROM payments WHERE service_trade_id=?",String.class,trades.getFirst()));
   assertEquals("CLOSED",db.queryForObject("SELECT status FROM payments WHERE service_trade_id=?",String.class,trades.getLast()));
   assertEquals(membership,db.queryForObject("SELECT membership_order_id FROM payments WHERE id=?",UUID.class,payment));
   assertEquals("PENDING",db.queryForObject("SELECT status FROM payments WHERE id=?",String.class,payment));
   assertEquals(2,db.queryForObject("SELECT count(*) FROM payments WHERE service_trade_id IS NOT NULL",Integer.class));
   assertEquals("BOOKED",db.queryForObject("SELECT status FROM service_bookings WHERE id=?",String.class,free));assertEquals(0,db.queryForObject("SELECT amount_fen FROM service_bookings WHERE id=?",Integer.class,free));
   for(String table:List.of("payment_attempts","payment_receipts","service_trade_money_events","service_trade_refunds"))assertEquals(0,db.queryForObject("SELECT count(*) FROM "+table,Integer.class));
   assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("INSERT INTO payments(id,payment_no,service_trade_id,membership_order_id,amount_fen,currency,expires_at) VALUES (?,?,?, ?,101,'CNY',now())",UUID.randomUUID(),"TEST_ONLY_invalid",trades.getFirst(),membership));
  }
 }
}
