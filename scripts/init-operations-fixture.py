"""Generate disposable loopback CI credentials; never a production Secret provisioner."""
import argparse,secrets
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--test-only',action='store_true',required=True);p.parse_args()
root=Path(__file__).resolve().parents[1]/'.local-operations';root.mkdir(exist_ok=True)
for name in ['scrape-token','webhook-token']:
    path=root/name
    if path.exists():raise SystemExit('FIXTURE_ALREADY_EXISTS')
    path.write_text(secrets.token_urlsafe(32),encoding='ascii');path.chmod(0o644)
print('Disposable engineering credentials created (values not printed).')
