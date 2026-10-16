package cn.pawday;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class V312FulfillmentMigrationTests {
 @Test void upgradePreservesV28ReservationWithoutInventingFulfillment()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   Flyway.configure().dataSource(pg.getPostgresDatabase()).target("28").load().migrate();
   UUID merchant=UUID.randomUUID(),store=UUID.randomUUID(),user=UUID.randomUUID(),service=UUID.randomUUID(),slot=UUID.randomUUID(),booking=UUID.randomUUID();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){
    s.execute("INSERT INTO merchant VALUES ('"+merchant+"','TEST preserved','ACTIVE')");s.execute("INSERT INTO merchant_store(id,merchant_id,name) VALUES ('"+store+"','"+merchant+"','TEST store')");s.execute("INSERT INTO app_user(id,status) VALUES ('"+user+"','ACTIVE')");
    s.execute("INSERT INTO booking_services(id,store_id,title,kind) VALUES ('"+service+"','"+store+"','TEST wash','GROOMING')");s.execute("INSERT INTO booking_slots(id,service_id,starts_at,ends_at,capacity) VALUES ('"+slot+"','"+service+"',now()+interval '1 day',now()+interval '1 day 1 hour',1)");
    s.execute("INSERT INTO service_bookings(id,slot_id,service_id,store_id,user_id,service_title) VALUES ('"+booking+"','"+slot+"','"+service+"','"+store+"','"+user+"','TEST original snapshot')");
   }
   Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT service_title,status,version,amount_fen,(SELECT count(*) FROM booking_fulfillment_events) FROM service_bookings WHERE id='"+booking+"'")){
    assertTrue(r.next());assertEquals("TEST original snapshot",r.getString(1));assertEquals("BOOKED",r.getString(2));assertEquals(0,r.getLong(3));assertEquals(0,r.getLong(4));assertEquals(0,r.getLong(5));
   }
  }
 }
}
