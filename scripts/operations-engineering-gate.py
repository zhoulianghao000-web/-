"""Real Prometheus/Alertmanager + PostgreSQL dump/restore, synthetic data only.

No arbitrary source DB, target DB, webhook URL, or container accepts CLI input.
The restore target is newly created on an internal Docker network without ports
or an application, MQ consumers or external credentials. Production remains blocked.
"""
import argparse,base64,datetime,hashlib,http.server,json,os,secrets,subprocess,threading,time,urllib.request,uuid
from pathlib import Path
from operations_bundle import create_bundle,verify_bundle,digest,BundleError

ROOT=Path(__file__).resolve().parents[1];LOCAL=ROOT/'.local-operations';OUT=ROOT/'backend/target/operations-evidence'
SOURCE='pawday-m62-it-postgres-1';USER=DB='pawday_ops_test'

def run(args,*,data=None,ok=True):
    r=subprocess.run(args,cwd=ROOT,input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=180)
    if ok and r.returncode:raise RuntimeError('OPERATIONS_COMMAND_FAILED:'+args[0])
    return r

def sql(container,text,*,ok=True):
    return run(['docker','exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U',USER,'-d',DB],data=text.encode(),ok=ok)

def request(url,token=None):
    h={} if token is None else {'Authorization':'Bearer '+token}
    with urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=5) as r:return r.read()

def wait_for(predicate,timeout=120):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        try:
            result=predicate()
            if result:return result
        except (OSError,ValueError):pass
        time.sleep(1)
    raise RuntimeError('OPERATIONS_CONDITION_TIMEOUT')

class Receiver(http.server.BaseHTTPRequestHandler):
    events=[];rejected=0;lock=threading.Lock();token=''
    def log_message(self,*args):pass
    def do_POST(self):
        if self.path!='/notify' or not secrets.compare_digest(self.headers.get('Authorization',''),'Bearer '+self.token):
            self.send_response(401);self.end_headers();return
        length=int(self.headers.get('Content-Length','0'))
        if not 0<length<65536:self.send_response(413);self.end_headers();return
        data=json.loads(self.rfile.read(length))
        # Exercise real notification retry; persist only fixed labels/status.
        state=type(self)
        with state.lock:
            failing=any(a.get('labels',{}).get('alertname')=='PawdayOutboxDead' and a.get('status')=='firing' for a in data.get('alerts',[]))
            if failing and state.rejected<2:
                state.rejected+=1;self.send_response(503);self.end_headers();return
            for a in data.get('alerts',[]):state.events.append({'alert':a.get('labels',{}).get('alertname'),'status':a.get('status')})
        self.send_response(200);self.end_headers()

def source_guard():
    c=json.loads(run(['docker','inspect',SOURCE]).stdout)[0]
    labels=c['Config'].get('Labels',{})
    if labels.get('cn.pawday.operations.fixture')!='true' or labels.get('com.docker.compose.project')!='pawday-m62-it':raise RuntimeError('NON_FIXTURE_SOURCE_REFUSED')

def facts(container):
    # Compare every business row, including timestamps/ciphertexts and ledger facts.
    tables=sql(container,"SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").stdout.decode().splitlines()
    result={}
    for table in tables:
        if not table.replace('_','').isalnum():raise RuntimeError('INVALID_TABLE_NAME')
        rows=sql(container,'SELECT row_to_json(t)::text FROM "'+table+'" t ORDER BY row_to_json(t)::text').stdout
        result[table]={'sha256':hashlib.sha256(rows).hexdigest(),'rows':len(rows.splitlines())}
    return result

def gate(commit):
    OUT.mkdir(parents=True,exist_ok=True);source_guard()
    if run(['git','status','--porcelain']).stdout.strip():raise RuntimeError('UNCOMMITTED_SOURCE_REFUSED')
    if run(['git','rev-parse',commit+'^{tree}']).stdout!=run(['git','rev-parse','HEAD^{tree}']).stdout:raise RuntimeError('CODE_TREE_MISMATCH')
    report={'result':'RUNNING','source_code_commit':commit,'environment':'synthetic-isolated-engineering','production_ready':False,'cases':[]}
    def passed(name):report['cases'].append({'name':name,'result':'PASS'})
    server=http.server.ThreadingHTTPServer(('0.0.0.0',9197),Receiver);Receiver.token=(LOCAL/'webhook-token').read_text();threading.Thread(target=server.serve_forever,daemon=True).start()
    env=dict(os.environ)
    for k in list(env):
        if k.startswith(('PAWDAY_','SPRING_','RABBITMQ_','REDIS_','OPENSEARCH_')):env.pop(k)
    env.update(SPRING_DATASOURCE_URL='jdbc:postgresql://127.0.0.1:5546/'+DB,SPRING_DATASOURCE_USERNAME=USER,SPRING_DATASOURCE_PASSWORD='TEST_ONLY_m62_db',PAWDAY_AUTH_SECRET=base64.b64encode(bytes(32)).decode(),PAWDAY_METRICS_SCRAPE_TOKEN=(LOCAL/'scrape-token').read_text(),PAWDAY_SEARCH_ENABLED='false',PAWDAY_OUTBOX_WORKERS_ENABLED='false',PAWDAY_OUTBOX_CONSUMER_ENABLED='false')
    args=['java','-jar','backend/target/pawday-backend-0.6.2-SNAPSHOT.jar','--server.port=8087','--management.health.redis.enabled=false','--management.health.rabbit.enabled=false',
        '--spring.datasource.hikari.connection-timeout=250','--spring.datasource.hikari.validation-timeout=250','--pawday.storage.local-root='+str(LOCAL/'app-media'),
        '--pawday.storage.cleanup-enabled=false','--pawday.checkout.expiry-enabled=false','--pawday.ordering.expiry-enabled=false','--pawday.payment.recovery-enabled=false','--pawday.refund.recovery-enabled=false','--pawday.settlement.worker-enabled=false','--pawday.membership.worker-enabled=false','--pawday.ai.worker-enabled=false']
    app_log=(LOCAL/'backend.log').open('wb');app=subprocess.Popen(args,cwd=ROOT,env=env,stdout=app_log,stderr=subprocess.STDOUT)
    token=env['PAWDAY_METRICS_SCRAPE_TOKEN'];target=None;network=None
    try:
        wait_for(lambda:json.loads(request('http://127.0.0.1:8087/actuator/health'))['status']=='UP');passed('actual_jar_health')
        wait_for(lambda:any(v['value'][1]=='1' for v in json.loads(request('http://127.0.0.1:9190/api/v1/query?query=up'))['data']['result']));passed('authenticated_real_prometheus_scrape')
        event=str(uuid.uuid4())
        sql(SOURCE,f"INSERT INTO outbox_event(id,root_event_id,aggregate_type,aggregate_id,event_type,payload,status,dead_at) VALUES ('{event}','{event}','TEST_ONLY','TEST_ONLY','TEST_ONLY','{{}}','DEAD',now())")
        wait_for(lambda:any(e=={'alert':'PawdayOutboxDead','status':'firing'} for e in Receiver.events));assert Receiver.rejected==2;passed('real_alertmanager_firing_and_delivery_retry')
        sql(SOURCE,f"UPDATE outbox_event SET status='PENDING',dead_at=NULL WHERE id='{event}'")
        wait_for(lambda:any(e=={'alert':'PawdayOutboxDead','status':'resolved'} for e in Receiver.events));passed('real_alertmanager_resolved_delivery')
        run(['docker','stop',SOURCE])
        try:
            wait_for(lambda:any(e=={'alert':'PawdayDatabaseUnavailable','status':'firing'} for e in Receiver.events));passed('real_database_outage_alert_delivery')
        finally:run(['docker','start',SOURCE])
        wait_for(lambda:any(e=={'alert':'PawdayDatabaseUnavailable','status':'resolved'} for e in Receiver.events));passed('real_database_recovery_notification')
        # Stop the only application before snapshotting. No target application is ever started.
        app.terminate();app.wait(timeout=30);app_log.close();passed('quiesced_source_before_backup')
        fixture=json.loads((ROOT/'backend/target/m62-test-ciphertexts.json').read_text());assert fixture['test_only'] is True
        principal='00000000-0000-0000-0000-000000000061';session='00000000-0000-0000-0000-000000000062';merchant='00000000-0000-0000-0000-000000000063';asset='00000000-0000-0000-0000-000000000064'
        for index,name in enumerate(['legacy','old','current']):
            cipher=fixture[name];assert all(c.isalnum() or c in '+/=:_-' for c in cipher)
            ident=principal if index==0 else str(uuid.uuid4())
            sql(SOURCE,f"INSERT INTO identity_principal(id,realm,login_name,password_hash,mfa_secret_ciphertext) VALUES ('{ident}','ADMIN','TEST_ONLY_{name}','TEST_ONLY','{cipher}')")
        sql(SOURCE,f"INSERT INTO auth_session(id,principal_id,access_token_hash,device_id,expires_at,refresh_expires_at,created_at) VALUES ('{session}','{principal}','{'a'*64}','TEST_ONLY',now()+interval '1 hour',now()+interval '1 day',now()); INSERT INTO merchant VALUES ('{merchant}','TEST_ONLY','ACTIVE'); INSERT INTO merchant_ledger_entries(id,merchant_id,entry_type,direction,amount_fen,affects_balance,source_event,created_by_type) VALUES (gen_random_uuid(),'{merchant}','MANUAL_ADJUSTMENT','CREDIT',12345,true,'TEST_ONLY_RESTORE','SYSTEM'); INSERT INTO processed_event(consumer,event_id,status,payload_hash) VALUES ('TEST_ONLY_RESTORE','{event}','PROCESSED','{'b'*64}')")
        media=LOCAL/'source-objects';obj=media/f'media/{asset}.png';obj.parent.mkdir(parents=True);obj.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5N8AAAAASUVORK5CYII='))
        sql(SOURCE,f"INSERT INTO media_asset(id,owner_id,realm,owner_session_id,scope,storage_provider,object_key,mime,size_bytes,sha256,status,upload_expires_at,next_cleanup_at,created_at,updated_at) VALUES ('{asset}','{principal}','ADMIN','{session}','ARTICLE','local','media/{asset}.png','image/png',{obj.stat().st_size},'{digest(obj)}','READY',now(),now(),now(),now())")
        before=facts(SOURCE);dump=LOCAL/'database.dump'
        with dump.open('wb') as stream:
            r=subprocess.run(['docker','exec',SOURCE,'pg_dump','-U',USER,'-d',DB,'--format=custom','--no-owner','--no-privileges'],stdout=stream,stderr=subprocess.PIPE,timeout=120)
            if r.returncode:raise RuntimeError('DUMP_FAILED')
        bundle=LOCAL/'bundle';manifest=create_bundle(dump,media,bundle,commit,fixture['key_references'],quiesced=True);passed('real_pg_dump_and_media_manifest')
        # Negative hash gate occurs BEFORE any target creation or pg_restore invocation.
        original=(bundle/'database.dump').read_bytes();(bundle/'database.dump').write_bytes(b'CORRUPT')
        try:verify_bundle(bundle,commit);raise RuntimeError('CORRUPTION_ACCEPTED')
        except BundleError:pass
        (bundle/'database.dump').write_bytes(original);verify_bundle(bundle,commit);passed('corrupt_bundle_rejected_before_restore')
        restore_started=time.monotonic();nonce=uuid.uuid4().hex;network='pawday-restore-'+nonce;target=network+'-postgres'
        run(['docker','network','create','--internal','--label','cn.pawday.restore.sandbox='+nonce,network])
        run(['docker','run','--detach','--name',target,'--network',network,'--label','cn.pawday.restore.sandbox='+nonce,'-e','POSTGRES_DB='+DB,'-e','POSTGRES_USER='+USER,'-e','POSTGRES_PASSWORD=TEST_ONLY_RESTORE','postgres:17.9-alpine'])
        # The image first starts a socket-only bootstrap server, then restarts it.
        # Probe TCP so bootstrap readiness cannot race the first restore query.
        wait_for(lambda:run(['docker','exec',target,'pg_isready','-h','127.0.0.1','-U',USER,'-d',DB],ok=False).returncode==0)
        info=json.loads(run(['docker','inspect',target]).stdout)[0];net=json.loads(run(['docker','network','inspect',network]).stdout)[0]
        assert not info['HostConfig']['PortBindings'] and net['Internal'] is True and len(net['Containers'])==1 and info['Config']['Labels']['cn.pawday.restore.sandbox']==nonce
        assert sql(target,"SELECT count(*) FROM pg_tables WHERE schemaname='public'").stdout.strip()==b'0';passed('new_empty_internal_target_no_ports_or_workers')
        verify_bundle(bundle,commit)
        run(['docker','exec','-i',target,'pg_restore','-U',USER,'-d',DB,'--single-transaction','--exit-on-error','--no-owner','--no-privileges'],data=(bundle/'database.dump').read_bytes());passed('real_atomic_pg_restore')
        after=facts(target);assert before==after and before==facts(SOURCE);passed('all_business_rows_identical_and_source_unchanged')
        restored=LOCAL/'restored-objects';restored.mkdir()
        for name in manifest['files']:
            if name.startswith('media/'):
                dst=restored/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((bundle/name).read_bytes());assert digest(dst)==manifest['files'][name]['sha256']
        assert sql(target,f"SELECT sha256 FROM media_asset WHERE id='{asset}'").stdout.strip().decode()==digest(restored/f'media/{asset}.png');passed('restored_media_bytes_match_database_reference')
        cipher_rows=sql(target,"SELECT mfa_secret_ciphertext FROM identity_principal WHERE login_name LIKE 'TEST_ONLY_%' ORDER BY CASE login_name WHEN 'TEST_ONLY_legacy' THEN 1 WHEN 'TEST_ONLY_old' THEN 2 ELSE 3 END").stdout
        cp=os.pathsep.join(['backend/target/classes','backend/target/test-classes'])
        key_result=json.loads(run(['java','-cp',cp,'cn.pawday.CipherRestoreProbe'],data=cipher_rows).stdout);assert key_result['result']=='PASS' and key_result['missing_key_rejected'];passed('restored_legacy_old_active_ciphertexts_and_missing_key_rejection')
        sql(target,f"INSERT INTO processed_event(consumer,event_id,status,payload_hash) VALUES ('TEST_ONLY_RESTORE','{event}','PROCESSED','{'b'*64}') ON CONFLICT DO NOTHING")
        assert sql(target,"SELECT count(*) FROM processed_event WHERE consumer='TEST_ONLY_RESTORE'").stdout.strip()==b'1';passed('restored_inbox_uniqueness_preserved')
        assert sql(target,"UPDATE merchant_ledger_entries SET amount_fen=1",ok=False).returncode!=0
        assert sql(target,"SELECT sum(amount_fen) FROM merchant_ledger_entries").stdout.strip()==b'12345';passed('restored_ledger_immutable_and_amount_preserved')
        assert facts(SOURCE)==before;passed('source_unchanged_after_all_target_checks')
        report.update(result='PASS',tables=len(before),business_rows=sum(r['rows'] for r in before.values()),bundle_file_count=len(manifest['files']),manifest_sha256=digest(bundle/'manifest.json'),notifications=list(Receiver.events),notification_failures_before_retry=Receiver.rejected,restore_seconds=round(time.monotonic()-restore_started,3),limitations=['Synthetic logical dump; not production WAL/PITR or promised RPO/RTO','External key values are not backed up in this bundle','No live providers or production deployment'],key_probe=key_result)
    finally:
        if app.poll() is None:app.terminate();app.wait(timeout=30)
        app_log.close();server.shutdown();server.server_close()
        # Cleanup only objects generated by this invocation and with its exact label.
        if target:
            rows=run(['docker','inspect',target],ok=False)
            if rows.returncode==0 and json.loads(rows.stdout)[0]['Config']['Labels'].get('cn.pawday.restore.sandbox')==nonce:run(['docker','rm','-f','-v',target])
        if network:
            rows=run(['docker','network','inspect',network],ok=False)
            if rows.returncode==0 and json.loads(rows.stdout)[0].get('Labels',{}).get('cn.pawday.restore.sandbox')==nonce:run(['docker','network','rm',network])
        (OUT/'operations-gate.json').write_text(json.dumps(report,indent=2)+'\n')
    if report['result']!='PASS':raise RuntimeError('OPERATIONS_GATE_INCOMPLETE')
    print(json.dumps({'result':'PASS','cases':len(report['cases']),'tables':report['tables'],'production_ready':False}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--test-only',action='store_true',required=True);parser.add_argument('--commit',required=True);args=parser.parse_args();gate(args.commit)
