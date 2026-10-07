package cn.pawday.settlement;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component public class SettlementWorker {
 private final SettlementService service;private final boolean enabled;
 public SettlementWorker(SettlementService service,@Value("${pawday.settlement.worker-enabled:true}")boolean enabled){this.service=service;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.settlement.sweep-ms:5000}")public void sweep(){if(enabled){service.promoteDue();service.retryFailed();}}
}
