package cn.pawday.search;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
/** Bounded, restart-safe sweep of existing facts and tombstones; no OpenSearch calls. */
@Component @ConditionalOnProperty(name="pawday.search.enabled",havingValue="true",matchIfMissing=true)
public class BusinessProjectionReconciler {
 private final JdbcTemplate db;private final BusinessSearchProjection projection;private final boolean enabled;
 private UUID cursor=new UUID(0,0);
 public BusinessProjectionReconciler(JdbcTemplate db,BusinessSearchProjection projection,@Value("${pawday.search.workers-enabled:true}") boolean enabled){this.db=db;this.projection=projection;this.enabled=enabled;}
 @Scheduled(fixedDelayString="${pawday.search.business-reconcile-ms:30000}") public synchronized void sweep(){if(!enabled)return;try{
  var rows=db.queryForList("SELECT id FROM skus WHERE id>? ORDER BY id LIMIT 100",cursor);
  for(var row:rows){UUID id=(UUID)row.get("id");projection.refresh(id,"CatalogPublished",null);cursor=id;}
  if(rows.size()<100)cursor=new UUID(0,0);
 }catch(org.springframework.dao.DataAccessException unavailable){/* Last successful cursor retained; next sweep retries. */}}
}
