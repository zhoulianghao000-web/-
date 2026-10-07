package cn.pawday.membership;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component public class MembershipWorker {
 private final MembershipService service;private final boolean enabled;
 public MembershipWorker(MembershipService service,@Value("${pawday.membership.worker-enabled:true}")boolean enabled){this.service=service;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.membership.expiry-ms:30000}")public void sweep(){if(enabled)service.expireBatch();}
}
