package cn.pawday.analytics;

import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import cn.pawday.pilot.PilotPolicy;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;

@Service
public class BusinessAnalyticsService {
    private static final ZoneId ZONE=ZoneId.of("Asia/Shanghai");
    private static final long SAFE=9007199254740991L;
    private final JdbcTemplate db;
    private final Clock clock;
    private final PilotPolicy pilot;
    public BusinessAnalyticsService(JdbcTemplate db,Clock clock,PilotPolicy pilot) { this.db=db; this.clock=clock; this.pilot=pilot; }
    public record Metrics(long paid_suborders,long refund_count,long paid_fen,long refund_fen,long net_fen,long commission_net_fen,long merchant_net_fen) {}
    public record Day(LocalDate date,Metrics metrics) {}
    public record Overview(UUID merchant_id,UUID store_id,String timezone,LocalDate from,LocalDate to,Instant as_of,String source,String scope_policy,boolean simulated,Metrics totals,List<Day> days) {}
    private long amount(Object value) {
        try { long n=new BigDecimal(value.toString()).longValueExact(); if(n < -SAFE || n > SAFE) throw new ArithmeticException(); return n; }
        catch(ArithmeticException e) { throw new Failure(422,"ANALYTICS_AMOUNT_OVERFLOW"); }
    }
    private Metrics metrics(Map<String,Object> row) {
        long paid=amount(row.get("paid_fen")),refund=amount(row.get("refund_fen")),commission=amount(row.get("commission_net_fen"));
        long net=amount(BigDecimal.valueOf(paid).subtract(BigDecimal.valueOf(refund)));
        long merchantNet=amount(BigDecimal.valueOf(net).subtract(BigDecimal.valueOf(commission)));
        return new Metrics(amount(row.get("paid_suborders")),amount(row.get("refund_count")),paid,refund,net,commission,merchantNet);
    }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Overview read(Actor actor,UUID requestedMerchant,UUID store,LocalDate from,LocalDate to) {
        boolean merchant=actor.realm()==Actor.Realm.MERCHANT;
        if(!actor.permissions().contains("ledger.read") || !actor.permissions().contains(merchant?"order.read":"order.admin.read") || !(merchant || actor.realm()==Actor.Realm.ADMIN)) throw new Failure(403,"PERMISSION_DENIED");
        UUID m=merchant?actor.merchantId():requestedMerchant;
        if(m==null || merchant && requestedMerchant!=null && !m.equals(requestedMerchant)) throw new Failure(404,"RESOURCE_NOT_FOUND");
        if(db.queryForObject("SELECT count(*) FROM merchant WHERE id=?",Integer.class,m)==0) throw new Failure(404,"RESOURCE_NOT_FOUND");
        if(store!=null) {
            String q="SELECT count(*) FROM merchant_store st WHERE st.id=? AND st.merchant_id=?";
            if(merchant) q+=" AND EXISTS(SELECT 1 FROM principal_store_scope p WHERE p.store_id=st.id AND p.merchant_id=st.merchant_id AND p.principal_id=?)";
            if(db.queryForObject(q,Integer.class,merchant?new Object[]{store,m,actor.principalId()}:new Object[]{store,m})==0) throw new Failure(404,"RESOURCE_NOT_FOUND");
        }
        Instant now=clock.instant();
        if(from==null || to==null || from.isAfter(to) || ChronoUnit.DAYS.between(from,to)>=90 || to.isAfter(now.atZone(ZONE).toLocalDate()) || from.isBefore(LocalDate.of(2000,1,1))) throw new Failure(400,"VALIDATION_ERROR");
        var args=new ArrayList<Object>(List.of(m,Timestamp.from(from.atStartOfDay(ZONE).toInstant()),Timestamp.from(to.plusDays(1).atStartOfDay(ZONE).toInstant()),Timestamp.from(now)));
        String scope="";
        if(merchant) {
            scope=" AND NOT EXISTS(SELECT 1 FROM order_items i WHERE i.suborder_id=s.id AND ((i.store_id IS NULL AND NOT ?) OR (i.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM principal_store_scope p WHERE p.principal_id=? AND p.merchant_id=i.merchant_id AND p.store_id=i.store_id))))";
            args.add(actor.permissions().contains("order.default-scope")); args.add(actor.principalId());
        }
        if(store!=null) { scope+=" AND NOT EXISTS(SELECT 1 FROM order_items i WHERE i.suborder_id=s.id AND i.store_id IS DISTINCT FROM ?)"; args.add(store); }
        // One row per immutable entry, never a join to order_items (which would multiply amounts).
        var rows=db.queryForList("SELECT (e.created_at AT TIME ZONE 'Asia/Shanghai')::date ledger_date,"+
            " count(DISTINCT e.suborder_id) FILTER(WHERE e.entry_type='SALE_CREDIT') paid_suborders,"+
            " count(DISTINCT e.refund_id) FILTER(WHERE e.entry_type IN ('REFUND_DEBIT','SHIPPING_ADJUSTMENT') AND e.direction='DEBIT') refund_count,"+
            " coalesce(sum(e.amount_fen) FILTER(WHERE e.entry_type='SALE_CREDIT'),0) paid_fen,"+
            " coalesce(sum(e.amount_fen) FILTER(WHERE e.entry_type IN ('REFUND_DEBIT','SHIPPING_ADJUSTMENT') AND e.direction='DEBIT'),0) refund_fen,"+
            " coalesce(sum(CASE WHEN e.entry_type='COMMISSION_DEBIT' THEN e.amount_fen WHEN e.entry_type='COMMISSION_REVERSAL' THEN -e.amount_fen ELSE 0 END),0) commission_net_fen"+
            " FROM merchant_ledger_entries e JOIN suborders s ON s.id=e.suborder_id AND s.merchant_id=e.merchant_id"+
            " WHERE e.merchant_id=? AND e.created_at>=? AND e.created_at<? AND e.created_at<=?"+
            " AND e.entry_type IN ('SALE_CREDIT','REFUND_DEBIT','SHIPPING_ADJUSTMENT','COMMISSION_DEBIT','COMMISSION_REVERSAL')"+
            " AND EXISTS(SELECT 1 FROM order_items i WHERE i.suborder_id=s.id)"+scope+" GROUP BY ledger_date ORDER BY ledger_date",args.toArray());
        Map<LocalDate,Metrics> byDate=new HashMap<>();
        var sums=new LinkedHashMap<String,Object>(); for(String k:List.of("paid_suborders","refund_count","paid_fen","refund_fen","commission_net_fen")) sums.put(k,BigDecimal.ZERO);
        for(var row:rows) { LocalDate date=((java.sql.Date)row.get("ledger_date")).toLocalDate(); byDate.put(date,metrics(row)); for(String k:sums.keySet()) sums.put(k,((BigDecimal)sums.get(k)).add(new BigDecimal(row.get(k).toString()))); }
        var days=new ArrayList<Day>(); var zero=new Metrics(0,0,0,0,0,0,0);
        for(LocalDate date=from;!date.isAfter(to);date=date.plusDays(1)) days.add(new Day(date,byDate.getOrDefault(date,zero)));
        return new Overview(m,store,"Asia/Shanghai",from,to,now,"IMMUTABLE_MERCHANT_LEDGER","WHOLE_AUTHORIZED_SUBORDER",pilot.enabled(),metrics(sums),List.copyOf(days));
    }
}
