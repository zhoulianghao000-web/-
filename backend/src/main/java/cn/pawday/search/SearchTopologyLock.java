package cn.pawday.search;
import java.sql.Connection;
import javax.sql.DataSource;
import org.springframework.stereotype.Component;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
/** A short session advisory lock coordinates bootstrap/cutover across JVMs, with no business transaction open during HTTP. */
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class SearchTopologyLock {
    private final DataSource source;
    public SearchTopologyLock(DataSource source){this.source=source;}
    public AutoCloseable acquire(){
        Connection connection=null;
        try {connection=source.getConnection();connection.setAutoCommit(true);try(var statement=connection.prepareStatement("SELECT pg_try_advisory_lock(hashtextextended('pawday-search-topology',0))")){var result=statement.executeQuery();result.next();if(!result.getBoolean(1)){connection.close();throw new OpenSearchClient.Unavailable("SEARCH_TOPOLOGY_BUSY");}}
            final Connection held=connection;return ()->{try(var statement=held.prepareStatement("SELECT pg_advisory_unlock(hashtextextended('pawday-search-topology',0))")){statement.execute();}finally{held.close();}};
        }catch(OpenSearchClient.Unavailable busy){throw busy;}catch(Exception e){if(connection!=null)try{connection.close();}catch(Exception ignored){}throw new OpenSearchClient.Unavailable("SEARCH_COORDINATION_UNAVAILABLE");}
    }
}
