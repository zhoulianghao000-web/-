package cn.pawday.care;
import cn.pawday.audit.AuditWriter;
import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api.Failure;
import cn.pawday.common.IdempotentCommandExecutor;
import cn.pawday.identity.Actor;
import cn.pawday.publishing.PublishingSupport;
import static cn.pawday.publishing.PublishingSupport.*;
import java.util.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Service;
@Service
public class FavoriteService {
 private final PublishingSupport p;private final IdempotentCommandExecutor commands;private final ConsumerCatalogService catalog;private final AuditWriter audit;
 public FavoriteService(PublishingSupport p,IdempotentCommandExecutor commands,ConsumerCatalogService catalog,AuditWriter audit){this.p=p;this.commands=commands;this.catalog=catalog;this.audit=audit;}
 private void consumer(Actor a){if(a.realm()!=Actor.Realm.CONSUMER||a.userId()==null)throw new Failure(403,"PERMISSION_DENIED");}
 private Map<String,Object> view(Map<String,Object>row){boolean product=row.get("spu_id")!=null;UUID target=(UUID)row.get(product?"spu_id":"store_id");List<Map<String,Object>> current=product?p.db.queryForList("SELECT DISTINCT p.name FROM spus p JOIN skus k ON k.spu_id=p.id JOIN sku_standard_versions v ON v.sku_id=k.id AND v.status='PUBLISHED' JOIN brands b ON b.id=p.brand_id WHERE p.id=? AND p.status='ACTIVE' AND k.status='ACTIVE' AND b.status='ACTIVE'",target):p.db.queryForList("SELECT s.name FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id JOIN nearby_store_profile n ON n.store_id=s.id WHERE s.id=? AND m.status='ACTIVE' AND n.publication_status='PUBLISHED'",target);return Map.of("id",row.get("id"),"kind",product?"PRODUCT":"STORE","target_id",target,"name",current.isEmpty()?"已不可用":current.getFirst().get("name"),"available",!current.isEmpty(),"created_at",p.view(row).get("created_at"));}
 public List<Map<String,Object>> list(Actor a,UUID after,int limit){consumer(a);limit(limit);return p.db.queryForList("SELECT * FROM consumer_favorites WHERE user_id=? AND active AND id>? ORDER BY id LIMIT ?",a.userId(),after,limit+1).stream().map(this::view).toList();}
 public Map<String,Object> save(Actor a,Map<String,Object>b,String key,HttpServletRequest r){consumer(a);fields(b,"kind","target_id");String kind=text(b.get("kind"),10);if(!Set.of("PRODUCT","STORE").contains(kind))throw new Failure(400,"VALIDATION_ERROR");UUID target=id(b.get("target_id"));return commands.command(a,"favorite.save",key,b,()->{boolean product=kind.equals("PRODUCT");if(product)catalog.product(target);else p.one("SELECT s.id FROM merchant_store s JOIN merchant m ON m.id=s.merchant_id JOIN nearby_store_profile n ON n.store_id=s.id WHERE s.id=? AND m.status='ACTIVE' AND n.publication_status='PUBLISHED'",target);p.db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.userId()+":"+kind+":"+target);String column=product?"spu_id":"store_id";var rows=p.db.queryForList("SELECT * FROM consumer_favorites WHERE user_id=? AND "+column+"=? FOR UPDATE",a.userId(),target);UUID fid=rows.isEmpty()?UUID.randomUUID():(UUID)rows.getFirst().get("id");if(rows.isEmpty())p.db.update("INSERT INTO consumer_favorites(id,user_id,"+column+") VALUES (?,?,?)",fid,a.userId(),target);else p.db.update("UPDATE consumer_favorites SET active=true,updated_at=clock_timestamp() WHERE id=?",fid);audit.write(a,"favorite.save","FAVORITE",fid.toString(),Map.of(),Map.of("kind",kind),r);return view(p.one("SELECT * FROM consumer_favorites WHERE id=?",fid));});}
 public Map<String,Object> remove(Actor a,UUID fid,String key,HttpServletRequest r){consumer(a);return commands.command(a,"favorite.remove:"+fid,key,Map.of(),()->{p.one("SELECT id FROM consumer_favorites WHERE id=? AND user_id=? FOR UPDATE",fid,a.userId());p.db.update("UPDATE consumer_favorites SET active=false,updated_at=clock_timestamp() WHERE id=?",fid);audit.write(a,"favorite.remove","FAVORITE",fid.toString(),Map.of(),Map.of("active",false),r);return Map.of("id",fid,"active",false);});}
}
