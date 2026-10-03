package cn.pawday.storage;

import java.nio.file.Path;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;

@Configuration
public class StorageConfiguration {
    @Bean @ConditionalOnMissingBean(ObjectStorageProvider.class)
    ObjectStorageProvider objectStorage(Environment env) {
        String kind=env.getProperty("pawday.storage.provider","local");
        if(!kind.equals("local"))throw new IllegalStateException("Configure an ObjectStorageProvider bean for "+kind);
        if(java.util.Arrays.asList(env.getActiveProfiles()).contains("production"))throw new IllegalStateException("The local object adapter is development-only; configure the production ObjectStorageProvider");
        return new LocalObjectStorageProvider(Path.of(env.getProperty("pawday.storage.local-root",".local-media")));
    }
}
