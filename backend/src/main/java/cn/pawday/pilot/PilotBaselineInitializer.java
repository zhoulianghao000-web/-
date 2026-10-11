package cn.pawday.pilot;

import cn.pawday.audit.AuditWriter;
import cn.pawday.storage.ObjectStorageProvider;
import cn.pawday.outbox.OutboxWriter;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import org.springframework.boot.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceUtils;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** One baseline per isolated round. Restarts never reset business facts or replenish stock. */
@Component
@Profile("local & pilot & !production")
@ConditionalOnProperty(name="pawday.demo.enabled",havingValue="true")
public class PilotBaselineInitializer implements ApplicationRunner {
 private final JdbcTemplate db;private final TransactionTemplate tx;private final ObjectStorageProvider storage;
 private final AuditWriter audit;private final OutboxWriter outbox;private final PilotPolicy policy;
 public PilotBaselineInitializer(JdbcTemplate db,TransactionTemplate tx,ObjectStorageProvider storage,AuditWriter audit,OutboxWriter outbox,PilotPolicy policy){this.db=db;this.tx=tx;this.storage=storage;this.audit=audit;this.outbox=outbox;this.policy=policy;}
 public static String digest(byte[] bytes){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(Exception e){throw new IllegalStateException(e);}}
 public Map<String,Object> summary(){
  var rows=db.queryForList("SELECT value_json::text FROM operation_config WHERE config_key='PILOT_BASELINE' AND version=1");
  if(rows.isEmpty())throw new cn.pawday.common.Api.Failure(503,"PILOT_BASELINE_NOT_INITIALIZED");
  return JsonMapper.builder().build().readValue(rows.getFirst().get("value_json").toString(),Map.class);
 }
 @Override public void run(ApplicationArguments args) throws Exception {
  if(!policy.enabled()||!"local".equals(storage.providerId()))throw new IllegalStateException("PILOT_BASELINE_REQUIRES_LOCAL_ISOLATION");
  var sql=new ClassPathResource("pilot/cq-v1.sql");byte[] definition=sql.getContentAsByteArray(),manifest=new ClassPathResource("pilot/cq-v1.json").getContentAsByteArray();
  String hash=digest((digest(definition)+digest(manifest)).getBytes(java.nio.charset.StandardCharsets.UTF_8));
  var prior=db.queryForList("SELECT value_json->>'definition_sha256' AS hash FROM operation_config WHERE config_key='PILOT_BASELINE' AND version=1");
  if(!prior.isEmpty()){if(!hash.equals(prior.getFirst().get("hash")))throw new IllegalStateException("PILOT_BASELINE_VERSION_DRIFT");policy.baselineReady();return;}
  // Immutable object writes precede the short facts transaction. A rollback can leave only unreferenced test objects.
  byte[] png=new ClassPathResource("pilot/synthetic.png").getContentAsByteArray();String imageHash=digest(png);
  for(String label:List.of("a","b")){
   String key="media/"+PilotMaterials.id("media-"+label)+".png";
   try{if(storage.metadata(key).isEmpty())storage.put(new ObjectStorageProvider.Put(key,"image/png",png.length,imageHash,5242880),new ByteArrayInputStream(png));}
   catch(cn.pawday.common.Api.Failure e){if(e.status!=409)throw e;}
   var existing=storage.metadata(key).orElseThrow();if(!imageHash.equals(existing.sha256())||existing.sizeBytes()!=png.length)throw new IllegalStateException("PILOT_IMAGE_DRIFT");
  }
  tx.executeWithoutResult(s->{
   db.queryForList("SELECT pg_advisory_xact_lock(hashtextextended('pawday-pilot-baseline',0))");
   var raced=db.queryForList("SELECT value_json->>'definition_sha256' AS hash FROM operation_config WHERE config_key='PILOT_BASELINE' AND version=1");
   if(!raced.isEmpty()){if(!hash.equals(raced.getFirst().get("hash")))throw new IllegalStateException("PILOT_BASELINE_VERSION_DRIFT");return;}
   ScriptUtils.executeSqlScript(DataSourceUtils.getConnection(Objects.requireNonNull(db.getDataSource())),new org.springframework.core.io.support.EncodedResource(sql,java.nio.charset.StandardCharsets.UTF_8));
   for(String label:List.of("a","b")){
    UUID session=PilotMaterials.id("media-session-"+label),owner=PilotMaterials.demo("staff-"+label),asset=PilotMaterials.id("media-"+label);
    // Revoked, expired technical reference; cannot be used to authenticate or upload.
    db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,revoked_at,created_at) VALUES (?,?,?,'SYNTHETIC_MEDIA_REFERENCE',now(),now(),now(),now())",session,owner,digest(UUID.randomUUID().toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)));
    db.update("INSERT INTO media_asset(id,owner_id,realm,owner_session_id,scope,store_id,storage_provider,object_key,mime,size_bytes,sha256,status,upload_expires_at,next_cleanup_at,created_at,updated_at) VALUES (?,?,'MERCHANT',?,'PRODUCT',?,'local',?,'image/png',?,?,'READY',now(),now(),now(),now())",asset,owner,session,PilotMaterials.demo("store-"+label),"media/"+asset+".png",png.length,imageHash);
   }
   var value=Map.of("baseline_version",PilotMaterials.VERSION,"definition_sha256",hash,"merchant_count",2,"store_count",2,"consumer_count",20,"sku_count",20,"generated_fixture",true,"production_approved",false);
   db.update("INSERT INTO operation_config(config_key,version,value_json,status,created_by) VALUES ('PILOT_BASELINE',1,?::jsonb,'SYNTHETIC','M6.6.2')",JsonMapper.builder().build().writeValueAsString(value));
   for(int n=1;n<=20;n++)outbox.append("CATALOG_SKU",PilotMaterials.id("sku-"+n).toString(),"CatalogStandardPublished",1,Map.of("sku_id",PilotMaterials.id("sku-"+n).toString(),"standard_version_id",PilotMaterials.id("standard-"+n).toString()),"pilot-cq-v1");
   audit.write(null,"pilot.baseline.initialized","PILOT_BASELINE",PilotMaterials.VERSION,Map.of(),value,null);
  });
  policy.baselineReady();
 }
}
