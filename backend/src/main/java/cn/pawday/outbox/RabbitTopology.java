package cn.pawday.outbox;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.context.annotation.*;
import org.springframework.beans.factory.InitializingBean;
@Configuration
public class RabbitTopology {
    public static final String SUPPORT_QUEUE="pawday.support.notifications";
    public static final String SEARCH_QUEUE="pawday.search";
    public static final String OFFER_FACT_QUEUE="pawday.offer.facts";
    public static final String CATALOG_STANDARD_QUEUE="pawday.catalog.standard-published";
    public static final String EXCHANGE="pawday.events",QUEUE="pawday.otp.sms",DLX="pawday.dead",DLQ="pawday.dead.delivery";
    @Bean Declarables deliveryTopology(){
        var exchange=new DirectExchange(EXCHANGE,true,false);var dead=new DirectExchange(DLX,true,false);
        var queue=QueueBuilder.durable(QUEUE).quorum().deadLetterExchange(DLX).deadLetterRoutingKey("dead").withArgument("x-dead-letter-strategy","at-least-once").withArgument("x-overflow","reject-publish").withArgument("x-delivery-limit",-1).build();
        var dlq=QueueBuilder.durable(DLQ).quorum().build();
        // Keep standard facts durably until M3.4 installs the catalog projection consumer.
        var offerQueue=QueueBuilder.durable(OFFER_FACT_QUEUE).quorum().build();
        var orderQueue=QueueBuilder.durable("pawday.order.facts").quorum().build();
        var paymentQueue=QueueBuilder.durable("pawday.payment.facts").quorum().build();
        var businessQueue=QueueBuilder.durable("pawday.business.facts").quorum().build();
        var catalogQueue=QueueBuilder.durable(CATALOG_STANDARD_QUEUE).quorum().build();
        var searchQueue=QueueBuilder.durable(SEARCH_QUEUE).quorum().deadLetterExchange(DLX).deadLetterRoutingKey("dead").withArgument("x-dead-letter-strategy","at-least-once").withArgument("x-overflow","reject-publish").withArgument("x-delivery-limit",-1).build();
        var supportQueue=QueueBuilder.durable(SUPPORT_QUEUE).quorum().deadLetterExchange(DLX).deadLetterRoutingKey("dead").withArgument("x-dead-letter-strategy","at-least-once").withArgument("x-overflow","reject-publish").withArgument("x-delivery-limit",-1).build();
        return new Declarables(supportQueue,exchange,dead,queue,searchQueue,dlq,catalogQueue,offerQueue,orderQueue,paymentQueue,businessQueue,
            BindingBuilder.bind(supportQueue).to(exchange).with("SupportMessageCreated"),
BindingBuilder.bind(supportQueue).to(exchange).with("SupportAssigned"),
BindingBuilder.bind(supportQueue).to(exchange).with("OrderCreated"),
BindingBuilder.bind(supportQueue).to(exchange).with("OrderPaid"),
BindingBuilder.bind(supportQueue).to(exchange).with("OrderCancelled"),
BindingBuilder.bind(supportQueue).to(exchange).with("OrderExpired"),
BindingBuilder.bind(supportQueue).to(exchange).with("ShipmentCreated"),
BindingBuilder.bind(supportQueue).to(exchange).with("SuborderReceiptConfirmed"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleCreated"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleMerchantDecision"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleInspected"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleEscalated"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleArbitrated"),
BindingBuilder.bind(supportQueue).to(exchange).with("AfterSaleCompleted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("CancellationRecorded"),
            BindingBuilder.bind(businessQueue).to(exchange).with("CancellationCompleted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("CouponReturned"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleCreated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleMerchantDecision"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleInspected"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleEscalated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleArbitrated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("AfterSaleCompleted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("RefundSucceeded"),
            BindingBuilder.bind(businessQueue).to(exchange).with("RefundFailed"),
            BindingBuilder.bind(businessQueue).to(exchange).with("SettlementEligible"),
            BindingBuilder.bind(businessQueue).to(exchange).with("SettlementCompleted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("SettlementAdjustmentCreated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("MembershipOrderCreated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("MembershipActivated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("MembershipPaymentSucceeded"),
            BindingBuilder.bind(businessQueue).to(exchange).with("PointsChanged"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ReviewSubmitted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ReviewUpdated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ReviewModerated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ReviewPolicyPublished"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticleCreated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticleUpdated"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticleSubmitted"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticlePublished"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticleRejected"),
            BindingBuilder.bind(businessQueue).to(exchange).with("ArticleHidden"),

            BindingBuilder.bind(paymentQueue).to(exchange).with("PaymentAttemptCreated"),
            BindingBuilder.bind(paymentQueue).to(exchange).with("PaymentExceptionRecorded"),
            BindingBuilder.bind(paymentQueue).to(exchange).with("PaymentCompensated"),
            BindingBuilder.bind(orderQueue).to(exchange).with("OrderPaid"),
            BindingBuilder.bind(orderQueue).to(exchange).with("ShipmentCreated"),
            BindingBuilder.bind(orderQueue).to(exchange).with("SuborderReceiptConfirmed"),
            BindingBuilder.bind(offerQueue).to(exchange).with("OfferStateChanged"),
            BindingBuilder.bind(offerQueue).to(exchange).with("InventoryAdjusted"),
            BindingBuilder.bind(offerQueue).to(exchange).with("InventoryReservationChanged"),
            BindingBuilder.bind(orderQueue).to(exchange).with("OrderCreated"),
            BindingBuilder.bind(orderQueue).to(exchange).with("OrderCancelled"),
            BindingBuilder.bind(orderQueue).to(exchange).with("OrderExpired"),
            BindingBuilder.bind(catalogQueue).to(exchange).with("CatalogStandardPublished"),
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
