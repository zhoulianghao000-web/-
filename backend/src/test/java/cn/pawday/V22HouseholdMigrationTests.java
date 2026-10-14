package cn.pawday;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class V22HouseholdMigrationTests {
 @Test void upgradePreservesOwnerAndDoesNotInventFamilyGrants()throws Exception{
  try(var pg=EmbeddedPostgres.builder().start()){
   Flyway.configure().dataSource(pg.getPostgresDatabase()).target("26").load().migrate();UUID user=UUID.randomUUID(),pet=UUID.randomUUID();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()){
    s.execute("INSERT INTO app_user(id,status) VALUES ('"+user+"','ACTIVE')");
    s.execute("INSERT INTO pets(id,owner_user_id,name,species_id,sex,neutered_status) VALUES ('"+pet+"','"+user+"','TEST_ONLY_UPGRADE','10000000-0000-4000-8000-000000000001','UNKNOWN','UNKNOWN')");
   }
   Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
   try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT owner_user_id,version,(SELECT count(*) FROM pet_share_members),(SELECT count(*) FROM pet_share_invites),(SELECT count(*) FROM pet_care_entries) FROM pets WHERE id='"+pet+"'")){
    assertTrue(r.next());assertEquals(user,r.getObject(1));assertEquals(0,r.getLong(2));assertEquals(0,r.getLong(3));assertEquals(0,r.getLong(4));assertEquals(0,r.getLong(5));
   }
  }
 }
}
