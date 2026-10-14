package cn.pawday.offer;

import cn.pawday.common.Api.Failure;
import cn.pawday.identity.Actor;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class PriceHistoryService {
 private static final ZoneId ZONE=ZoneId.of("Asia/Shanghai");
 private final JdbcTemplate db;private final OfferService offers;private final TransactionTemplate read;
 public PriceHistoryService(JdbcTemplate db,OfferService offers,PlatformTransactionManager manager){
  this.db=db;this.offers=offers;read=new TransactionTemplate(manager);read.setReadOnly(true);read.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ);
 }
 public Map<String,Object> history(UUID id,int days,Actor actor,boolean admin){
  if(days!=30&&days!=90)throw new Failure(400,"VALIDATION_ERROR");
  return read.execute(s->{
   Instant asOf=db.queryForObject("SELECT clock_timestamp()",java.sql.Timestamp.class).toInstant();
   Map<String,Object> offer;
   boolean publicView=actor==null;
   if(publicView){
    var found=db.queryForList("""
     SELECT o.* FROM offers o JOIN merchant m ON m.id=o.merchant_id
     JOIN skus k ON k.id=o.sku_id JOIN spus p ON p.id=k.spu_id JOIN brands b ON b.id=p.brand_id
     WHERE o.id=? AND o.sale_status='ACTIVE' AND m.status='ACTIVE' AND k.status='ACTIVE' AND p.status='ACTIVE' AND b.status='ACTIVE'
     AND EXISTS(SELECT 1 FROM sku_standard_versions v WHERE v.sku_id=k.id AND v.status='PUBLISHED')
     AND EXISTS(SELECT 1 FROM inventory_balances i WHERE i.offer_id=o.id)
     """,id);
    if(found.isEmpty())throw new Failure(404,"RESOURCE_NOT_FOUND");offer=found.getFirst();
   }else offer=offers.historyAccess(actor,admin,id);
   LocalDate to=asOf.atZone(ZONE).toLocalDate(),from=to.minusDays(days-1);
   var points=db.queryForList("""
    SELECT d.day::date::text AS date,
      CASE WHEN ? OR h.publicly_recorded THEN h.sale_price_fen ELSE NULL END AS sale_price_fen,
      CASE WHEN ? OR h.publicly_recorded THEN h.member_price_fen ELSE NULL END AS member_price_fen,
      CASE WHEN ? OR h.publicly_recorded THEN h.sale_status ELSE NULL END AS sale_status,
      CASE WHEN ? OR h.publicly_recorded THEN h.recorded_at ELSE NULL END AS recorded_at,h.publicly_recorded
    FROM generate_series(?::date,?::date,interval '1 day') d(day)
    LEFT JOIN LATERAL (
      SELECT sale_price_fen,member_price_fen,sale_status,recorded_at,publicly_recorded FROM offer_price_snapshots
      WHERE offer_id=? AND recorded_at<=? AND recorded_at<((d.day::date+1)::timestamp AT TIME ZONE 'Asia/Shanghai')
      ORDER BY recorded_at DESC,id DESC LIMIT 1
    ) h ON true ORDER BY d.day
    """,!publicView,!publicView,!publicView,!publicView,from.toString(),to.toString(),id,java.sql.Timestamp.from(asOf));
   List<Long> known=points.stream().filter(p->p.get("sale_price_fen")!=null).map(p->((Number)p.get("sale_price_fen")).longValue()).toList();
   var out=new LinkedHashMap<String,Object>();out.put("offer_id",id);out.put("sku_id",offer.get("sku_id"));out.put("days",days);out.put("timezone","Asia/Shanghai");out.put("currency","CNY");out.put("basis","DAILY_LAST_RECORDED_QUOTATION");out.put("as_of",asOf);out.put("from_date",from);out.put("to_date",to);
   out.put("observed_from",db.queryForObject("SELECT min(recorded_at) FROM offer_price_snapshots WHERE offer_id=? AND (? OR publicly_recorded)",java.sql.Timestamp.class,id,!publicView));
   out.put("current_sale_price_fen",offer.get("sale_price_fen"));out.put("current_member_price_fen",offer.get("member_price_fen"));out.put("offer_version",offer.get("version"));out.put("observed_days",known.size());out.put("lowest_recorded_daily_sale_price_fen",known.isEmpty()?null:Collections.min(known));out.put("highest_recorded_daily_sale_price_fen",known.isEmpty()?null:Collections.max(known));out.put("points",points);return out;
  });
 }
}
