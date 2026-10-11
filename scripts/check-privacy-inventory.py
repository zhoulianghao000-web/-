"""Check metadata-only coverage. PASS does not approve an account deletion."""
import argparse,json
from pathlib import Path
from privacy_export_contract import strict_json
from privacy_review_contract import review_inventory
from recovery_contract import RecoveryError

def main():
    p=argparse.ArgumentParser();p.add_argument('--schema-json',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    root=Path(__file__).resolve().parents[1]
    try:
        m=strict_json((root/'deployment/privacy/data-inventory.json').read_bytes())
        rows=strict_json(a.schema_json.read_bytes())
        result=review_inventory(m,rows,root/'backend/src/main/resources/db/migration')
        code=0
    except (RecoveryError,OSError,ValueError,TypeError,KeyError,AttributeError):
        result=dict(result='FAIL',reason='PRIVACY_INVENTORY_REVIEW_FAILED',deletion_authorized=False,production_ready=False);code=2
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8');print(json.dumps(result));return code

if __name__=='__main__':raise SystemExit(main())
