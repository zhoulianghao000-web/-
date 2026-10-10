package cn.pawday.privacy;

import java.nio.file.Path;
import java.time.Clock;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

@Component
@ConditionalOnProperty(name="pawday.privacy.export-enabled",havingValue="true")
public final class PrivacyExportScheduler {
    private final PrivacyExportService service;
    public PrivacyExportScheduler(JdbcTemplate db,TransactionTemplate tx,Clock clock,
        @Value("${pawday.privacy.export-root}") String root,@Value("${pawday.storage.local-root:.local-media}") String media,
        @Value("${pawday.privacy.export-signing-key}") String signingKey) {
        var export=Path.of(root).toAbsolutePath().normalize();var objects=Path.of(media).toAbsolutePath().normalize();
        if(export.startsWith(objects)||objects.startsWith(export))throw new IllegalArgumentException("INDEPENDENT_EXPORT_ROOT_REQUIRED");
        byte[] key=Base64.getDecoder().decode(signingKey);
        service=new PrivacyExportService(db,tx,new LocalPrivacyExportProvider(export,key),key,clock,60);
    }
    @Scheduled(fixedDelayString="${pawday.privacy.export-poll-ms:1000}") public void poll(){service.runOne();}
}
