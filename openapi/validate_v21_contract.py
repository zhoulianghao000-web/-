"""Validate V2.1 specification and captured actual HTTP responses."""
import argparse,json,re
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--samples',type=Path,required=True);parser.add_argument('--report',type=Path,required=True)
args=parser.parse_args();spec=yaml.safe_load(Path(__file__).with_name('pawday-v2.1.yaml').read_text(encoding='utf8'));validate_spec(spec)
operations=[(path,method,op) for path,item in spec['paths'].items() for method,op in item.items() if isinstance(op,dict) and 'responses' in op]
registry=Registry().with_resource('urn:pawday:v21',Resource.from_contents(spec,default_specification=DRAFT202012));covered=set();history_responses=0
for sample in json.loads(args.samples.read_text(encoding='utf8')):
 uri=urlsplit(sample['path']);matches=[(p,m,op) for p,m,op in operations if m==sample['method'] and re.fullmatch(re.sub(r'\{[^}]+\}',r'[^/]+',p),uri.path)]
 assert len(matches)==1,(sample['path'],sample['method'])
 p,m,op=matches[0];status=str(sample['status']);schema=op['responses'][status]['content']['application/json']['schema']
 Draft202012Validator({'$ref':'urn:pawday:v21'+schema['$ref']},registry=registry,format_checker=FormatChecker()).validate(sample['response'])
 if p.endswith('/price-history'):
  history_responses+=1;covered.add((p,status))
  if status=='200':
   data=sample['response']['data'];days=int(parse_qs(uri.query).get('days',['30'])[0]);assert len(data['points'])==days==data['days'];assert data['timezone']=='Asia/Shanghai'
   if p.startswith(('/public/','/consumer/')):
    assert all(x['publicly_recorded'] is True or (x['sale_price_fen'] is None and x['member_price_fen'] is None) for x in data['points'])
required={(f'/{realm}/offers/{{id}}/price-history','200') for realm in ['public','consumer','merchant','admin']}
required|={('/public/offers/{id}/price-history',s) for s in ['400','404']}
required|={('/merchant/offers/{id}/price-history',s) for s in ['401','403','404']}
required.add(('/admin/offers/{id}/price-history','403'));assert required<=covered,required-covered
report={'result':'PASS','operations':len(operations),'actual_history_responses':history_responses,'covered_responses':[list(x) for x in sorted(covered)]};args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report))
