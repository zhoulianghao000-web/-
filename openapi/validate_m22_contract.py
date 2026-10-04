"""Validate M2.1 OpenAPI and, optionally, sanitized real HTTP integration responses."""
from pathlib import Path
import argparse,json,re
from datetime import datetime,timezone
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--samples',type=Path);parser.add_argument('--report',type=Path,default=HERE/'m22-validation-report.json');args=parser.parse_args()
spec=yaml.safe_load((HERE/'pawday-m2.2.yaml').read_text(encoding='utf-8'));validate_spec(spec)
ids=set();operations=[]
for path,item in spec['paths'].items():
 for method,op in item.items():
  assert op['operationId'] not in ids;ids.add(op['operationId'])
  assert op['x-implemented-in'] in ['M2.1','M2.2']
  operations.append((path,method,op))
registry=Registry().with_resource('urn:pawday:m2-contract',Resource.from_contents(spec,default_specification=__import__('referencing.jsonschema',fromlist=['DRAFT202012']).DRAFT202012))
count=0;covered=set()
if args.samples:
 for sample in json.loads(args.samples.read_text(encoding='utf-8')):
  matching=[(path,method,op) for path,method,op in operations if method==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',path),sample['path'].split('?')[0])]
  assert len(matching)==1,('Unmapped response',sample['path'],sample['method'])
  path,method,op=matching[0];code=str(sample['status']);assert code in op['responses'],(path,code)
  schema=op['responses'][code]['content']['application/json']['schema']
  Draft202012Validator({'$ref':'urn:pawday:m2-contract'+schema['$ref']},registry=registry,format_checker=FormatChecker()).validate(sample['response'])
  count+=1;covered.add((method,path,code))
report={'result':'PASS','validated_at_utc':datetime.now(timezone.utc).isoformat(),'operations':len(operations),'schemas':len(spec['components']['schemas']),'actual_http_responses_validated':count,'covered_method_path_status_count':len(covered),'covered_responses':[list(x) for x in sorted(covered)],'note':'Only captured responses are runtime-verified; OpenAPI validation does not establish runtime coverage for every operation.'}
args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'pawday-m2.2.bundle.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='covered_responses'},ensure_ascii=False))
