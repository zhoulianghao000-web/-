"""Mandatory real HTTPS smoke for the generated AMap destination URI, without an API key."""
import argparse,json,time,urllib.request
from pathlib import Path
from urllib.parse import urlparse,parse_qs

p=argparse.ArgumentParser();p.add_argument('--samples',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
samples=json.loads(args.samples.read_text(encoding='utf8'))
sample=next(s for s in samples if s['path']=='/public/nearby/navigation-intents' and s['status']==200)
uri=sample['response']['data']['fallback_url'];parsed=urlparse(uri)
assert parsed.scheme=='https' and parsed.hostname=='uri.amap.com' and parsed.path=='/marker'
assert parse_qs(parsed.query)['coordinate']==['wgs84'] and 'from' not in parse_qs(parsed.query)
class SafeRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,req,fp,code,msg,headers,newurl):
  u=urlparse(newurl)
  assert u.scheme=='https' and u.hostname in {'uri.amap.com','ditu.amap.com','www.amap.com'},'Unexpected navigation redirect'
  return super().redirect_request(req,fp,code,msg,headers,newurl)
opener=urllib.request.build_opener(SafeRedirect())
for attempt in range(3):
 try:
  with opener.open(urllib.request.Request(uri,headers={'User-Agent':'Mozilla/5.0 Pawday-M54-CI'}),timeout=25) as r:
   body=r.read();assert r.status==200 and len(body)>1000
   report={'result':'PASS','provider':'AMAP_URI','real_https_status':r.status,'final_host':urlparse(r.url).hostname,'bytes':len(body),'coordinate_system':'WGS84','user_origin_sent':False,'native_installed_app_verified':False}
  break
 except Exception:
  if attempt==2:raise
  time.sleep(2)
args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report))
