package cn.pawday.storage;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component
@ConditionalOnProperty(name="pawday.storage.cleanup-enabled",havingValue="true",matchIfMissing=true)
public class MediaRecoveryScheduler {
    private final MediaService service;
    public MediaRecoveryScheduler(MediaService service){this.service=service;}
    @Scheduled(fixedDelayString="${pawday.storage.cleanup-delay-ms:30000}")
    public void cleanup(){service.recover();}
}
