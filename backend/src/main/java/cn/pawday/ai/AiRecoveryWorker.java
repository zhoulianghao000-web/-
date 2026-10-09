package cn.pawday.ai;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@Component @ConditionalOnProperty(name="pawday.ai.worker-enabled",havingValue="true",matchIfMissing=true)
public class AiRecoveryWorker {
 private final AiQuotaService quota;
 public AiRecoveryWorker(AiQuotaService quota){this.quota=quota;}
 @Scheduled(fixedDelayString="${pawday.ai.recovery-delay-ms:5000}")void recover(){quota.sweep();}
}
