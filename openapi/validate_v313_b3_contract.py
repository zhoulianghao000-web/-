"""Validate actual B1/B2/B3 HTTP responses against implemented service finance operations."""
import argparse,json,re
from pathlib import Path
from urllib.parse import urlsplit
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
ROOT=Path(__file__).resolve().parents[1]
def validate(samples):
 doc=json.loads((ROOT/'openapi/pawday-v3.1.3-b3.json').read_text(encoding='utf-8'));validate_spec(doc)
 reg=Registry().with_resource('urn:pawday:v313b3',Resource.from_contents(doc,default_specification=DRAFT202012));covered=set();count=0
 ops=[(p,m,op) for p,v in doc['paths'].items() for m,op in v.items() if op.get('x-implemented-in') in ['V3.1.3-B1','V3.1.3-B2','V3.1.3-B3']]
 for sample in samples:
  matches=[(p,m,op) for p,m,op in ops if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',p),urlsplit(sample['path']).path)]
  if not matches:continue
  p,m,op=matches[0];status=str(sample['status']);schema=op['responses'][status]['content']['application/json']['schema']
  Draft202012Validator({'$ref':'urn:pawday:v313b3'+schema['$ref']},registry=reg,format_checker=FormatChecker()).validate(sample['response']);covered.add((p,m,status));count+=1
 assert {(p,m,'200') for p,m,_ in ops}<=covered,'Missing success operations: '+str({(p,m,'200') for p,m,_ in ops}-covered)
 assert {'400','401','403','404','409','503'}<={status for _,_,status in covered},'Missing negative response coverage'
 newops=[(p,m) for p,m,op in ops if op.get('x-implemented-in')=='V3.1.3-B3']
 required={(p,m,status) for p,m in newops for status in ['200','400','401','403','404','503']}|{(p,m,'409') for p,m in newops if m=='post' and not p.endswith('/service-trade-settlement-previews')}
 assert required<=covered,'Missing per-operation B3 failure branches: '+str(required-covered)
 return dict(result='PASS',stage='V3.1.3-B3',evidence_kind='REAL_HTTP_SYNTHETIC_BUSINESS',runtime_verified=True,real_payment_verified=False,settlement_implemented=True,real_payout_verified=False,final_e2e_acceptance=False,operations=len(ops),actual_responses=count,coverage=[list(x) for x in sorted(covered)])
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--samples',type=Path,required=True);p.add_argument('--b1-samples',type=Path,required=True);p.add_argument('--b2-samples',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();report=validate(json.loads(a.samples.read_text(encoding='utf-8'))+json.loads(a.b1_samples.read_text(encoding='utf-8'))+json.loads(a.b2_samples.read_text(encoding='utf-8')));a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
