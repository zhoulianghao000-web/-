package cn.pawday.search;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class IndexBootstrap {
    private final OpenSearchClient client;private final AliasManager aliases;private final JdbcTemplate db;private final TransactionTemplate tx;private final SearchTopologyLock coordination;
    public IndexBootstrap(OpenSearchClient client,AliasManager aliases,JdbcTemplate db,TransactionTemplate tx,SearchTopologyLock coordination){this.client=client;this.aliases=aliases;this.db=db;this.tx=tx;this.coordination=coordination;}
    public synchronized String initialize() {
        try(var held=coordination.acquire()){
        String current=aliases.current();
        if(current==null) {
            if(db.queryForObject("SELECT count(*) FROM search_index_version WHERE status='ACTIVE'",Integer.class)>0)throw new OpenSearchClient.Unavailable("SEARCH_ALIAS_MISSING_REBUILD_REQUIRED");
            IndexVersion.ensure(client,IndexVersion.INITIAL);aliases.switchTo(IndexVersion.INITIAL);current=IndexVersion.INITIAL;
        }
        IndexVersion.validate(client,current);final String selected=current;
        tx.executeWithoutResult(s->{
            db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended('pawday-search-bootstrap',0))");
            db.update("UPDATE search_index_version SET status='RETIRED' WHERE status='ACTIVE' AND index_name<>?",selected);
            db.update("INSERT INTO search_index_version(index_name,schema_version,status,activated_at) VALUES (?,?,'ACTIVE',clock_timestamp()) ON CONFLICT(index_name) DO UPDATE SET status='ACTIVE',activated_at=coalesce(search_index_version.activated_at,excluded.activated_at)",selected,IndexVersion.SCHEMA);
            SearchTasks.seed(db,selected,null);
        });return current;
        }catch(OpenSearchClient.Unavailable e){throw e;}catch(Exception e){throw new OpenSearchClient.Unavailable("SEARCH_BOOTSTRAP_FAILURE");}
    }
}
