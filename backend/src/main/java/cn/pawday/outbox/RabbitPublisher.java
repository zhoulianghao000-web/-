package cn.pawday.outbox;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

@Component
public class RabbitPublisher {
    public static class PublishFailure extends RuntimeException {public final String code;public PublishFailure(String code){super(code);this.code=code;}}
    private final RabbitTemplate rabbit;private final DeliveryPolicy policy;private final JsonMapper json=JsonMapper.builder().build();
    public RabbitPublisher(RabbitTemplate rabbit,DeliveryPolicy policy){this.rabbit=rabbit;this.policy=policy;}
    public void publish(OutboxRepository.Claim claim) {
        var props=new MessageProperties();props.setContentType(MessageProperties.CONTENT_TYPE_JSON);props.setDeliveryMode(MessageDeliveryMode.PERSISTENT);
        props.setMessageId(claim.envelope().event_id().toString());props.setHeader("transport_id",claim.id().toString());
        if(claim.envelope().correlation_id()!=null)props.setCorrelationId(claim.envelope().correlation_id());
        var correlation=new CorrelationData(claim.id()+":"+claim.token());
        try {
            rabbit.send(claim.kind().equals("DEAD_LETTER")?RabbitTopology.DLX:RabbitTopology.EXCHANGE,
                claim.kind().equals("DEAD_LETTER")?"dead":claim.envelope().event_type(),new Message(json.writeValueAsString(claim.envelope()).getBytes(StandardCharsets.UTF_8),props),correlation);
            var confirm=correlation.getFuture().get(policy.confirmMillis,TimeUnit.MILLISECONDS);
            if(!confirm.ack())throw new PublishFailure("BROKER_NACK");
            if(correlation.getReturned()!=null)throw new PublishFailure("UNROUTABLE_MESSAGE");
        } catch(java.util.concurrent.TimeoutException e){throw new PublishFailure("CONFIRM_TIMEOUT");}
        catch(PublishFailure e){throw e;}
        catch(InterruptedException e){Thread.currentThread().interrupt();throw new PublishFailure("PUBLISH_INTERRUPTED");}
        catch(Exception e){throw new PublishFailure("BROKER_UNAVAILABLE");} // Never persist raw exception text or credentials.
    }
}
