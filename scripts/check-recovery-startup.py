"""Actual packaged JAR must refuse recovery application/worker startup before DB/HTTP."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--jar',required=True);p.add_argument('--report',required=True);a=p.parse_args();jar=Path(a.jar);cases=[]
 for name,flags in [('recovery-profile',['--spring.profiles.active=recovery']),('mixed-restore-profile',['--spring.profiles.active=local,restore','--pawday.outbox.workers-enabled=true']),('recovery-mode',['--pawday.deployment-mode=recovery']),('explicit-quarantine',['--pawday.recovery.quarantine=true','--pawday.deployment-mode=development'])]:
  env={k:v for k,v in os.environ.items() if not k.startswith(('PAWDAY_','SPRING_','OPENSEARCH_','REDIS_','RABBITMQ_'))}
  r=subprocess.run(['java','-jar',str(jar),*flags,'--spring.main.banner-mode=off'],env=env,capture_output=True,text=True,timeout=30);log=r.stdout+r.stderr
  passed=r.returncode!=0 and 'PAWDAY_RECOVERY_QUARANTINE_BLOCKED' in log and not any(x in log for x in ['HikariPool-','Flyway Community','Tomcat started','Started PawdayApplication'])
  cases.append(dict(case=name,result='PASS' if passed else 'FAIL',before_database_and_http_server=passed))
 report=dict(result='PASS' if all(c['result']=='PASS' for c in cases) else 'FAIL',jar_sha256=hashlib.sha256(jar.read_bytes()).hexdigest(),production_ready=False,cases=cases);out=Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(0 if report['result']=='PASS' else 1)
if __name__=='__main__':main()
