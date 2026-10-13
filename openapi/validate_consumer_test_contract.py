"""Validate bounded-request/gateway contracts and captured real HTTP error responses."""
import argparse
import json
from pathlib import Path
import re
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--samples',type=Path)
parser.add_argument('--disabled-samples',type=Path)
parser.add_argument('--require-coverage',action='store_true')
parser.add_argument('--report',type=Path,required=True)
args=parser.parse_args()
spec=yaml.safe_load(Path(__file__).with_name('pawday-v1.0.9.yaml').read_text(encoding='utf8'))
validate_spec(spec)
assert spec["paths"]["/consumer/auth/password-login"]["post"]["x-internal-test-only"] is True
assert spec['x-json-request-max-bytes']==3*1024*1024 and spec['x-media-request-max-bytes']==5*1024*1024
operations=[(path,method,op) for path,item in spec['paths'].items() for method,op in item.items() if isinstance(op,dict) and 'responses' in op]
for path,method,op in operations:
    for status in ['413','502']:
        assert op['responses'][status]['content']['application/json']['schema']['$ref']=='#/components/schemas/ErrorEnvelope'
registry=Registry().with_resource('urn:pawday:security',Resource.from_contents(spec,default_specification=DRAFT202012))
covered=set()
samples=json.loads(args.samples.read_text(encoding='utf8')) if args.samples else []
if args.disabled_samples:
    samples+=json.loads(args.disabled_samples.read_text(encoding='utf8'))
for sample in samples:
    matches=[(path,method,op) for path,method,op in operations if method==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',path),sample['path'])]
    assert len(matches)==1
    path,method,op=matches[0];status=str(sample['status']);assert status in op['responses']
    schema=op['responses'][status]['content']['application/json']['schema']
    Draft202012Validator({'$ref':'urn:pawday:security'+schema['$ref']},registry=registry,format_checker=FormatChecker()).validate(sample['response'])
    covered.add((method,path,status))
if args.require_coverage:
    assert {('post','/consumer/auth/password-login','200'),('post','/consumer/auth/password-login','401'),('post','/consumer/auth/password-login','429'),('post','/consumer/auth/password-login','503'),('post','/consumer/auth/phone/verify','403')}<=covered
    assert ('post','/consumer/auth/password-login','403') in covered
report={'result':'PASS','operations':len(operations),'actual_http_responses_validated':len(samples),'covered_responses':[list(x) for x in sorted(covered)]}
args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(json.dumps(report))
