"""Actual JAR refusal probes. No successful startup or provider evidence is claimed."""
import argparse,hashlib,json,os,subprocess,tempfile
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--jar',required=True);p.add_argument('--java',default='java');p.add_argument('--report',required=True);a=p.parse_args();jar=Path(a.jar).resolve();cases=[]
 env={k:v for k,v in os.environ.items() if not k.startswith(('PAWDAY_','SPRING_','REDIS_','RABBITMQ_','OPENSEARCH_'))}
 with tempfile.TemporaryDirectory(prefix='pawday-pilot-refusal-') as root:
  base=['--spring.profiles.active=local,pilot','--pawday.pilot.root='+root,'--pawday.storage.local-root='+root+'/media','--pawday.auth.local-sms-directory='+root+'/sms','--spring.datasource.url=jdbc:postgresql://127.0.0.1:5546/pawday_pilot_probe']
  for name,flags in [('missing-root',['--pawday.pilot.root=']),('ordinary-database',['--spring.datasource.url=jdbc:postgresql://127.0.0.1:5432/pawday']),('live-ai-credential',['--pawday.ai.deepseek-api-key=TEST_ONLY_DO_NOT_LOG']),('navigation-enabled',['--pawday.nearby.navigation-enabled=true'])]:
   done=subprocess.run([a.java,'-jar',str(jar),*base,*flags],env=env,capture_output=True,text=True,timeout=30);log=done.stdout+done.stderr
   passed=done.returncode!=0 and 'PAWDAY_PILOT_CONFIGURATION_BLOCKED' in log and not any(x in log for x in ['HikariPool-','Tomcat started','Started PawdayApplication']) and 'TEST_ONLY_DO_NOT_LOG' not in log
   cases.append(dict(case=name,result='PASS' if passed else 'FAIL',before_database_and_http_server=passed))
 report=dict(result='PASS' if all(x['result']=='PASS' for x in cases) else 'FAIL',production_ready=False,jar_sha256=hashlib.sha256(jar.read_bytes()).hexdigest(),cases=cases)
 f=Path(a.report);f.parent.mkdir(parents=True,exist_ok=True);f.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report));return 0 if report['result']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
