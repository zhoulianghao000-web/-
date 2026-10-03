package cn.pawday.search;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.health.contributor.*;
import org.springframework.stereotype.Component;
@Component("searchHealthIndicator") @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchHealthIndicator implements HealthIndicator {
    private final OpenSearchClient client;private final AliasManager aliases;
    public SearchHealthIndicator(OpenSearchClient client,AliasManager aliases){this.client=client;this.aliases=aliases;}
    public Health health() {
        try {
            var cluster=client.health();var target=aliases.current();
            if("red".equals(cluster.get("status")) || target==null)return Health.down().withDetail("reason_code",target==null?"SEARCH_NOT_INITIALIZED":"SEARCH_CLUSTER_RED").build();
            IndexVersion.validate(client,target);
            return Health.up().withDetail("cluster_status",cluster.get("status")).withDetail("schema_version",IndexVersion.SCHEMA).withDetail("active_index",target).build();
        }catch(OpenSearchClient.Unavailable e){return Health.down().withDetail("reason_code",e.code).build();}
        catch(Exception e){return Health.down().withDetail("reason_code","SEARCH_HEALTH_FAILURE").build();}
    }
}
