package cn.pawday.search;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
final class SearchTasks {
    private SearchTasks(){}
    static void enqueue(JdbcTemplate db,UUID source,String target,long revision,UUID event) {
        db.update("""
            INSERT INTO search_sync_task(source_id,target_index,desired_revision,event_id) VALUES (?,?,?,?)
            ON CONFLICT(source_id,target_index) DO UPDATE SET
              desired_revision=greatest(search_sync_task.desired_revision,excluded.desired_revision),
              event_id=CASE WHEN excluded.desired_revision>search_sync_task.desired_revision THEN excluded.event_id ELSE search_sync_task.event_id END,
              status=CASE WHEN search_sync_task.status='SYNCING' THEN 'SYNCING' WHEN excluded.desired_revision>search_sync_task.desired_revision THEN 'PENDING' ELSE search_sync_task.status END,
              attempt_count=CASE WHEN excluded.desired_revision>search_sync_task.desired_revision AND search_sync_task.status<>'SYNCING' THEN 0 ELSE search_sync_task.attempt_count END,
              available_at=CASE WHEN excluded.desired_revision>search_sync_task.desired_revision THEN clock_timestamp() ELSE search_sync_task.available_at END,
              updated_at=clock_timestamp()
            """,source,target,revision,event);
    }
    static void seed(JdbcTemplate db,String index,UUID event) {
        for(var row:db.queryForList("SELECT sku_id,revision FROM catalog_search_source ORDER BY sku_id"))enqueue(db,(UUID)row.get("sku_id"),index,((Number)row.get("revision")).longValue(),event);
    }
    static String rebuildTarget(UUID id){return "pawday-product-v1-"+id.toString().replace("-","");}
}
