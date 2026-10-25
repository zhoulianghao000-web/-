"""B2 actual HTTP response gate. Draft examples are never counted as runtime evidence."""
import argparse,json,re
from pathlib import Path
from urllib.parse import urlsplit
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
ROOT=Path(__file__).resolve().parents[1]

def validate(samples):
 doc=json.loads((ROOT/'openapi/pawday-v3.2-b2.json').read_text(encoding='utf-8'));validate_spec(doc)
 reg=Registry().with_resource('urn:pawday:v32b2',Resource.from_contents(doc,default_specification=DRAFT202012));covered=set();count=0
 ops=[(p,m,op) for p,v in doc['paths'].items() for m,op in v.items() if op.get('x-implemented-in')=='V3.2-B2']
 for sample in samples:
  matches=[(p,m,op) for p,m,op in ops if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',p),urlsplit(sample['path']).path)]
  assert matches,'Unmapped B2 sample: '+sample['path']
  p,m,op=matches[0];status=str(sample['status']);schema=op['responses'][status]['content']['application/json']['schema']
  Draft202012Validator({'$ref':'urn:pawday:v32b2'+schema['$ref']},registry=reg,format_checker=FormatChecker()).validate(sample['response']);covered.add((p,m,status));count+=1
 required={(p,m,status) for p,m,_ in ops for status in ['200','400','401','403','404','503']}|{(p,m,'409') for p,m,_ in ops if m=='post'}
 assert len(ops)==3 and required<=covered,'Missing actual per-operation branches: '+str(required-covered)
 return dict(result='PASS',stage='V3.2-B2',evidence_kind='REAL_HTTP_SYNTHETIC_BUSINESS',operations=len(ops),actual_responses=count,coverage=[list(x) for x in sorted(covered)],real_supplier_verified=False,final_e2e_acceptance=False)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--samples',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--disabled-samples',type=Path);a=p.parse_args();report=validate(json.loads(a.samples.read_text(encoding='utf-8'))+(json.loads(a.disabled_samples.read_text(encoding='utf-8')) if a.disabled_samples else []));a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
