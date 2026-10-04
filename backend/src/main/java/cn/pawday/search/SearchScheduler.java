package cn.pawday.search;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchScheduler {
    private final IndexBootstrap bootstrap;private final SearchSyncWorker sync;private final SearchRebuildWorker rebuild;private final boolean enabled;private boolean initialized;
    public SearchScheduler(IndexBootstrap bootstrap,SearchSyncWorker sync,SearchRebuildWorker rebuild,@Value("${pawday.search.workers-enabled:true}")boolean enabled){this.bootstrap=bootstrap;this.sync=sync;this.rebuild=rebuild;this.enabled=enabled;}
    @Scheduled(fixedDelayString="${pawday.search.poll-ms:1000}") public void deliver(){if(!enabled)return;try{if(!initialized){bootstrap.initialize();initialized=true;}for(int i=0;i<32&&sync.runOne();i++){}rebuild.runOne();}catch(org.springframework.dao.DataAccessException|OpenSearchClient.Unavailable transientFailure){/* DB tasks remain durable; health indicator exposes service failure. */}}
}
