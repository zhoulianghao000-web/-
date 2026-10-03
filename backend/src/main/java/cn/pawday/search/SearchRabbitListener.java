package cn.pawday.search;
import cn.pawday.outbox.*;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import tools.jackson.databind.json.JsonMapper;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchRabbitListener {
    private final SearchInboxConsumer consumer;private final JsonMapper json=JsonMapper.builder().build();
    public SearchRabbitListener(SearchInboxConsumer consumer){this.consumer=consumer;}
    @RabbitListener(queues=RabbitTopology.SEARCH_QUEUE,ackMode="MANUAL",autoStartup="${pawday.search.consumers-enabled:true}")
    public void receive(Message message,Channel channel) throws IOException {
        long tag=message.getMessageProperties().getDeliveryTag();
        try {
            var event=json.readValue(message.getBody(),EventEnvelope.class);
            if(event.event_id()==null || !event.event_id().toString().equals(message.getMessageProperties().getMessageId()))throw new IllegalArgumentException("Invalid event id");
            consumer.process(event);channel.basicAck(tag,false);
        }catch(IllegalArgumentException | tools.jackson.core.JacksonException poison){channel.basicReject(tag,false);}
        catch(Exception databaseUnavailable){try{Thread.sleep(250);}catch(InterruptedException e){Thread.currentThread().interrupt();}channel.basicNack(tag,false,true);}
    }
}
