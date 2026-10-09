"""Probe the actual packaged application: production must fail before DB/server startup.
No credentials, network calls or database are needed. Output contains only reason IDs.
"""
import argparse, hashlib, json, os, subprocess
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--jar', required=True)
    p.add_argument('--java', default='java')
    p.add_argument('--report', required=True)
    args = p.parse_args()
    jar = Path(args.jar).resolve()
    if not jar.is_file(): raise SystemExit('Packaged JAR is missing')
    results = []
    for name, flags in [
        ('production', ['--spring.profiles.active=production']),
        ('mixed-local-production', ['--spring.profiles.active=local,production', '--pawday.settlement.simulation-enabled=true', '--pawday.ai.allow-loopback-provider=true']),
        ('prod-alias', ['--spring.profiles.active=prod']),
        ('deployment-mode', ['--pawday.deployment-mode=production']),
    ]:
        # Do not inherit operator credentials/config into an isolated rejection probe.
        env = {k:v for k,v in os.environ.items() if not k.startswith(('PAWDAY_', 'SPRING_', 'OPENSEARCH_', 'REDIS_', 'RABBITMQ_'))}
        done = subprocess.run([args.java, '-jar', str(jar), *flags,
            '--spring.config.additional-location=optional:file:./__no_private_config__/',
            '--spring.main.banner-mode=off'], env=env, capture_output=True, text=True, timeout=30)
        log = done.stdout + done.stderr
        passed = done.returncode != 0 and 'PAWDAY_PRODUCTION_ADMISSION_BLOCKED' in log and not any(
            marker in log for marker in ['HikariPool-', 'Flyway Community', 'Tomcat started', 'Started PawdayApplication'])
        results.append({'case':name, 'result':'PASS' if passed else 'FAIL', 'exit_code':done.returncode,
                        'before_database_and_http_server':passed})
    report = {'result':'PASS' if all(x['result']=='PASS' for x in results) else 'FAIL',
              'production_ready':False, 'jar_sha256':hashlib.sha256(jar.read_bytes()).hexdigest(), 'cases':results}
    target = Path(args.report); target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report))
    raise SystemExit(0 if report['result']=='PASS' else 1)
if __name__ == '__main__': main()
