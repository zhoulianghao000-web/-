"""Validate every simulated booking operation against captured real HTTP responses."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--samples',type=Path,required=True)
p.add_argument('--report',type=Path,required=True)
a=p.parse_args()
doc=yaml.safe_load(Path(__file__).with_name('pawday-v3.1.yaml').read_text(encoding='utf-8'))
validate_spec(doc)
ops=[(path,m,op) for path,item in doc['paths'].items() for m,op in item.items() if isinstance(op,dict) and op.get('x-implemented-in')=='V3.1.1']
reg=Registry().with_resource('urn:pawday:v31',Resource.from_contents(doc,default_specification=DRAFT202012))
covered=set()
samples=json.loads(a.samples.read_text(encoding='utf-8'))
for sample in samples:
 path=urlsplit(sample['path']).path
 matches=[(route,m,op) for route,m,op in ops if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',route),path)]
 assert len(matches)==1,(path,sample['method'])
 route,method,op=matches[0]
 status=str(sample['status'])
 schema=op['responses'][status]['content']['application/json']['schema']
 Draft202012Validator({'$ref':'urn:pawday:v31'+schema['$ref']},registry=reg,format_checker=FormatChecker()).validate(sample['response'])
 covered.add((route,method,status))
assert {(route,m,'200') for route,m,_ in ops}<=covered,'Missing successful operation samples'
assert {'400','401','403','404','409'}<={status for _,_,status in covered},'Missing negative response evidence'
report={'result':'PASS','operations':len(ops),'actual_booking_responses':len(samples),'covered_responses':[list(x) for x in sorted(covered)]}
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
