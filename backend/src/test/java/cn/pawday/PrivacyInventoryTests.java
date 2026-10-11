package cn.pawday;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.nio.file.*;
import java.sql.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

/** Real database schema metadata only; never exports application rows. */
class PrivacyInventoryTests {
    @Test void actualMigratedSchemaIsCollectedInReadOnlySnapshot() throws Exception {
        try(var pg=EmbeddedPostgres.builder().start()) {
            Flyway.configure().dataSource(pg.getPostgresDatabase()).load().migrate();
            try(var c=pg.getPostgresDatabase().getConnection()) {
                c.setReadOnly(true);c.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);c.setAutoCommit(false);
                try(var s=c.createStatement();var r=s.executeQuery("SELECT coalesce(json_agg(row_to_json(s) ORDER BY s.table_name,s.ordinal_position),'[]') FROM (SELECT table_name,column_name,ordinal_position,udt_name,is_nullable,character_maximum_length FROM information_schema.columns WHERE table_schema='public' AND table_name NOT IN ('flyway_schema_history','m63_fixture')) s")) {
                    assertTrue(r.next());Path output=Path.of("target/privacy-review-schema.json");Files.createDirectories(output.getParent());Files.writeString(output,r.getString(1));
                }
                try(var s=c.createStatement();var r=s.executeQuery("SHOW transaction_read_only")) {assertTrue(r.next());assertEquals("on",r.getString(1));}
                assertThrows(SQLException.class,()->{try(var s=c.createStatement()){s.executeUpdate("UPDATE privacy_journal_head SET last_sequence=0");}});
                c.rollback();
            }
        }
    }
}
