package cn.pawday.outbox;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.*;
@Configuration @EnableScheduling
@ConditionalOnProperty(name="pawday.outbox.workers-enabled",havingValue="true",matchIfMissing=true)
public class DeliveryScheduler {
    private final OutboxPublisher publisher;private final SmsDeliveryWorker sms;
    public DeliveryScheduler(OutboxPublisher publisher,SmsDeliveryWorker sms){this.publisher=publisher;this.sms=sms;}
    @Scheduled(fixedDelayString="${pawday.outbox.poll-ms:500}") public void publish(){for(int i=0;i<16 && publisher.publishOne();i++) {} }
    @Scheduled(fixedDelayString="${pawday.outbox.poll-ms:500}") public void sendSms(){for(int i=0;i<16 && sms.sendOne();i++) {} }
    @Scheduled(fixedDelay=60000) public void expireOtpMaterial(){sms.expireSecrets();}
}
