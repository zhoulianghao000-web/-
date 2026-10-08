package cn.pawday.support;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import org.springframework.stereotype.Service;
@Service
public class NotificationService {
 public static final List<String> CATEGORIES=List.of("ORDER","AFTERSALE","PRICE_DROP","RESTOCK","FOOD_REMINDER","ACTIVITY","SUPPORT");
 private final PublishingSupport p;private final IdempotentCommandExecutor commands;
 public NotificationService(PublishingSupport p,IdempotentCommandExecutor commands){this.p=p;this.commands=commands;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER)throw new Failure(403,"PERMISSION_DENIED");}
 public List<Map<String,Object>> preferences(Actor a){consumer(a);return CATEGORIES.stream().map(c->Map.<String,Object>of("category",c,"enabled",enabled(a.principalId(),c))).toList();}
 public boolean enabled(UUID owner,String category){var values=p.db.queryForList("SELECT enabled FROM notification_preferences WHERE principal_id=? AND category=?",Boolean.class,owner,category);return values.isEmpty()||values.getFirst();}
 public Map<String,Object> preference(Actor a,String category,Map<String,Object>b,String key){consumer(a);fields(b,"enabled");boolean value=bool(b.get("enabled"));if(!CATEGORIES.contains(category))throw new Failure(400,"VALIDATION_ERROR");return commands.command(a,"notification.preference:"+category,key,b,()->{p.db.update("INSERT INTO notification_preferences(principal_id,category,enabled) VALUES (?,?,?) ON CONFLICT(principal_id,category) DO UPDATE SET enabled=excluded.enabled,updated_at=clock_timestamp()",a.principalId(),category,value);return Map.of("category",category,"enabled",value);});}
 public List<Map<String,Object>> list(Actor a,UUID after,int limit,String category){consumer(a);limit(limit);if(category!=null&&!CATEGORIES.contains(category))throw new Failure(400,"VALIDATION_ERROR");return p.db.queryForList("SELECT id,category,event_type,target_type,target_id,notify_enabled,read_at,created_at FROM notification_messages WHERE principal_id=? AND (?::uuid='00000000-0000-0000-0000-000000000000' OR (created_at,id)<(SELECT created_at,id FROM notification_messages WHERE id=? AND principal_id=?)) AND (?::varchar IS NULL OR category=?) ORDER BY created_at DESC,id DESC LIMIT ?",a.principalId(),after,after,a.principalId(),category,category,limit+1).stream().map(p::view).toList();}
 public Map<String,Object> read(Actor a,UUID mid,String key){consumer(a);p.one("SELECT id FROM notification_messages WHERE id=? AND principal_id=?",mid,a.principalId());commands.command(a,"notification.read:"+mid,key,Map.of("id",mid.toString()),()->{p.db.update("UPDATE notification_messages SET read_at=coalesce(read_at,clock_timestamp()) WHERE id=? AND principal_id=?",mid,a.principalId());return Map.of("id",mid.toString());});return p.view(p.one("SELECT id,category,event_type,target_type,target_id,notify_enabled,read_at,created_at FROM notification_messages WHERE id=? AND principal_id=?",mid,a.principalId()));}
 public Map<String,Object> unread(Actor a){consumer(a);return Map.of("unread_count",p.db.queryForObject("SELECT count(*) FROM notification_messages WHERE principal_id=? AND read_at IS NULL",Long.class,a.principalId()));}
 public Map<String,Object> target(Actor a,UUID mid){consumer(a);var row=p.one("SELECT target_type,target_id FROM notification_messages WHERE id=? AND principal_id=?",mid,a.principalId());UUID target=(UUID)row.get("target_id");String type=row.get("target_type").toString(),destination;
  if(type.equals("CONVERSATION")){p.one("SELECT id FROM conversations WHERE id=? AND consumer_id=?",target,a.principalId());destination="/conversation?id="+target;}
  else if(type.equals("ORDER")){p.one("SELECT id FROM orders WHERE id=? AND user_id=?",target,a.userId());destination="/orders?id="+target;}
  else{var aftersale=p.one("SELECT order_id FROM aftersales WHERE id=? AND user_id=?",target,a.userId());destination="/orders?id="+aftersale.get("order_id");}
  return Map.of("destination",destination);
 }
}
