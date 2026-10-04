package cn.pawday.outbox;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.InitializingBean;
@Configuration
public class RabbitTopology {
    public static final String SEARCH_QUEUE="pawday.search";
    public static final String EXCHANGE="pawday.events",QUEUE="pawday.otp.sms",DLX="pawday.dead",DLQ="pawday.dead.delivery";
    @Bean Declarables deliveryTopology(){
        var exchange=new DirectExchange(EXCHANGE,true,false);var dead=new DirectExchange(DLX,true,false);
        var queue=QueueBuilder.durable(QUEUE).quorum().deadLetterExchange(DLX).deadLetterRoutingKey("dead").withArgument("x-dead-letter-strategy","at-least-once").withArgument("x-overflow","reject-publish").withArgument("x-delivery-limit",-1).build();
        var dlq=QueueBuilder.durable(DLQ).quorum().build();
        var searchQueue=QueueBuilder.durable(SEARCH_QUEUE).quorum().deadLetterExchange(DLX).deadLetterRoutingKey("dead").withArgument("x-dead-letter-strategy","at-least-once").withArgument("x-overflow","reject-publish").withArgument("x-delivery-limit",-1).build();
        return new Declarables(exchange,dead,queue,searchQueue,dlq,
            BindingBuilder.bind(queue).to(exchange).with("otp.sms.requested"),BindingBuilder.bind(dlq).to(dead).with("dead"),
            BindingBuilder.bind(searchQueue).to(exchange).with("CatalogPublished"),
            BindingBuilder.bind(searchQueue).to(exchange).with("OfferChanged"),
            BindingBuilder.bind(searchQueue).to(exchange).with("InventoryAvailabilityChanged"),
            BindingBuilder.bind(searchQueue).to(exchange).with("SearchReindexRequested"));
    }
    @Bean InitializingBean publisherSafety(RabbitTemplate rabbit,CachingConnectionFactory connection){return ()->{
        connection.setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED);connection.setPublisherReturns(true);rabbit.setMandatory(true);
    };}
}
