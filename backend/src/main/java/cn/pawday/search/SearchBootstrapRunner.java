package cn.pawday.search;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchBootstrapRunner implements ApplicationRunner {
    private final IndexBootstrap bootstrap;
    public SearchBootstrapRunner(IndexBootstrap bootstrap){this.bootstrap=bootstrap;}
    public void run(ApplicationArguments args){try{bootstrap.initialize();}catch(OpenSearchClient.Unavailable unavailable){/* Startup survives search outage; scheduled bootstrap retries. */}}
}
