"""Mandatory physical backup/WAL/PITR + existing search rebuild. Synthetic only.
Fixed source labels. New internal targets/volumes. No runtime app or live workers.
No promotion/deletion command for production. Backups and registry stay private.
"""
import argparse,base64,datetime as dt,hashlib,hmac,json,os,re,secrets,subprocess,time,uuid
from pathlib import Path
from privacy_export_contract import verify_export
from recovery_contract import RecoveryError,bundle_files,validate_bundle,privacy_registry,retention_plan,privacy_replay_sql

ROOT=Path(__file__).resolve().parents[1];LOCAL=ROOT/'.local-recovery';OUT=ROOT/'backend/target/recovery-evidence'
SOURCE='pawday-m63-it-postgres-1';SEARCH='pawday-m63-it-opensearch-1';DB=USER='pawday_recovery_test';PG='postgres:17.9-alpine';NETWORK='pawday-m63-it_recovery'
def run(args,*,data=None,ok=True,timeout=180):
 r=subprocess.run(args,cwd=ROOT,input=data,capture_output=True,timeout=timeout)
 if ok and r.returncode:raise RuntimeError('RECOVERY_COMMAND_FAILED:'+args[0])
 return r
def sql(container,text,*,ok=True):return run(['docker','exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U',USER,'-d',DB],data=text.encode(),ok=ok)
def value(container,text):return sql(container,text).stdout.decode().strip()
def wait_for(predicate,timeout=120):
 deadline=time.monotonic()+timeout
 while time.monotonic()<deadline:
  try:
   result=predicate()
   if result:return result
  except (OSError,ValueError):pass
  time.sleep(1)
 raise RuntimeError('RECOVERY_CONDITION_TIMEOUT')
def guard():
 for name in [SOURCE,SEARCH]:
  c=json.loads(run(['docker','inspect',name]).stdout)[0];labels=c['Config']['Labels']
  if labels.get('com.docker.compose.project')!='pawday-m63-it' or labels.get('cn.pawday.recovery.fixture')!='true' or c['HostConfig']['PortBindings']:raise RuntimeError('NON_FIXTURE_SOURCE_REFUSED')
 if not json.loads(run(['docker','network','inspect',NETWORK]).stdout)[0]['Internal']:raise RuntimeError('NON_INTERNAL_NETWORK_REFUSED')
def facts(container):
 tables=value(container,"SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").splitlines();queries=[]
 for table in tables:
  if not re.fullmatch('[a-z0-9_]+',table):raise RuntimeError('UNSAFE_TABLE_NAME')
  queries.append("SELECT json_build_object('table','"+table+"','rows',count(*),'sha256',encode(digest(coalesce(string_agg(row_to_json(t)::text,E'\\n' ORDER BY row_to_json(t)::text),''),'sha256'),'hex')) FROM \""+table+'\" t;')
 return {r['table']:{'rows':r['rows'],'sha256':r['sha256']} for r in map(json.loads,value(container,'\n'.join(queries)).splitlines())}
def fixed_id(n):return '63000000-0000-4000-8000-'+str(n).zfill(12)

def gate(commit):
 guard();OUT.mkdir(parents=True,exist_ok=True)
 if run(['git','status','--porcelain']).stdout.strip() or run(['git','rev-parse',commit+'^{tree}']).stdout!=run(['git','rev-parse','HEAD^{tree}']).stdout:raise RuntimeError('UNVERIFIED_CODE_REFUSED')
 LOCAL.mkdir(exist_ok=False);report=dict(result='FAIL',source_code_commit=commit,production_ready=False,environment='synthetic-physical-PITR',cases=[]);nonce=uuid.uuid4().hex;image='pawday-m63-probe:'+commit[:12];network='pawday-m63-restore-'+nonce;targets=[];volumes=[];created_network=False
 def passed(name):report['cases'].append(dict(name=name,result='PASS'))
 def probe(action,*,target=False,ok=True):
  return run(['docker','run','--rm',*(['--mount','type=bind,source='+str(LOCAL/'independent-privacy')+',target=/independent-privacy','--mount','type=bind,source='+str(LOCAL/'live-media')+',target=/live-media'] if not target else []),'--network',network if target else NETWORK,'--label','cn.pawday.recovery.sandbox='+nonce,'-e','M63_TARGET='+('recovered-postgres' if target else 'postgres'),image,'--test-only',action],ok=ok)
 def restore(name,target_time):
  volume=name+'-data';wal_volume=name+'-wal'
  for owned in [volume,wal_volume]:
   run(['docker','volume','create','--label','cn.pawday.recovery.sandbox='+nonce,owned]);volumes.append(owned)
  # docker cp preserves mode 0600 but host uid differs on Linux. Copy into a
  # private, per-target WAL volume and restore postgres ownership; never chmod
  # the original backup or expose archive bytes to other host users.
  run(['docker','run','--rm','--network','none','--mount','type=bind,source='+str(LOCAL/'bundle/base')+',target=/backup,readonly','--mount','type=bind,source='+str(LOCAL/'bundle/wal')+',target=/archive,readonly','--mount','type=volume,source='+volume+',target=/recovery','--mount','type=volume,source='+wal_volume+',target=/restore-wal',PG,'sh','-c','test ! -e /recovery/PG_VERSION && cp -a /backup/. /recovery/ && cp -a /archive/. /restore-wal/ && touch /recovery/recovery.signal && chown -R postgres:postgres /recovery /restore-wal'])
  run(['docker','run','--detach','--name',name,'--network',network,'--network-alias','recovered-postgres','--label','cn.pawday.recovery.sandbox='+nonce,'--mount','type=volume,source='+volume+',target=/var/lib/postgresql/data','--mount','type=volume,source='+wal_volume+',target=/wal,readonly',PG,'postgres','-c','archive_mode=off','-c','restore_command=cp /wal/%f %p','-c','recovery_target_time='+target_time,'-c','recovery_target_action=pause','-c','default_transaction_read_only=on']);targets.append(name)
  info=json.loads(run(['docker','inspect',name]).stdout)[0];assert not info['HostConfig']['PortBindings'] and len(info['NetworkSettings']['Networks'])==1
  return name
 try:
  for p in sorted((ROOT/'backend/src/main/resources/db/migration').glob('V*.sql')):sql(SOURCE,p.read_text(encoding='utf8'))
  passed('all_twenty_one_actual_migrations_on_fresh_source')
  (LOCAL/'independent-privacy').mkdir();(LOCAL/'live-media/media').mkdir(parents=True)
  run(['docker','build','-f','deployment/recovery/Dockerfile','-t',image,'.'],timeout=300);probe('seed');passed('actual_catalog_privacy_ledger_inbox_and_pending_sms_facts')
  png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5N8AAAAASUVORK5CYII=');media_backup=LOCAL/'object-snapshot/media';media_backup.mkdir(parents=True)
  for asset in [61,62]:
   (media_backup/(fixed_id(asset)+'.png')).write_bytes(png);(LOCAL/'live-media/media'/(fixed_id(asset)+'.png')).write_bytes(png)
  probe('export');old_export=(LOCAL/'independent-privacy/latest.json').read_bytes()
  failed=int(value(SOURCE,'SELECT failed_count FROM pg_stat_archiver'))
  run(['docker','exec',SOURCE,'touch','/archive/TEST_ONLY_PAUSE']);segment=value(SOURCE,'SELECT pg_walfile_name(pg_current_wal_lsn())');sql(SOURCE,'SELECT pg_switch_wal()')
  wait_for(lambda:int(value(SOURCE,'SELECT failed_count FROM pg_stat_archiver'))>failed);sql(SOURCE,"UPDATE offers SET version=version+1 WHERE sale_status='ACTIVE'");passed('archive_failure_visible_business_writes_continue')
  run(['docker','exec',SOURCE,'rm','/archive/TEST_ONLY_PAUSE']);sql(SOURCE,'SELECT pg_switch_wal()')
  wait_for(lambda:run(['docker','exec',SOURCE,'test','-f','/archive/wal/'+segment],ok=False).returncode==0,180);passed('archive_resumes_and_catches_up')
  with (LOCAL/'basebackup.log').open('wb') as log:
   base=subprocess.Popen(['docker','exec','-u','postgres','-e','PGPASSWORD=TEST_ONLY_M63',SOURCE,'pg_basebackup','-h','127.0.0.1','-U',USER,'-D','/archive/base','-Fp','-Xstream','--checkpoint=fast','--max-rate=10M','--manifest-checksums=SHA256'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
   time.sleep(.5);assert base.poll() is None;sql(SOURCE,"UPDATE offers SET version=version+1 WHERE sale_status='ACTIVE'");assert base.wait(timeout=180)==0
  run(['docker','exec',SOURCE,'pg_verifybackup','/archive/base']);passed('online_physical_basebackup_with_concurrent_write_and_native_verification')
  sql(SOURCE,f"UPDATE offers SET sale_price_fen=2000 WHERE id='{fixed_id(26)}'; UPDATE inventory_balances SET on_hand_qty=7 WHERE offer_id='{fixed_id(26)}'")
  before=facts(SOURCE);target_time=value(SOURCE,'SELECT clock_timestamp()');time.sleep(.2)
  sql(SOURCE,f"UPDATE offers SET sale_price_fen=9999 WHERE id='{fixed_id(26)}'; UPDATE inventory_balances SET on_hand_qty=0 WHERE offer_id='{fixed_id(26)}'; INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,source_event,created_by_type) VALUES (gen_random_uuid(),'{fixed_id(3)}','MANUAL_ADJUSTMENT','CREDIT',999,true,'TEST_ONLY_AFTER_TARGET','SYSTEM')")
  passed('committed_good_state_and_later_bad_state_separated_by_database_time')
  # Independent, newer privacy facts must not disappear when restoring an older time.
  probe('privacy');required_until=value(SOURCE,'SELECT clock_timestamp()');system_id=value(SOURCE,'SELECT system_identifier FROM pg_control_system()');backup_id=uuid.uuid4().hex
  probe('export-failure');assert value(SOURCE,'SELECT count(*) FROM privacy_journal')=='4' and value(SOURCE,"SELECT status FROM ai_conversations WHERE id='"+fixed_id(40)+"'")=='DELETED';passed('actual_business_privacy_commands_commit_despite_independent_export_outage')
  probe('export');export_data=(LOCAL/'independent-privacy/latest.json').read_bytes();key=b'TEST_ONLY_M64_PRIVATE_EXPORT_32_BYTES'
  pin=json.loads(value(SOURCE,"SELECT row_to_json(s) FROM (SELECT h.journal_id,s.exported_sequence,s.checkpoint_sha256 FROM privacy_export_state s CROSS JOIN privacy_journal_head h) s"))
  args=dict(system_id=system_id,journal_id=pin['journal_id'],required_until=required_until,minimum_sequence=pin['exported_sequence'],expected_checkpoint_sha256=pin['checkpoint_sha256'],now=dt.datetime.now(dt.timezone.utc).isoformat(),backup_id=backup_id)
  registry=verify_export(export_data,key,**args);assert registry['last_sequence']==4;passed('independent_signed_export_retries_and_covers_all_four_committed_facts')
  registry_data=json.dumps(registry,sort_keys=True).encode();signature=hmac.new(key,registry_data,hashlib.sha256).hexdigest()
  segment=value(SOURCE,'SELECT pg_walfile_name(pg_current_wal_lsn())');sql(SOURCE,'SELECT pg_switch_wal()');wait_for(lambda:run(['docker','exec',SOURCE,'test','-f','/archive/wal/'+segment],ok=False).returncode==0)
  source_final=facts(SOURCE);archive_stats=json.loads(value(SOURCE,"SELECT row_to_json(s) FROM (SELECT archived_count,failed_count,last_archived_time FROM pg_stat_archiver) s"));run(['docker','stop',SOURCE]);run(['docker','cp',SOURCE+':/archive/.',str(LOCAL/'bundle')]);passed('immutable_archive_capture_includes_later_commits')
  manifest=dict(schema_version='pawday-pitr/v1',source_commit=commit,system_id=system_id,backup_id=backup_id,target_time=target_time,files=bundle_files(LOCAL/'bundle'));validate_bundle(LOCAL/'bundle',manifest,commit=commit,system_id=system_id)
  wal=next(p for p in (LOCAL/'bundle/wal').iterdir() if re.fullmatch('[0-9A-F]{24}',p.name));raw=wal.read_bytes();wal.write_bytes(b'CORRUPT')
  try:validate_bundle(LOCAL/'bundle',manifest,commit=commit,system_id=system_id);raise RuntimeError('CORRUPT_WAL_ACCEPTED')
  except RecoveryError:pass
  wal.write_bytes(raw);held=LOCAL/'held-wal';wal.rename(held)
  try:validate_bundle(LOCAL/'bundle',manifest,commit=commit,system_id=system_id);raise RuntimeError('MISSING_WAL_ACCEPTED')
  except RecoveryError:pass
  held.rename(wal);validate_bundle(LOCAL/'bundle',manifest,commit=commit,system_id=system_id);passed('missing_and_corrupt_wal_rejected_before_target_creation')
  run(['docker','network','create','--internal','--label','cn.pawday.recovery.sandbox='+nonce,network]);created_network=True;run(['docker','network','connect','--alias','opensearch',network,SEARCH]);started=time.monotonic()
  target=restore(network+'-postgres',target_time)
  def replay_paused():
   r=sql(target,'SELECT pg_is_in_recovery() AND pg_is_wal_replay_paused()',ok=False)
   return r.returncode==0 and r.stdout.strip()==b't'
  wait_for(replay_paused);assert facts(target)==before;passed('actual_time_target_paused_read_only_and_every_table_matches')
  assert sql(target,"UPDATE offers SET sale_price_fen=1",ok=False).returncode!=0;passed('paused_recovery_rejects_writes')
  impossible=restore(network+'-unreachable',(dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=1)).isoformat())
  wait_for(lambda:b'recovery ended before configured recovery target was reached' in run(['docker','logs',impossible],ok=False).stderr);passed('unreachable_time_target_fails_without_promotion')
  # Only this randomly labelled engineering target may be promoted for offline review.
  assert value(target,'SELECT pg_promote(true,30)')=='t';passed('engineering_only_promotion_keeps_network_and_default_read_only')
  rejected=probe('prepare',target=True,ok=False)
  assert rejected.returncode!=0 and b'PRIVACY_REVIEW_REQUIRED' in rejected.stderr;passed('search_rebuild_blocked_before_privacy_review')
  registry_before=facts(target)
  try:verify_export(old_export,key,**args);raise RuntimeError('STALE_REGISTRY_ACCEPTED')
  except RecoveryError:pass
  assert facts(target)==registry_before;passed('authenticated_but_stale_registry_cannot_change_restore')
  tampered=bytearray(export_data);tampered[len(tampered)//2]^=1
  try:verify_export(bytes(tampered),key,**args);raise RuntimeError('TAMPERED_EXPORT_ACCEPTED')
  except RecoveryError:pass
  assert facts(target)==registry_before;passed('tampered_independent_export_cannot_change_restore')
  args['now']=dt.datetime.now(dt.timezone.utc).isoformat();verified_registry=verify_export(export_data,key,**args)
  privacy_sql=privacy_replay_sql(verified_registry)
  sql(target,privacy_sql);privacy_once=facts(target);sql(target,privacy_sql);assert facts(target)==privacy_once
  sql(target,f"BEGIN; SET LOCAL transaction_read_only=off; UPDATE m63_fixture SET privacy_reviewed=true,registry_hash='{hashlib.sha256(registry_data).hexdigest()}'; COMMIT;")
  assert value(target,'SELECT count(*) FROM ai_messages WHERE user_text_ciphertext IS NOT NULL OR result_ciphertext IS NOT NULL')=='0' and value(target,'SELECT count(*) FROM ai_preferences WHERE personalization_enabled')=='0';passed('deletion_revocation_retention_and_session_invalidation_replayed_idempotently')
  restored=LOCAL/'restored-objects';restored.mkdir()
  refs=json.loads(value(target,"SELECT coalesce(json_agg(s),'[]') FROM (SELECT object_key,sha256 FROM media_asset WHERE status='READY') s"))
  for obj in refs:
   assert re.fullmatch(r'media/[0-9a-f-]{36}\.png',obj['object_key']);body=(LOCAL/'object-snapshot'/obj['object_key']).read_bytes();assert hashlib.sha256(body).hexdigest()==obj['sha256'];p=restored/obj['object_key'];p.parent.mkdir(exist_ok=True);p.write_bytes(body)
  assert len(refs)==1 and not (restored/('media/'+fixed_id(62)+'.png')).exists();passed('ready_media_restored_and_deleted_media_not_resurrected')
  probe('prepare',target=True);old=json.loads(run(['docker','exec',SEARCH,'curl','-fsS','http://localhost:9200/_alias/pawday-product-read']).stdout);run(['docker','stop',SEARCH]);probe('retry',target=True);run(['docker','start',SEARCH]);wait_for(lambda:run(['docker','exec',SEARCH,'curl','-fsS','http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=2s'],ok=False).returncode==0)
  assert json.loads(run(['docker','exec',SEARCH,'curl','-fsS','http://localhost:9200/_alias/pawday-product-read']).stdout)==old;passed('actual_search_outage_keeps_old_alias_and_durable_retry')
  probe('finish',target=True);passed('existing_projection_rebuild_retry_atomic_alias_and_retired_sku_filter')
  assert sql(target,'BEGIN; SET LOCAL transaction_read_only=off; UPDATE merchant_ledger_entries SET amount_fen=1;',ok=False).returncode!=0 and value(target,'SELECT sum(amount_fen) FROM merchant_ledger_entries')=='12345'
  sql(target,f"BEGIN; SET LOCAL transaction_read_only=off; INSERT INTO processed_event(consumer,event_id,status,payload_hash) VALUES ('TEST_ONLY_M63','{fixed_id(31)}','PROCESSED','{'b'*64}') ON CONFLICT DO NOTHING; COMMIT;")
  after=facts(target)
  for table in ['merchant_ledger_entries','processed_event','offers','inventory_balances','ai_quota_ledger','payments','payment_attempts','refunds','settlements']:assert after[table]==before[table]
  assert value(target,"SELECT count(*) FROM outbox_event WHERE event_type='OtpSmsRequested' AND status<>'PENDING'")=='0';passed('ledger_inbox_inventory_and_delivery_facts_preserved_no_business_replay')
  try:retention_plan(['wal/required'],['wal/required','objects/required','secrets://history']);raise RuntimeError('PINNED_WAL_RETENTION_ACCEPTED')
  except RecoveryError:pass
  passed('backup_chain_object_and_key_retention_pins_block_cleanup')
  run(['docker','start',SOURCE])
  def source_ready():
   r=sql(SOURCE,'SELECT NOT pg_is_in_recovery()',ok=False)
   return r.returncode==0 and r.stdout.strip()==b't'
  wait_for(source_ready);assert facts(SOURCE)==source_final;passed('source_database_unchanged_by_all_restore_reviews')
  report.update(result='PASS',tables=len(before),rows=sum(v['rows'] for v in before.values()),archive=archive_stats,target_time=target_time,system_id=system_id,backup_id=backup_id,backup_files=len(manifest['files']),registry_sha256=hashlib.sha256(registry_data).hexdigest(),registry_events=4,independent_export=True,trusted_latest_pin=pin,restore_seconds=round(time.monotonic()-started,3),runtime_application_started=False,external_workers_started=False,quarantine_released=False,limitations=['Synthetic local archive only; no production RPO/RTO promise','Online privacy capture verified for AI deletion/expiry, personalization revocation and media tombstones only; production KMS/object versions and account deletion remain pending','No production promotion or live provider reconciliation'])
 except BaseException as e:
  report['failure_code']=str(e) if re.fullmatch('[A-Z_:]+',str(e)) else type(e).__name__;raise
 finally:
  for name in targets:
   data=run(['docker','inspect',name],ok=False)
   if data.returncode==0 and json.loads(data.stdout)[0]['Config']['Labels'].get('cn.pawday.recovery.sandbox')==nonce:
    logs=run(['docker','logs',name],ok=False);(OUT/(name+'.log')).write_bytes(logs.stdout+logs.stderr)
    run(['docker','rm','-f',name])
  if created_network:
   run(['docker','network','disconnect',network,SEARCH],ok=False);data=run(['docker','network','inspect',network],ok=False)
   if data.returncode==0 and json.loads(data.stdout)[0]['Labels'].get('cn.pawday.recovery.sandbox')==nonce:run(['docker','network','rm',network])
  for volume in volumes:
   data=run(['docker','volume','inspect',volume],ok=False)
   if data.returncode==0 and json.loads(data.stdout)[0]['Labels'].get('cn.pawday.recovery.sandbox')==nonce:run(['docker','volume','rm',volume])
  (OUT/'recovery-gate.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(dict(result=report['result'],cases=len(report['cases']),tables=report['tables'],production_ready=False)))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--test-only',action='store_true',required=True);p.add_argument('--commit',required=True);a=p.parse_args();gate(a.commit)
