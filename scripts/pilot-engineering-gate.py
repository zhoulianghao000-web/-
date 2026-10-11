"""Independent real four-service pilot gate. Synthetic identities, no live providers."""
import argparse,base64,hashlib,json,os,secrets,subprocess,tempfile,time,urllib.request,urllib.error,uuid
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--jar',required=True);p.add_argument('--java',default='java');p.add_argument('--report',required=True);a=p.parse_args();jar=Path(a.jar).resolve();target=Path(a.report).resolve();target.parent.mkdir(parents=True,exist_ok=True)
 env={k:v for k,v in os.environ.items() if not k.startswith(('PAWDAY_','SPRING_','REDIS_','RABBITMQ_','OPENSEARCH_','SERVER_','PILOT_'))}
 env.update(PILOT_DB_NAME='pawday_pilot_gate',PILOT_DB_PASSWORD=secrets.token_urlsafe(24),PILOT_MQ_PASSWORD=secrets.token_urlsafe(24))
 samples=[];binary=[]
 def fixture(name):
  raw=bytearray(hashlib.md5(('pawday-pilot:cq-v1:'+name).encode()).digest());raw[6]=(raw[6]&15)|48;raw[8]=(raw[8]&63)|128;return str(uuid.UUID(bytes=bytes(raw)))
 compose=['docker','compose','-p','pawday-pilot-m662-gate','-f','compose.pilot.yaml'];cases=[];process=None;owned=False;failure=None
 def run(*args):return subprocess.run([*compose,*args],env=env,capture_output=True,text=True,timeout=360)
 def record(name,ok):
  cases.append(dict(case=name,result='PASS' if ok else 'FAIL'))
  if not ok:raise RuntimeError(name)
 def request(path,body=None,token=None,client=True):
  headers={'Content-Type':'application/json'}
  if client:headers['X-Pawday-Pilot']='simulated-v1'
  if token:headers['Authorization']='Bearer '+token
  r=urllib.request.Request('http://127.0.0.1:8086'+path,data=None if body is None else json.dumps(body).encode(),headers=headers)
  try:response=urllib.request.urlopen(r,timeout=5)
  except urllib.error.HTTPError as ex:response=ex
  with response:
   if response.headers.get('Content-Type','').startswith('image/png'):
    data=response.read();binary.append(dict(path=path.removeprefix('/api/v1'),status=response.status,content_type='image/png',bytes=len(data)));return response.status,data,response.headers
   data=json.load(response)
   if path.startswith(('/api/v1/consumer/pilot/','/api/v1/public/skus/','/api/v1/consumer/skus/','/api/v1/public/products','/api/v1/public/nearby/')):
    samples.append(dict(method='post' if body is not None else 'get',path=path.removeprefix('/api/v1'),status=response.status,response=data))
   return response.status,data,response.headers
 try:
  record('isolated_project_not_preexisting',run('ps','-q').stdout.strip()=='')
  owned=True;record('four_real_services_start',run('up','-d','--wait','--wait-timeout','300').returncode==0)
  with tempfile.TemporaryDirectory(prefix='pawday-pilot-gate-') as tmp:
   root=Path(tmp);env.update(SPRING_PROFILES_ACTIVE='local,pilot',PAWDAY_DEPLOYMENT_MODE='pilot',PAWDAY_PILOT_ROOT=str(root),SERVER_PORT='8086',SERVER_ADDRESS='127.0.0.1',
    SPRING_DATASOURCE_URL='jdbc:postgresql://127.0.0.1:5546/pawday_pilot_gate',SPRING_DATASOURCE_USERNAME='pawday_pilot',SPRING_DATASOURCE_PASSWORD=env['PILOT_DB_PASSWORD'],
    REDIS_HOST='127.0.0.1',REDIS_PORT='6386',RABBITMQ_HOST='127.0.0.1',RABBITMQ_PORT='5676',RABBITMQ_USER='pawday_pilot',RABBITMQ_PASSWORD=env['PILOT_MQ_PASSWORD'],OPENSEARCH_URL='http://127.0.0.1:9206',
    PAWDAY_AUTH_SECRET=base64.b64encode(secrets.token_bytes(32)).decode(),PAWDAY_DEMO_ENABLED='true',PAWDAY_DEMO_MERCHANT_PASSWORD=secrets.token_urlsafe(24),PAWDAY_DEMO_ADMIN_PASSWORD=secrets.token_urlsafe(24),PAWDAY_DEMO_ADMIN_TOTP_BASE64=base64.b64encode(secrets.token_bytes(20)).decode())
   with (target.parent/'backend.log').open('w',encoding='utf8') as log:
    process=subprocess.Popen([a.java,'-jar',str(jar)],env=env,stdout=log,stderr=subprocess.STDOUT)
    health=None
    for _ in range(150):
     if process.poll() is not None:break
     try:
      status,health,_=request('/actuator/health')
      if status==200:break
     except (OSError,ValueError):pass
     time.sleep(1)
    record('aggregate_real_health',health is not None and health.get('status')=='UP')
    for _ in range(60):
     if request('/api/v1/public/pet-taxonomy',client=False)[0]==409:break
     time.sleep(.2)
    record('ordinary_client_rejected',request('/api/v1/public/pet-taxonomy',client=False)[0]==409)
    record('guest_public_data_rejected',request('/api/v1/public/pet-taxonomy')[0]==401)
    record('uninvited_otp_rejected',request('/api/v1/consumer/auth/phone/request-code',dict(phone_e164='+999000000099',purpose='LOGIN'))[0]==403)
    phone='+999000000001';status,otp,_=request('/api/v1/consumer/auth/phone/request-code',dict(phone_e164=phone,purpose='LOGIN'));record('invited_otp_committed',status==200)
    receipt=root/'sms'/(otp['data']['id']+'.txt')
    for _ in range(40):
     if receipt.is_file():break
     time.sleep(.5)
    record('rabbit_outbox_delivers_local_sms',receipt.is_file());lines=receipt.read_text().splitlines();record('synthetic_sms_destination',lines[0]==phone)
    status,login,headers=request('/api/v1/consumer/auth/phone/verify',dict(phone_e164=phone,code=lines[1],device_id='PILOT_GATE'));record('invited_consumer_login',status==200);token=login['data']['access_token']
    record('pilot_environment_and_no_store',headers.get('X-Pawday-Environment')=='SIMULATED_PILOT' and headers.get('Cache-Control')=='no-store')
    record('authenticated_public_data',request('/api/v1/public/pet-taxonomy',token=token)[0]==200)
    record('consumer_admin_realm_denied',request('/api/v1/admin/me',token=token)[0]==403)
    status,baseline,_=request('/api/v1/consumer/pilot/baseline',token=token);record('versioned_cq_baseline',status==200 and baseline['data']['sku_count']==20 and baseline['data']['consumer_count']==20 and baseline['data']['production_approved'] is False)
    for n in range(1,21):
     status,standard,_=request('/api/v1/public/skus/'+fixture('sku-'+str(n)),token=token)
     record('source_snapshot_'+str(n),status==200 and standard['data']['pilot_material']['generated_fixture'] is True and standard['data']['pilot_material']['kind']==('SYNTHETIC' if n<=16 else 'UNVERIFIED'))
    status,fit,_=request('/api/v1/consumer/skus/'+fixture('sku-1')+'/fit?pet_id='+fixture('pet-1'),token=token);record('synthetic_suitable',status==200 and fit['data']['result']=='SUITABLE')
    status,fit,_=request('/api/v1/consumer/skus/'+fixture('sku-18')+'/fit?pet_id='+fixture('pet-1'),token=token);record('unverified_forces_information_insufficient',status==200 and fit['data']['result']=='INSUFFICIENT_DATA' and not fit['data']['hard_conflicts'])
    media='/api/v1/consumer/pilot/skus/'+fixture('sku-1')+'/media'
    record('image_guest_denied',request(media)[0]==401)
    status,image,headers=request(media,token=token);record('authenticated_real_object_image',status==200 and image[:4]==bytes([137,80,78,71]) and headers.get('Cache-Control')=='no-store')
    products=[]
    for _ in range(60):
     status,page,_=request('/api/v1/public/products?limit=100',token=token)
     products=page.get('data',[]) if status==200 else []
     if len(products)==20:break
     time.sleep(.5)
    record('all_twenty_outbox_search_projection_visible',len(products)==20 and all(x['pilot_material']['production_approved'] is False for x in products))
    status,nearby,_=request('/api/v1/public/nearby/places?city='+urllib.parse.quote('重庆'),token=token)
    record('two_synthetic_chongqing_stores',status==200 and len(nearby['data'])==2 and all('合成' in x['name'] for x in nearby['data']))
    record('refresh_rotates',request('/api/v1/consumer/auth/refresh',dict(refresh_token=login['data']['refresh_token']))[0]==200)
    # Use the new access token for the pause/resume check.
    status,otp,_=request('/api/v1/consumer/auth/phone/request-code',dict(phone_e164=phone,purpose='LOGIN'));receipt=root/'sms'/(otp['data']['id']+'.txt')
    for _ in range(40):
     if receipt.is_file():break
     time.sleep(.5)
    status,login,_=request('/api/v1/consumer/auth/phone/verify',dict(phone_e164=phone,code=receipt.read_text().splitlines()[1],device_id='PILOT_GATE'));record('second_local_login',status==200);token=login['data']['access_token']
    (root/'PAUSED').write_text('gate');record('pause_blocks_active_session',request('/api/v1/consumer/me',token=token)[0]==503);(root/'PAUSED').unlink();record('resume_recovers_active_session',request('/api/v1/consumer/me',token=token)[0]==200)
 except Exception as ex:failure=str(ex) if isinstance(ex,RuntimeError) else type(ex).__name__
 finally:
  if process is not None:
   process.terminate()
   try:process.wait(timeout=20)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=10)
  if owned:record_cleanup=run('down','--volumes').returncode==0;cases.append(dict(case='stop_only_owned_project',result='PASS' if record_cleanup else 'FAIL'))
 report=dict(result='PASS' if failure is None and all(c['result']=='PASS' for c in cases) else 'FAIL',scope='SIMULATED_PILOT_ENGINEERING_ONLY',production_ready=False,onsite_users_tested=0,jar_sha256=hashlib.sha256(jar.read_bytes()).hexdigest(),cases=cases)
 if failure:report['failure']=failure
 (target.parent/'http-samples.json').write_text(json.dumps(samples,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 (target.parent/'binary-samples.json').write_text(json.dumps(binary,indent=2)+'\n',encoding='utf8')
 target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report));return 0 if report['result']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
