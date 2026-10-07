package cn.pawday.search;
import cn.pawday.identity.Crypto;
import cn.pawday.outbox.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import tools.jackson.databind.json.JsonMapper;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class BusinessFactConsumer {
    public static final String CONSUMER="catalog-business-facts-v1";
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OutboxWriter writer;private final DeliveryPolicy policy;private final Crypto crypto;
    private final BusinessSearchProjection projection;private final JsonMapper json=JsonMapper.builder().build();
    public BusinessFactConsumer(JdbcTemplate db,TransactionTemplate tx,OutboxWriter writer,DeliveryPolicy policy,Crypto crypto,BusinessSearchProjection projection){this.projection=projection;this.db=db;this.tx=tx;this.writer=writer;this.policy=policy;this.crypto=crypto;}
    public void process(EventEnvelope event) {
        if(event.event_id()==null || event.event_type()==null || event.event_type().isBlank() || event.event_version()<1 || event.aggregate_type()==null || event.aggregate_id()==null || event.payload()==null || event.delivery_attempt()<1 || event.generation()<0)throw new IllegalArgumentException("Invalid envelope");
        String hash=crypto.hash(json.writeValueAsString(List.of(event.event_type(),event.event_version(),event.aggregate_type(),event.aggregate_id(),new TreeMap<>(event.payload()))));
        tx.executeWithoutResult(status->{
            var roots=db.queryForList("SELECT generation FROM outbox_event WHERE id=?",event.event_id());
            if(!roots.isEmpty() && event.generation()!=((Number)roots.getFirst().get("generation")).intValue())return;
            db.update("INSERT INTO processed_event(consumer,event_id,status,payload_hash,generation) VALUES (?,?,'FAILED_RETRYABLE',?,?) ON CONFLICT DO NOTHING",CONSUMER,event.event_id(),hash,event.generation());
            var row=db.queryForMap("SELECT * FROM processed_event WHERE consumer=? AND event_id=? FOR UPDATE",CONSUMER,event.event_id());
            if(!hash.equals(row.get("payload_hash")))throw new IllegalArgumentException("Event identity payload conflict");
            if(row.get("status").equals("PROCESSED") || row.get("status").equals("DEAD"))return;
            int attempt=((Number)row.get("attempt_count")).intValue()+1;
            if(event.delivery_attempt()!=attempt || event.generation()!=((Number)row.get("generation")).intValue())return;
            Object savepoint=status.createSavepoint();String code=null;
            try{handle(event);}catch(Exception e){status.rollbackToSavepoint(savepoint);code=e instanceof InvalidEvent failure?failure.code:"BUSINESS_FACT_INBOX_FAILURE";}finally{status.releaseSavepoint(savepoint);}
            if(code==null)db.update("UPDATE processed_event SET status='PROCESSED',attempt_count=?,completed_at=clock_timestamp(),next_attempt_at=NULL,last_error_code=NULL,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",attempt,CONSUMER,event.event_id());
            else {
                boolean dead=attempt>=policy.maxAttempts;
                db.update("UPDATE processed_event SET status=?,attempt_count=?,last_error_code=?,next_attempt_at=CASE WHEN ? THEN NULL ELSE clock_timestamp()+(?*interval '1 millisecond') END,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",dead?"DEAD":"FAILED_RETRYABLE",attempt,code,dead,policy.backoff(attempt),CONSUMER,event.event_id());
                if(dead)writer.deadLetter(event.event_id(),"BUSINESS_FACT_INBOX",code,event.generation());
                else writer.insert(UUID.randomUUID(),event.event_id(),"RETRY",event.aggregate_type(),event.aggregate_id(),event.event_type(),event.event_version(),event.payload(),event.correlation_id(),attempt+1,event.generation(),policy.backoff(attempt));
            }
        });
    }
    private void handle(EventEnvelope e) {
        if(e.event_version()!=1)throw new InvalidEvent("UNSUPPORTED_BUSINESS_EVENT_VERSION");
        boolean catalog=e.event_type().equals("CatalogStandardPublished"), reservation=e.event_type().equals("InventoryReservationChanged"), stock=e.event_type().equals("InventoryAdjusted")||reservation, offer=e.event_type().equals("OfferStateChanged");
        if(!catalog&&!stock&&!offer)throw new InvalidEvent("UNSUPPORTED_BUSINESS_EVENT");
        Set<String> fields=catalog?Set.of("sku_id","standard_version_id"):stock?Set.of("offer_id","sku_id",reservation?"reservation_event_id":"adjustment_id","inventory_version"):Set.of("offer_id","sku_id","version");
        if(!fields.equals(e.payload().keySet()))throw new InvalidEvent("INVALID_BUSINESS_EVENT_PAYLOAD");
        UUID sku=UUID.fromString(e.payload().get("sku_id").toString());
        if(catalog){UUID v=UUID.fromString(e.payload().get("standard_version_id").toString());if(!e.aggregate_type().equals("CATALOG_SKU")||!e.aggregate_id().equals(sku.toString())||db.queryForObject("SELECT count(*) FROM sku_standard_versions WHERE id=? AND sku_id=? AND status IN ('PUBLISHED','RETIRED')",Integer.class,v,sku)!=1)throw new InvalidEvent("INVALID_BUSINESS_EVENT_PAYLOAD");}
        else{UUID id=UUID.fromString(e.payload().get("offer_id").toString());if(!e.aggregate_type().equals("OFFER")||!e.aggregate_id().equals(id.toString())||db.queryForObject("SELECT count(*) FROM offers WHERE id=? AND sku_id=?",Integer.class,id,sku)!=1)throw new InvalidEvent("INVALID_BUSINESS_EVENT_PAYLOAD");Object version=e.payload().get(stock?"inventory_version":"version");if(!(version instanceof Number n)||n.longValue()<0)throw new InvalidEvent("INVALID_BUSINESS_EVENT_PAYLOAD");if(stock){UUID adjustment=UUID.fromString(e.payload().get(reservation?"reservation_event_id":"adjustment_id").toString());boolean known=reservation?db.queryForObject("SELECT count(*) FROM inventory_reservation_events WHERE id=? AND offer_id=?",Integer.class,adjustment,id)==1:db.queryForObject("SELECT (SELECT count(*) FROM inventory_adjustments WHERE id=? AND offer_id=?)+(SELECT count(*) FROM inventory_restock_events WHERE id=? AND offer_id=?)",Integer.class,adjustment,id,adjustment,id)==1;if(!known)throw new InvalidEvent("INVALID_BUSINESS_EVENT_PAYLOAD");}}
        projection.refresh(sku,catalog?"CatalogPublished":stock?"InventoryAvailabilityChanged":"OfferChanged",e.correlation_id());
    }
    private static class InvalidEvent extends RuntimeException{final String code;InvalidEvent(String code){this.code=code;}}
}
