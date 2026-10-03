package cn.pawday.outbox;
import java.util.UUID;
import org.springframework.stereotype.Component;
@Component
public class OutboxPublisher {
    private final OutboxRepository events;private final RabbitPublisher rabbit;private final String worker="publisher-"+UUID.randomUUID();
    public OutboxPublisher(OutboxRepository events,RabbitPublisher rabbit){this.events=events;this.rabbit=rabbit;}
    public boolean publishOne(){var claim=events.claim(worker);if(claim.isEmpty())return false;
        try {rabbit.publish(claim.get());events.published(claim.get());}
        catch(RabbitPublisher.PublishFailure failure){events.failed(claim.get(),failure.code);}return true;
    }
}
