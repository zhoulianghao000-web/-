"""Validate the implemented M5.1 membership and points contract and captured real HTTP responses."""
from pathlib import Path
import argparse,json,re
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--samples',type=Path)
parser.add_argument('--report',type=Path,default=HERE/'m51-validation-report.json')
args=parser.parse_args()
spec=yaml.safe_load((HERE/'pawday-m5.1.yaml').read_text(encoding='utf8'))
validate_spec(spec)
operations=[];ids=set()
for path,item in spec['paths'].items():
 for method,op in item.items():
  assert op['operationId'] not in ids;ids.add(op['operationId'])
  assert op['x-implemented-in'] in ['M2.1','M2.2','M2.3','M3.1','M3.2','M3.3','M3.4','M4.1','M4.2','M4.3','M4.4','M4.5','M4.6','M5.1']
  operations.append((path,method,op))
registry=Registry().with_resource('urn:pawday:m51',Resource.from_contents(spec,default_specification=DRAFT202012))
covered=set();count=0
if args.samples:
 for sample in json.loads(args.samples.read_text(encoding='utf8')):
  matches=[(p,m,o) for p,m,o in operations if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',p),sample['path'].split('?')[0])]
  assert len(matches)==1,('unmapped response',sample['path'])
  path,method,op=matches[0];status=str(sample['status']);assert status in op['responses'],(path,status)
  schema=op['responses'][status]['content']['application/json']['schema']
  Draft202012Validator({'$ref':'urn:pawday:m51'+schema['$ref']},registry=registry,format_checker=FormatChecker()).validate(sample['response'])
  count+=1;covered.add((method,path,status))
report={'result':'PASS','operations':len(operations),'new_membership_points_operations':sum(o['x-implemented-in']=='M5.1' for _,_,o in operations),'actual_http_responses_validated':count,'covered_responses':[list(x) for x in sorted(covered)]}
args.report.parent.mkdir(parents=True,exist_ok=True)
args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='covered_responses'}))
