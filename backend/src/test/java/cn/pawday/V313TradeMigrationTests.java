package cn.pawday;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class V313TradeMigrationTests {
 @Test void upgradePreservesOldBookingAndFulfillmentWithoutInventingTrades()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   Flyway.configure().dataSource(pg.getPostgresDatabase()).target("29").load().migrate();
   UUID merchant=UUID.randomUUID(),store=UUID.randomUUID(),user=UUID.randomUUID(),service=UUID.randomUUID(),slot=UUID.randomUUID(),booking=UUID.randomUUID(),actor=UUID.randomUUID();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){
    s.execute("INSERT INTO merchant VALUES ('"+merchant+"','TEST B1 preserved','ACTIVE')");s.execute("INSERT INTO merchant_store(id,merchant_id,name) VALUES ('"+store+"','"+merchant+"','TEST B1 store')");s.execute("INSERT INTO app_user(id,status) VALUES ('"+user+"','ACTIVE')");s.execute("INSERT INTO identity_principal(id,realm,user_id) VALUES ('"+actor+"','CONSUMER','"+user+"')");
    s.execute("INSERT INTO booking_services(id,store_id,title,kind) VALUES ('"+service+"','"+store+"','TEST old wash','GROOMING')");s.execute("INSERT INTO booking_slots(id,service_id,starts_at,ends_at,capacity) VALUES ('"+slot+"','"+service+"',now()-interval '5 minutes',now()+interval '1 hour',1)");s.execute("INSERT INTO service_bookings(id,slot_id,service_id,store_id,user_id,service_title) VALUES ('"+booking+"','"+slot+"','"+service+"','"+store+"','"+user+"','TEST preserved title')");s.execute("INSERT INTO booking_fulfillment_events VALUES ('"+UUID.randomUUID()+"','"+booking+"',1,'CHECKED_IN','','"+actor+"',now())");
   }
   Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT service_title,status,amount_fen,(SELECT count(*) FROM booking_fulfillment_events),(SELECT count(*) FROM service_trade_terms),(SELECT count(*) FROM service_trade_quotes),(SELECT count(*) FROM service_trade_orders) FROM service_bookings WHERE id='"+booking+"'")){
    assertTrue(r.next());assertEquals("TEST preserved title",r.getString(1));assertEquals("BOOKED",r.getString(2));assertEquals(0,r.getLong(3));assertEquals(1,r.getLong(4));for(int i=5;i<=7;i++)assertEquals(0,r.getLong(i));
   }
  }
 }
}
