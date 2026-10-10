package cn.pawday;

import cn.pawday.catalog.ConsumerCatalogService;
import cn.pawday.identity.*;
import cn.pawday.outbox.OutboxWriter;
import cn.pawday.search.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

/** Test-only offline probe. No Spring context, HTTP server, Rabbit listener or scheduler. */
public final class RecoverySearchProbe {
 static UUID id(int n){return UUID.fromString("63000000-0000-4000-8000-"+String.format("%012d",n));}
 static void require(boolean b,String code){if(!b)throw new IllegalStateException(code);}
 static String hash(byte[] value){try{return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(value));}catch(Exception e){throw new IllegalStateException("HASH_UNAVAILABLE");}}
 public static void main(String[] args)throws Exception {
  require(args.length==2&&args[0].equals("--test-only"),"TEST_ONLY_REQUIRED");
  String action=args[1],host=System.getenv("M63_TARGET");require(Set.of("postgres","recovered-postgres").contains(host),"NON_FIXTURE_TARGET_REFUSED");
  require(Set.of("seed","privacy","export","export-failure").contains(action)==host.equals("postgres"),"NON_FIXTURE_ACTION_REFUSED");
  String url="jdbc:postgresql://"+host+":5432/pawday_recovery_test";
  // Every new helper connection opts into sandbox review writes. No pool/app is started.
  if(host.equals("recovered-postgres"))url+="?options=-c%20default_transaction_read_only%3Doff";
  var ds=new DriverManagerDataSource(url,"pawday_recovery_test","TEST_ONLY_M63");
  var db=new JdbcTemplate(ds);db.setQueryTimeout(10);var tx=new TransactionTemplate(new DataSourceTransactionManager(ds));
  var writer=new OutboxWriter(db);var source=new CatalogSearchSource(db,tx,writer);var catalog=new ConsumerCatalogService(db,null,tx);var projection=new BusinessSearchProjection(db,source,catalog,tx);
  var client=new OpenSearchClient("http://opensearch:9200",1000,"","");var aliases=new AliasManager(client);var lock=new SearchTopologyLock(ds);
  var policy=new SearchDeliveryPolicy(5,50,30000);var sync=new SearchSyncWorker(db,tx,client,policy,writer);
  var crypto=new Crypto(Base64.getEncoder().encodeToString(new byte[32]),Clock.systemUTC(),new DataEncryptionKeyRing("legacy",""));
  var rebuild=new SearchRebuildWorker(db,tx,client,aliases,sync,policy,crypto,writer,lock);
  if(action.equals("seed")){
   tx.executeWithoutResult(s->{
    db.execute("CREATE TABLE m63_fixture (singleton boolean PRIMARY KEY CHECK(singleton),privacy_reviewed boolean NOT NULL DEFAULT false,registry_hash varchar(64))");db.update("INSERT INTO m63_fixture(singleton) VALUES (true)");
    db.update("INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES (?,'ADMIN','TEST_ONLY_M63','TEST_ONLY',?)",id(1),crypto.encrypt(new byte[20]));
    db.update("INSERT INTO app_user(id,status,display_name) VALUES (?,'ACTIVE','TEST_ONLY')",id(2));
    db.update("INSERT INTO merchant VALUES (?,'TEST_ONLY','ACTIVE')",id(3));
    db.update("INSERT INTO brands VALUES (?,'TEST_ONLY_M63','TEST_ONLY','ACTIVE')",id(4));
    db.update("INSERT INTO spus(id,brand_id,name,pet_category,category) VALUES (?,?,'TEST_ONLY','CAT','DRY_FOOD')",id(5),id(4));
    for(int k:List.of(6,7)){
     db.update("INSERT INTO skus(id,spu_id,sku_code,weight_g,package_unit) VALUES (?,?,?,100,'BAG')",id(k),id(5),"TEST_ONLY_"+k);
     db.update("INSERT INTO sku_standard_versions(id,sku_id,version_no,status,ingredients,nutrients,allergens_known,life_stage_ids,source_refs,source_updated_on,created_by,published_at) VALUES (?,?,1,'PUBLISHED','[]','[]',false,'[]','[\"TEST_ONLY\"]',current_date,?,now())",id(k+10),id(k),id(1));
     db.update("INSERT INTO offers(id,merchant_id,sku_id,sale_price_fen,fulfillment_sla,sale_status) VALUES (?,?,?,1000,'TEST_ONLY','ACTIVE')",id(k+20),id(3),id(k));
     db.update("INSERT INTO inventory_balances(offer_id,on_hand_qty) VALUES (?,10)",id(k+20));
    }
    db.update("UPDATE skus SET status='RETIRED' WHERE id=?",id(7));
    db.update("INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,source_event,created_by_type) VALUES (?,?,'MANUAL_ADJUSTMENT','CREDIT',12345,true,'TEST_ONLY_M63','SYSTEM')",id(30),id(3));
    db.update("INSERT INTO processed_event(consumer,event_id,status,payload_hash) VALUES ('TEST_ONLY_M63',?,'PROCESSED',?)",id(31),"b".repeat(64));
    writer.append("TEST_ONLY",id(2).toString(),"OtpSmsRequested",1,Map.of("challenge_id",id(32).toString()),null);
    db.update("INSERT INTO ai_preferences(user_id,personalization_enabled) VALUES (?,true)",id(2));
    for(int c:List.of(40,41)){
     db.update("INSERT INTO ai_conversations(id,user_id,expires_at) VALUES (?,?,now()+(?*interval '1 second'))",id(c),id(2),c==40?3600:1);
     db.update("INSERT INTO ai_requests(id,user_id,conversation_id,idempotency_key,payload_hash,preference_version,prompt_id,policy_id) VALUES (?,?,?,?,?,0,'55000000-0000-4000-8000-000000000002','55000000-0000-4000-8000-000000000001')",id(c+10),id(2),id(c),"TEST_ONLY_"+c,"c".repeat(64));
     db.update("INSERT INTO ai_messages(id,conversation_id,user_text_ciphertext,result_ciphertext) VALUES (?,?,?,?)",id(c+10),id(c),crypto.encrypt(new byte[20]),crypto.encrypt(new byte[20]));
    }
    db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'TEST_ONLY',now()+interval '1 hour',now()+interval '1 day',now())",id(60),id(1),"d".repeat(64));
    byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5N8AAAAASUVORK5CYII=");
    String hash=hash(png);
    for(int a:List.of(61,62))db.update("INSERT INTO media_asset(id,owner_id,realm,owner_session_id,scope,storage_provider,object_key,mime,size_bytes,sha256,status,upload_expires_at,next_cleanup_at,created_at,updated_at) VALUES (?,?,'ADMIN',?,'CHAT','local',?,'image/png',?,?,'READY',now(),now(),now(),now())",id(a),id(1),id(60),"media/"+id(a)+".png",png.length,hash);
   });
   // Deliberately stale derived rows must be rebuilt from catalog/offer facts.
   for(int k:List.of(6,7))source.change(new CatalogSearchSource.Product(id(5),id(k),"STALE_BACKUP_VALUE","CAT","MULTIPLE_OR_UNKNOWN","DRY_FOOD",List.of(),1,false,0,Instant.now()),false,"CatalogPublished",null);
   new IndexBootstrap(client,aliases,db,tx,lock).initialize();while(sync.runOne()){}
  }else if(action.equals("privacy")){
   var p=new cn.pawday.publishing.PublishingSupport(db,null);var quota=new cn.pawday.ai.AiQuotaService(p,tx,Clock.systemUTC());var audit=new cn.pawday.audit.AuditWriter(db);
   db.update("INSERT INTO identity_principal(id,realm,user_id) VALUES (?,'CONSUMER',?)",id(80),id(2));
   db.update("INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES (?,?,?,'TEST_ONLY',now()+interval '1 hour',now()+interval '1 day',now())",id(81),id(80),"e".repeat(64));
   var actor=new Actor(id(80),Actor.Realm.CONSUMER,id(2),null,id(81),Set.of(),Set.of());
   var unavailable=new cn.pawday.ai.ExplanationProvider(){public Plan explain(String instruction,List<Map<String,Object>> evidence){throw new IllegalStateException("NO_EXTERNAL_PROVIDER");}public boolean available(){return false;}};
   var ai=new cn.pawday.ai.AiService(p,quota,null,unavailable,crypto,new cn.pawday.common.IdempotentCommandExecutor(db,tx,crypto),audit,null);
   ai.clear(actor,id(40),"TEST_ONLY_M64_DELETE",null);ai.preference(actor,Map.of("personalization_enabled",false),"\"0\"","TEST_ONLY_M64_REVOKE",null);quota.sweep();
   var owner=new Actor(id(1),Actor.Realm.ADMIN,null,null,id(60),Set.of(),Set.of());
   org.springframework.security.core.context.SecurityContextHolder.getContext().setAuthentication(new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(owner,null,List.of()));
   try{new cn.pawday.storage.MediaService(db,tx,new AccessGuard(db),crypto,audit,Clock.systemUTC(),new cn.pawday.storage.LocalObjectStorageProvider(java.nio.file.Path.of("/live-media")),5242880,300,60).delete(id(62),null);}
   finally{org.springframework.security.core.context.SecurityContextHolder.clearContext();}
   require(db.queryForObject("SELECT count(*) FROM privacy_journal",Integer.class)==4,"ONLINE_PRIVACY_FACTS_MISSING");
  }else if(action.startsWith("export")){
   byte[] signing="TEST_ONLY_M64_PRIVATE_EXPORT_32_BYTES".getBytes(java.nio.charset.StandardCharsets.UTF_8);
   java.nio.file.Path directory=java.nio.file.Path.of("/independent-privacy");
   if(action.equals("export-failure")){directory=directory.resolve("TEST_ONLY_BLOCKED");java.nio.file.Files.writeString(directory,"NOT_A_DIRECTORY");}
   db.update("UPDATE privacy_export_state SET next_attempt_at=now()-interval '1 second'");
   new cn.pawday.privacy.PrivacyExportService(db,tx,new cn.pawday.privacy.LocalPrivacyExportProvider(directory,signing),signing,Clock.systemUTC(),60).runOne();
   require((db.queryForObject("SELECT last_error_code FROM privacy_export_state",String.class)==null)==action.equals("export"),"EXPORT_RESULT_MISMATCH");
  }else{
   require(Boolean.TRUE.equals(db.queryForObject("SELECT privacy_reviewed FROM m63_fixture",Boolean.class)),"PRIVACY_REVIEW_REQUIRED");
   if(action.equals("prepare")){
    for(var row:db.queryForList("SELECT id FROM skus ORDER BY id"))projection.refresh((UUID)row.get("id"),"CatalogPublished",null);
    db.update("INSERT INTO search_rebuild_job(target_index) VALUES ('pawday-product-v1-m63-recovered')");
   }else if(action.equals("retry")){
    rebuild.runOne();require(db.queryForObject("SELECT count(*) FROM search_rebuild_job WHERE status='FAILED_RETRYABLE'",Integer.class)==1,"FAILED_REBUILD_NOT_RETRYABLE");
   }else if(action.equals("finish")){
    long deadline=System.nanoTime()+Duration.ofSeconds(20).toNanos();
    while(!"pawday-product-v1-m63-recovered".equals(aliases.current())&&System.nanoTime()<deadline){rebuild.runOne();Thread.sleep(100);}
    require("pawday-product-v1-m63-recovered".equals(aliases.current()),"ALIAS_NOT_SWITCHED");
    var docs=client.documents(aliases.current());require(docs.size()==2&&Boolean.TRUE.equals(docs.get(id(7)).get("deleted")),"RETIRED_SKU_RESURRECTED");
    var d=docs.get(id(6));require("TEST_ONLY_M63".equals(d.get("brand"))&&((Number)d.get("price_min_fen")).longValue()==2000&&Boolean.TRUE.equals(d.get("in_stock")),"FACT_DERIVATION_MISMATCH");
    require(((Number)client.request("GET","/pawday-product-read/_count",null).get("count")).intValue()==1,"PUBLIC_ALIAS_TOMBSTONE_FILTER_FAILED");
    require(crypto.decrypt(db.queryForObject("SELECT mfa_secret_ciphertext FROM identity_principal WHERE id=?",String.class,id(1))).length==20,"RESTORED_CIPHER_FAILURE");
   }else throw new IllegalArgumentException("UNKNOWN_ACTION");
  }
  System.out.println(new JsonMapper().writeValueAsString(Map.of("result","PASS","action",action,"test_only",true)));
 }
}
