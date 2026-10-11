package cn.pawday.pilot;

import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.common.Api;
import cn.pawday.identity.AccessGuard;
import cn.pawday.storage.ObjectStorageProvider;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

/** Invited consumers read only the current published snapshot's fixed media reference. */
@RestController
@Profile("local & pilot & !production")
@ConditionalOnProperty(name="pawday.demo.enabled",havingValue="true")
@RequestMapping("/api/v1/consumer/pilot")
public class PilotMediaController {
 private final PilotBaselineInitializer baseline;private final ConsumerCatalogService catalog;private final JdbcTemplate db;
 private final ObjectStorageProvider storage;private final AccessGuard guard;
 public PilotMediaController(PilotBaselineInitializer baseline,ConsumerCatalogService catalog,JdbcTemplate db,ObjectStorageProvider storage,AccessGuard guard){this.baseline=baseline;this.catalog=catalog;this.db=db;this.storage=storage;this.guard=guard;}
 @GetMapping("/baseline") Object baseline(HttpServletRequest r){guard.actor();return Api.ok(baseline.summary(),r);}
 @GetMapping("/skus/{sku_id}/media") ResponseEntity<InputStreamResource> media(@PathVariable UUID sku_id){
  guard.actor();var sku=catalog.sku(sku_id);int n=PilotMaterials.number(sku_id);
  if(n==0||!PilotMaterials.id("standard-"+n).equals(sku.get("catalog_standard_version_id"))||!((List<?>)sku.get("source_refs")).contains("pawday-pilot-media:"+PilotMaterials.media(n)))throw new Api.Failure(404,"RESOURCE_NOT_FOUND");
  var rows=db.queryForList("SELECT a.object_key,a.mime,a.size_bytes,a.sha256 FROM media_asset a JOIN merchant_store s ON s.id=a.store_id JOIN merchant m ON m.id=s.merchant_id JOIN identity_principal p ON p.id=a.owner_id WHERE a.id=? AND a.status='READY' AND a.scope='PRODUCT' AND a.storage_provider=? AND a.store_id=? AND a.owner_id=? AND m.status='ACTIVE' AND p.status='ACTIVE'",PilotMaterials.media(n),storage.providerId(),PilotMaterials.demo("store-"+(n%2==1?"a":"b")),PilotMaterials.demo("staff-"+(n%2==1?"a":"b")));
  if(rows.isEmpty())throw new Api.Failure(404,"RESOURCE_NOT_FOUND");var row=rows.getFirst();String key=row.get("object_key").toString();var meta=storage.metadata(key).orElseThrow(()->new Api.Failure(404,"RESOURCE_NOT_FOUND"));
  if(!meta.sha256().equals(row.get("sha256"))||meta.sizeBytes()!=((Number)row.get("size_bytes")).longValue())throw new Api.Failure(503,"OBJECT_STORAGE_UNAVAILABLE");
  return ResponseEntity.ok().contentType(MediaType.IMAGE_PNG).contentLength(meta.sizeBytes()).header("X-Content-Type-Options","nosniff").header("Cache-Control","no-store").body(new InputStreamResource(storage.read(key)));
 }
}
