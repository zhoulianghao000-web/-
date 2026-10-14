package cn.pawday;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.time.Instant;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class V21PriceHistoryMigrationTests {
 @Test void upgradeCapturesCurrentBaselineWithoutInventingPriorDates() throws Exception {
  try(var pg=EmbeddedPostgres.builder().start()){
   Flyway.configure().dataSource(pg.getPostgresDatabase()).target("25").load().migrate();
   UUID merchant=UUID.randomUUID(),brand=UUID.randomUUID(),spu=UUID.randomUUID(),sku=UUID.randomUUID(),offer=UUID.randomUUID();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){
    s.execute("INSERT INTO merchant(id,name,status) VALUES ('"+merchant+"','TEST_ONLY_UPGRADE','ACTIVE')");
    s.execute("INSERT INTO brands(id,name,source_ref) VALUES ('"+brand+"','TEST_ONLY_UPGRADE','TEST_ONLY')");
    s.execute("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES ('"+spu+"','"+brand+"','TEST_ONLY','CAT','DRY_FOOD')");
    s.execute("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES ('"+sku+"','"+spu+"','TEST_ONLY_UPGRADE',1000,'BAG')");
    s.execute("INSERT INTO offers(id,merchant_id,sku_id,sale_price_fen,fulfillment_sla,created_at) VALUES ('"+offer+"','"+merchant+"','"+sku+"',1234,'TEST_ONLY',now()-interval '60 days')");
   }
   Instant before=Instant.now();Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT kind,sale_price_fen,recorded_at FROM offer_price_snapshots WHERE offer_id='"+offer+"'")){
    assertTrue(r.next());assertEquals("BASELINE",r.getString(1));assertEquals(1234,r.getLong(2));assertFalse(r.getTimestamp(3).toInstant().isBefore(before));assertFalse(r.next());
   }
  }
 }
}
