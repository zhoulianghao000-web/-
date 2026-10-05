package cn.pawday.ordering;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component public class OrderExpiryWorker {
 private final cn.pawday.payment.PaymentService payments;private final OrderService service;private final boolean enabled;
 public OrderExpiryWorker(cn.pawday.payment.PaymentService payments,OrderService service,@Value("${pawday.ordering.expiry-enabled:true}")boolean enabled){this.payments=payments;this.service=service;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.ordering.expiry-ms:30000}")public void sweep(){if(enabled){payments.recoverBatch();service.expireBatch();}}
}
