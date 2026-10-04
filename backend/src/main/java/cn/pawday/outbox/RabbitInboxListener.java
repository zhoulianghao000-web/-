package cn.pawday.outbox;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;
@Component
public class RabbitInboxListener {
    private final InboxConsumer consumer;private final JsonMapper json=JsonMapper.builder().build();
    public RabbitInboxListener(InboxConsumer consumer){this.consumer=consumer;}
    @RabbitListener(queues=RabbitTopology.QUEUE,ackMode="MANUAL",autoStartup="${pawday.outbox.consumer-enabled:true}")
    public void receive(Message message,Channel channel) throws IOException {
        long tag=message.getMessageProperties().getDeliveryTag();
        try {
            EventEnvelope envelope=json.readValue(message.getBody(),EventEnvelope.class);
            if(envelope.event_id()==null || !envelope.event_id().toString().equals(message.getMessageProperties().getMessageId()))throw new IllegalArgumentException("Invalid event id");
            consumer.process(envelope);channel.basicAck(tag,false); // Only after inbox/business/retry transaction commits.
        } catch(IllegalArgumentException | tools.jackson.core.JacksonException poison){channel.basicReject(tag,false);}
        catch(Exception databaseUnavailable){
            // DB unavailable means there is no durable retry decision yet; retain at broker.
            try {Thread.sleep(250);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();}
            channel.basicNack(tag,false,true);
        }
    }
}
