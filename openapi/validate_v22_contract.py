"""Validate V2.2 contract with credential-redacted real HTTP samples."""
import argparse,json,re
from pathlib import Path
from urllib.parse import urlsplit
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--samples',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
doc=yaml.safe_load(Path(__file__).with_name('pawday-v2.2.yaml').read_text(encoding='utf8'));validate_spec(doc)
ops=[(path,m,op) for path,item in doc['paths'].items() for m,op in item.items() if isinstance(op,dict) and 'responses' in op]
reg=Registry().with_resource('urn:pawday:v22',Resource.from_contents(doc,default_specification=DRAFT202012));covered=set();count=0
for sample in json.loads(a.samples.read_text(encoding='utf8')):
 path=urlsplit(sample['path']).path;matches=[(p,m,op) for p,m,op in ops if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',p),path)];assert len(matches)==1,(path,sample['method'])
 route,method,op=matches[0];status=str(sample['status']);schema=op['responses'][status]['content']['application/json']['schema']
 Draft202012Validator({'$ref':'urn:pawday:v22'+schema['$ref']},registry=reg,format_checker=FormatChecker()).validate(sample['response']);covered.add((route,method,status));count+=1
required={(path,m,str(next(k for k in op['responses'] if str(k).startswith('2')))) for path,m,op in ops if '/household' in path}
assert required<=covered,required-covered
assert {('/consumer/household/pets/{pet}','get',s) for s in ['401','403','404']}<=covered
assert ('/consumer/household/accept','post','429') in covered
report={'result':'PASS','operations':len(ops),'actual_household_responses':count,'covered_responses':[list(x) for x in sorted(covered)]};a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report))
