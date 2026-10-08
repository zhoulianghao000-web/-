package cn.pawday.support;
import cn.pawday.identity.Crypto;
import cn.pawday.outbox.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;
@Component
public class SupportInboxConsumer {
    public static final String CONSUMER="support-notifications-v1";
    private final JdbcTemplate db;private final TransactionTemplate tx;private final OutboxWriter writer;private final DeliveryPolicy policy;private final Crypto crypto;
    private final NotificationService notifications;private final JsonMapper json=JsonMapper.builder().build();
    public SupportInboxConsumer(JdbcTemplate db,TransactionTemplate tx,OutboxWriter writer,DeliveryPolicy policy,Crypto crypto,NotificationService notifications){this.notifications=notifications;this.db=db;this.tx=tx;this.writer=writer;this.policy=policy;this.crypto=crypto;}
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
            try{handle(event);}catch(Exception e){status.rollbackToSavepoint(savepoint);code=e instanceof InvalidEvent failure?failure.code:"SUPPORT_INBOX_FAILURE";}finally{status.releaseSavepoint(savepoint);}
            if(code==null)db.update("UPDATE processed_event SET status='PROCESSED',attempt_count=?,completed_at=clock_timestamp(),next_attempt_at=NULL,last_error_code=NULL,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",attempt,CONSUMER,event.event_id());
            else {
                boolean dead=attempt>=policy.maxAttempts;
                db.update("UPDATE processed_event SET status=?,attempt_count=?,last_error_code=?,next_attempt_at=CASE WHEN ? THEN NULL ELSE clock_timestamp()+(?*interval '1 millisecond') END,updated_at=clock_timestamp() WHERE consumer=? AND event_id=?",dead?"DEAD":"FAILED_RETRYABLE",attempt,code,dead,policy.backoff(attempt),CONSUMER,event.event_id());
                if(dead)writer.deadLetter(event.event_id(),"SUPPORT_INBOX",code,event.generation());
                else writer.insert(UUID.randomUUID(),event.event_id(),"RETRY",event.aggregate_type(),event.aggregate_id(),event.event_type(),event.event_version(),event.payload(),event.correlation_id(),attempt+1,event.generation(),policy.backoff(attempt));
            }
        });
    }
    private void handle(EventEnvelope e) {
        if(e.event_version()!=1)throw new InvalidEvent("UNSUPPORTED_EVENT_VERSION");
        var roots=db.queryForList("SELECT aggregate_type,aggregate_id,event_type,payload FROM outbox_event WHERE id=?",e.event_id());
        if(roots.isEmpty())throw new InvalidEvent("UNKNOWN_EVENT");var root=roots.getFirst();
        if(!e.event_type().equals(root.get("event_type"))||!e.aggregate_type().equals(root.get("aggregate_type"))||!e.aggregate_id().equals(root.get("aggregate_id"))||!json.readTree(root.get("payload").toString()).equals(json.valueToTree(e.payload())))throw new InvalidEvent("EVENT_FACT_MISMATCH");
        UUID recipient,target;String category,targetType;
        if(e.event_type().equals("SupportMessageCreated")){
            if(!e.payload().keySet().equals(Set.of("conversation_id","message_id","sequence")))throw new InvalidEvent("INVALID_EVENT_PAYLOAD");
            UUID cid=UUID.fromString(e.payload().get("conversation_id").toString()),mid=UUID.fromString(e.payload().get("message_id").toString());
            if(!e.aggregate_type().equals("CONVERSATION")||!e.aggregate_id().equals(cid.toString()))throw new InvalidEvent("INVALID_EVENT_PAYLOAD");
            var rows=db.queryForList("SELECT c.consumer_id,m.sender_realm,m.sequence FROM conversations c JOIN conversation_messages m ON m.conversation_id=c.id WHERE c.id=? AND m.id=?",cid,mid);
            if(rows.isEmpty()||!(e.payload().get("sequence") instanceof Number n)||n.longValue()!=((Number)rows.getFirst().get("sequence")).longValue())throw new InvalidEvent("MESSAGE_NOT_FOUND");
            db.queryForMap("SELECT id FROM conversations WHERE id=? FOR UPDATE",cid);
            db.update("INSERT INTO conversation_message_delivery(message_id,event_id) VALUES (?,?) ON CONFLICT(message_id) DO NOTHING",mid,e.event_id());
            db.update("UPDATE conversations c SET delivered_sequence=(SELECT coalesce(min(m.sequence)-1,c.last_sequence) FROM conversation_messages m WHERE m.conversation_id=c.id AND NOT EXISTS(SELECT 1 FROM conversation_message_delivery d WHERE d.message_id=m.id)) WHERE c.id=?",cid);
            if(rows.getFirst().get("sender_realm").equals("CONSUMER"))return;
            recipient=(UUID)rows.getFirst().get("consumer_id");target=cid;category="SUPPORT";targetType="CONVERSATION";
        }else if(e.event_type().equals("SupportAssigned")){
            if(!e.payload().keySet().equals(Set.of("conversation_id"))||!e.aggregate_type().equals("CONVERSATION")||!e.aggregate_id().equals(e.payload().get("conversation_id")))throw new InvalidEvent("INVALID_EVENT_PAYLOAD");
            return;
        }else if(Set.of("OrderCreated","OrderPaid","OrderCancelled","OrderExpired","ShipmentCreated","SuborderReceiptConfirmed").contains(e.event_type())){
            target=UUID.fromString(e.payload().get("order_id").toString());var rows=db.queryForList("SELECT ip.id FROM orders o JOIN identity_principal ip ON ip.user_id=o.user_id AND ip.realm='CONSUMER' WHERE o.id=?",target);
            if(rows.isEmpty())throw new InvalidEvent("ORDER_NOT_FOUND");recipient=(UUID)rows.getFirst().get("id");category="ORDER";targetType="ORDER";
        }else if(Set.of("AfterSaleCreated","AfterSaleMerchantDecision","AfterSaleInspected","AfterSaleEscalated","AfterSaleArbitrated","AfterSaleCompleted").contains(e.event_type())){
            target=UUID.fromString(e.payload().get("aftersale_id").toString());var rows=db.queryForList("SELECT ip.id FROM aftersales a JOIN orders o ON o.id=a.order_id JOIN identity_principal ip ON ip.user_id=o.user_id AND ip.realm='CONSUMER' WHERE a.id=?",target);
            if(rows.isEmpty())throw new InvalidEvent("AFTERSALE_NOT_FOUND");recipient=(UUID)rows.getFirst().get("id");category="AFTERSALE";targetType="AFTERSALE";
        }else throw new InvalidEvent("UNSUPPORTED_EVENT_TYPE");
        db.update("INSERT INTO notification_messages(id,principal_id,event_id,category,event_type,target_type,target_id,notify_enabled) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(principal_id,event_id) DO NOTHING",UUID.randomUUID(),recipient,e.event_id(),category,e.event_type(),targetType,target,notifications.enabled(recipient,category));
    }
    private static class InvalidEvent extends RuntimeException{final String code;InvalidEvent(String code){this.code=code;}}
}
