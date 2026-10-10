package cn.pawday.operations;

import io.micrometer.core.instrument.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Fixed-cardinality read-only operational facts. No user/order/merchant identifiers. */
@Component
public final class OperationsMetrics {
    public OperationsMetrics(MeterRegistry registry,JdbcTemplate db) {
        Gauge.builder("pawday.operations.db.available",db,j->{try{return j.queryForObject("SELECT 1",Integer.class);}catch(org.springframework.dao.DataAccessException e){return 0;}}).register(registry);
        register(registry,db,"pawday.privacy.export.backlog","SELECT greatest(0,h.last_sequence-s.exported_sequence) FROM privacy_journal_head h CROSS JOIN privacy_export_state s");
        register(registry,db,"pawday.privacy.export.coverage.age.seconds","SELECT coalesce(extract(epoch FROM clock_timestamp()-covered_until),extract(epoch FROM clock_timestamp()-h.installed_at)) FROM privacy_export_state s CROSS JOIN privacy_journal_head h");
        register(registry,db,"pawday.privacy.export.failures","SELECT attempts FROM privacy_export_state");
        register(registry,db,"pawday.privacy.export.unavailable","SELECT CASE WHEN covered_until IS NULL OR last_error_code IS NOT NULL THEN 1 ELSE 0 END FROM privacy_export_state");
        register(registry,db,"pawday.payment.unknown","SELECT count(*) FROM payment_attempts WHERE status='UNKNOWN'");
        register(registry,db,"pawday.payment.unknown.age.seconds","SELECT coalesce(extract(epoch FROM now()-min(created_at)),0) FROM payment_attempts WHERE status='UNKNOWN'");
        register(registry,db,"pawday.refund.pending","SELECT count(*) FROM refunds WHERE status IN ('CREATED','PROCESSING','FAILED_RETRYABLE')");
        register(registry,db,"pawday.refund.expired.leases","SELECT count(*) FROM refunds WHERE lease_until<=now() AND status='PROCESSING'");
        register(registry,db,"pawday.refund.oldest.age.seconds","SELECT coalesce(extract(epoch FROM now()-min(created_at)),0) FROM refunds WHERE status IN ('CREATED','PROCESSING','FAILED_RETRYABLE')");
        register(registry,db,"pawday.settlement.retryable","SELECT count(*) FROM settlements WHERE status='FAILED_RETRYABLE'");
        register(registry,db,"pawday.settlement.debit.mismatches","SELECT count(*) FROM settlements s WHERE s.status='SETTLED' AND s.amount_fen<>coalesce((SELECT e.amount_fen FROM merchant_ledger_entries e WHERE e.settlement_id=s.id AND e.entry_type='SETTLEMENT_DEBIT'),0)");
    }
    private static void register(MeterRegistry r,JdbcTemplate db,String name,String sql) {
        Gauge.builder(name,db,j->j.queryForObject(sql,Double.class)).register(r);
    }
}
