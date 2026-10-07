package cn.pawday.payment;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component public class RefundRecoveryWorker {
 private final RefundService service;private final boolean enabled;
 public RefundRecoveryWorker(RefundService service,@Value("${pawday.refund.recovery-enabled:true}")boolean enabled){this.service=service;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.refund.recovery-ms:5000}")public void sweep(){if(enabled)service.recoverBatch();}
}
