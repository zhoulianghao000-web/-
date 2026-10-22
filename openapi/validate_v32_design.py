"""Validate isolated proposal and synthetic models; never counts them as real HTTP evidence."""
import argparse,copy,hashlib,importlib.util,json,re,subprocess,sys
from pathlib import Path
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
from openapi_spec_validator import validate_spec
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from erp_wms_design_contract import DesignError,require,digest,event_identity,stock_projection,delivery_result,paid_cancellation,shipment_application
PROTECTED=['backend/src/main/','backend/src/test/','consumer-app/flutter/','merchant-web/','admin-web/','packages/','deployment/','openapi/pawday-','scripts/generate-api.mjs','backend/pom.xml','package.json','pnpm-lock.yaml']

def load_inputs():return [json.loads(p.read_text(encoding='utf-8')) for p in [ROOT/'openapi/design/pawday-v3.2-draft.json',ROOT/'design/v3.2/synthetic-cases.json',ROOT/'design/v3.2/external-gaps.json',ROOT/'design/v3.2/runtime-baseline.json',ROOT/'design/v3.2/engineering-policy.json']]

def runtime_rows():
 files=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard'],cwd=ROOT,text=True,encoding='utf-8').splitlines()
 return [{'path':n,'sha256':hashlib.sha256((ROOT/n).read_bytes().replace(b'\r\n',b'\n')).hexdigest()} for n in sorted(set(n for n in files if any(n.startswith(p) for p in PROTECTED)))]

def validate_artifact(doc,fixtures,gaps,baseline,policy,actual_rows=None):
 validate_spec(doc)
 require(doc.get('x-design-status')=='DRAFT_NOT_IMPLEMENTED' and doc.get('x-runtime-implemented') is False and doc.get('x-supplier-status')=='PENDING_REAL_SYSTEM','DESIGN_BOUNDARY_REQUIRED')
 require(doc['servers']==[{'url':'https://design.invalid/api/v1','description':'Reserved invalid domain; no deployed service.'}],'DESIGN_SERVER_REQUIRED')
 require('openapi/design/' not in (ROOT/'scripts/generate-api.mjs').read_text(encoding='utf-8') and 'v3.2' not in (ROOT/'scripts/generate-api.mjs').read_text(encoding='utf-8'),'DRAFT_RUNTIME_CODEGEN_FORBIDDEN')
 require(baseline['source_commit']=='e024c322001e8267df6958a9dbcf6dc182f64000' and baseline['business_commit']=='3e90a4f22a03918ad73c82e1fb8b78634ec98750' and baseline['runtime_contract']=='openapi/pawday-v3.1.3-b3.json','RUNTIME_BASELINE_SOURCE_CHANGED')
 require(digest(baseline['rows'])==baseline['rows_sha256'] and (runtime_rows() if actual_rows is None else actual_rows)==baseline['rows'],'RUNTIME_SOURCE_CHANGED')
 require(len(gaps['gaps'])==12 and gaps['status']=='PENDING_REAL_SYSTEM' and gaps['production_ready'] is False and len({g['id'] for g in gaps['gaps']})==12 and all(g['status']=='PENDING' and g['confirmed_value'] is None and g['evidence_ref'] is None for g in gaps['gaps']),'EXTERNAL_RULES_NOT_CONFIRMED')
 require(policy['scope']=='SYNTHETIC_ENGINEERING_ONLY' and policy['modes']==['SIMULATED_TEST'] and policy['default_enabled'] is False and policy['production_allowed'] is False,'ENGINEERING_GATE_CHANGED')
 require(policy['stock']['basis']=='DEDICATED_REMAINING_AFTER_WATERMARK' and policy['stock']['preview_seconds']==300 and policy['stock']['invalid_projection_is_null_not_zero'] is True,'STOCK_POLICY_CHANGED')
 require(policy['recovery']['lease_seconds']==60 and policy['recovery']['max_automatic_attempts']==8 and policy['recovery']['query_before_resend'] is True and policy['recovery']['exhausted_retains_responsibility'] is True and policy['recovery']['old_lease_can_commit'] is False,'RECOVERY_POLICY_CHANGED')
 require(policy['ordering']['domain']=='GOODS_ONLY' and policy['ordering']['local_fence_before_external_io'] is True and policy['ordering']['unknown_or_accepted_export_automatic_paid_cancellation'] is False and policy['ordering']['consumer_receipt_from_external_scan'] is False,'FULFILLMENT_POLICY_CHANGED')
 schemas=doc['components']['schemas'];operations=[]
 permitted_inputs={'ConnectionInput','ConnectionStateInput','MappingInput','MappingStateInput','Empty','StockApplyInput','RetryInput','ResponsibilityInput'}
 forbidden={'outcome','endpoint','base_url','credential','password','api_key','secret','amount_fen','paid_fen','target_on_hand_qty','external_remaining_qty','receipt_id','acknowledged_local_sequence'}
 for path,item in doc['paths'].items():
  require(path.startswith(('/merchant/','/admin/')),'CONSUMER_INTEGRATION_ROUTE_FORBIDDEN')
  for method,op in item.items():
   require(op.get('x-design-status')=='DRAFT_NOT_IMPLEMENTED' and op.get('x-runtime-implemented') is False and 'x-implemented-in' not in op,'OPERATION_NOT_DRAFT')
   require(op['security']==[{path.split('/')[1]+'Bearer':[]}] and op.get('x-proposed-permissions'),'SCOPED_PERMISSION_REQUIRED')
   if '/shipment-events/' in path and method=='post':require('order.ship' in op['x-proposed-permissions'],'NATIVE_SHIPMENT_PERMISSION_REQUIRED')
   params={p['name']:p for p in op.get('parameters',[])}
   if method!='get':
    require(params.get('Idempotency-Key',{}).get('required') is True,'IDEMPOTENCY_REQUIRED')
    name=op['requestBody']['content']['application/json']['schema']['$ref'].rsplit('/',1)[1]
    require(name in permitted_inputs and not forbidden.intersection(schemas[name]['properties']) and schemas[name]['additionalProperties'] is False,'CLIENT_AUTHORITY_FORBIDDEN')
    sensitive=not path.endswith(('/previews','/requery'))
    if sensitive:require(params.get('X-Reverify-Token',{}).get('required') is True and bool(op.get('x-reverify-action')),'ACTION_PROOF_REQUIRED')
    if path.endswith(('/state','/retry','/requery','/review')) or method=='post' and path.endswith('/mappings') or path.endswith('/apply') and '/shipment-events/' in path:
     require(params.get('If-Match',{}).get('required') is True and bool(op.get('x-version-resource')),'VERSION_REQUIRED')
   require(set(['200','400','401','403','404','409','503'])<=set(op['responses']),'PROPOSED_FAILURE_RESPONSES_REQUIRED')
   operations.append((path,method,op))
 require(len(operations)==18,'OPERATION_COUNT_CHANGED')
 require(schemas['ConnectionInput']['properties']['mode']=={'const':'SIMULATED_TEST'} and schemas['Responsibility']['properties']['responsibility_open']=={'const':True},'SIMULATION_OR_RESPONSIBILITY_CHANGED')
 require(fixtures['evidence_kind']=='DESIGN_ONLY_SYNTHETIC' and fixtures['actual_http_responses']==0 and fixtures['runtime_verified'] is False and len(fixtures['cases'])==66,'SYNTHETIC_BOUNDARY_REQUIRED')
 require(len({c['name'] for c in fixtures['cases']})==66 and all(c['name'].startswith('TEST_ONLY_') for c in fixtures['cases']),'CASE_IDENTITY_INVALID')
 positive=negative=0;models={'stock':stock_projection,'delivery':delivery_result,'cancel':paid_cancellation,'shipment':shipment_application,'identity':lambda s:event_identity(s['previous'],s['current'])}
 for c in fixtures['cases']:
  error=None;result=None
  try:result=models[c['model']](c['input'])
  except DesignError as e:error=str(e)
  require(error==c['expected_error'],'CASE_ERROR_MISMATCH:'+c['name']+':'+str(error))
  if error is None:require(result==c['expected'],'CASE_RESULT_MISMATCH:'+c['name']);positive+=1
  else:negative+=1
 registry=Registry().with_resource('urn:pawday:v32-design',Resource.from_contents(doc,default_specification=DRAFT202012))
 def example(s):
  if '$ref' in s:return example(schemas[s['$ref'].rsplit('/',1)[1]])
  if 'const' in s:return s['const']
  if 'enum' in s:return s['enum'][0]
  if 'anyOf' in s:return None if any(t.get('type')=='null' for t in s['anyOf']) else example(s['anyOf'][0])
  kind=s.get('type')
  if kind=='object':return {k:example(v) for k,v in s['properties'].items()}
  if kind=='array':return [example(s['items']) for _ in range(s.get('minItems',0))]
  if kind=='integer':return s.get('minimum',0)
  if kind=='boolean':return False
  if kind=='string':
   if s.get('format')=='uuid':return '00000000-0000-4000-8000-000000000001'
   if s.get('format')=='date-time':return '2030-01-01T00:00:00Z'
   if s.get('pattern','').startswith('^[0-9a-f]'):return 'a'*64
   if s.get('pattern')=='^[A-Za-z0-9-]{6,80}$':return 'TESTONLY123'
   return 'TEST_ONLY_DESIGN'
  raise DesignError('UNSUPPORTED_EXAMPLE_SCHEMA')
 examples=0
 for _,_,op in operations:
  for schema in ([op['requestBody']['content']['application/json']['schema']] if 'requestBody' in op else [])+[op['responses']['200']['content']['application/json']['schema']]:
   validator=Draft202012Validator({'$ref':'urn:pawday:v32-design'+schema['$ref']},registry=registry,format_checker=FormatChecker())
   require(not list(validator.iter_errors(example(schema))),'STRUCTURAL_EXAMPLE_INVALID:'+schema['$ref']);examples+=1
 return {'result':'PASS','stage':'V3.2-A-DESIGN','evidence_kind':'DESIGN_ONLY_SYNTHETIC','operations':len(operations),'request_response_schema_examples':examples,'synthetic_model_cases':len(fixtures['cases']),'positive_cases':positive,'negative_cases':negative,'external_rule_gaps_pending':12,'runtime_source_files_unchanged':len(baseline['rows']),'actual_http_responses':0,'runtime_implemented':False,'real_supplier_verified':False,'final_end_to_end_acceptance_executed':False,'v32_development_complete':False,'v3_complete':False,'phone_operations_performed':False,'production_ready':False}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--report',required=True,type=Path);a=p.parse_args()
 spec=importlib.util.spec_from_file_location('v32_composer',ROOT/'scripts/compose-v32-design.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 inputs=load_inputs();require(inputs[0]==module.build(),'GENERATED_DESIGN_DRIFT');report=validate_artifact(*inputs);a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
