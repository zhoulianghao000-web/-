package cn.pawday;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class V31BookingMigrationTests {
 @Test void upgradeDoesNotRewriteExistingMerchantOrInventAppointments()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   Flyway.configure().dataSource(pg.getPostgresDatabase()).target("27").load().migrate();UUID merchant=UUID.randomUUID(),store=UUID.randomUUID();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){
    s.execute("INSERT INTO merchant VALUES ('"+merchant+"','TEST ONLY preserved','ACTIVE')");
    s.execute("INSERT INTO merchant_store(id,merchant_id,name) VALUES ('"+store+"','"+merchant+"','TEST ONLY store')");
   }
   Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT name,(SELECT count(*) FROM booking_services),(SELECT count(*) FROM booking_slots),(SELECT count(*) FROM service_bookings) FROM merchant_store WHERE id='"+store+"'")){
    assertTrue(r.next());assertEquals("TEST ONLY store",r.getString(1));assertEquals(0,r.getLong(2));assertEquals(0,r.getLong(3));assertEquals(0,r.getLong(4));
   }
  }
 }
}
