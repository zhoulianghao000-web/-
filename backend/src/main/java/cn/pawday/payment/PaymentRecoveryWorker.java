package cn.pawday.payment;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component public class PaymentRecoveryWorker {
 private final PaymentService service;private final boolean enabled;
 public PaymentRecoveryWorker(PaymentService service,@Value("${pawday.payment.recovery-enabled:true}")boolean enabled){this.service=service;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.payment.recovery-ms:5000}")public void sweep(){if(enabled)service.recoverBatch();}
}
