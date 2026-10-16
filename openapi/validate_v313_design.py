"""Validate isolated draft schemas and synthetic examples; no runtime/HTTP claims."""
import argparse,copy,importlib.util,json,re,sys
from pathlib import Path
from openapi_spec_validator import validate_spec
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from service_trade_design_contract import DesignError,require,protected_tree,validate_snapshot,refund_commission_delta

def load_inputs():
 base=ROOT/'design/v3.1.3'
 return [json.loads(p.read_text(encoding='utf-8')) for p in [ROOT/'openapi/design/pawday-v3.1.3-draft.json',base/'synthetic-cases.json',base/'policy-gaps.json',base/'baseline.json']]

def validate_artifact(doc,fixtures,gaps,baseline):
 validate_spec(doc)
 require(doc.get('x-design-status')=='DRAFT_NOT_IMPLEMENTED' and doc.get('x-runtime-implemented') is False and doc.get('x-policy-status')=='PENDING_OWNER_RULES','DESIGN_BOUNDARY_REQUIRED')
 require(doc['servers']==[{'url':'https://design.invalid/api/v1','description':'Reserved invalid domain. No deployed service.'}],'DESIGN_SERVER_REQUIRED')
 require(baseline['protected_tree']==protected_tree(),'RUNTIME_BASELINE_CHANGED')
 require(baseline['runtime_contract']=='openapi/pawday-v3.1.2.yaml' and baseline['active_paid_service_routes'] is False,'ACTIVE_CONTRACT_CHANGED')
 active=(ROOT/'scripts/generate-api.mjs').read_text(encoding='utf-8');require('pawday-v3.1.2.yaml' in active and 'v3.1.3' not in active,'DRAFT_IN_RUNTIME_CODEGEN')
 require(gaps['status']=='PENDING_OWNER_RULES' and gaps['production_ready'] is False and len(gaps['gaps'])==12,'POLICY_GAP_MISMATCH')
 require(len({g['id'] for g in gaps['gaps']})==12 and all(g['status']=='PENDING' and g['evidence_ref'] is None and g['confirmed_value'] is None for g in gaps['gaps']),'UNSUPPORTED_RULE_CONFIRMATION')
 require(fixtures['evidence_kind']=='DESIGN_ONLY_SYNTHETIC' and fixtures['actual_http_responses']==0 and fixtures['runtime_verified'] is False,'SYNTHETIC_EVIDENCE_ONLY')
 operations=[]
 for path,item in doc['paths'].items():
  for method,op in item.items():
   require(op.get('x-design-status')=='DRAFT_NOT_IMPLEMENTED' and op.get('x-runtime-implemented') is False and 'x-implemented-in' not in op,'OPERATION_NOT_DRAFT')
   require(op['security']==[{path.split('/')[1]+'Bearer':[]}],'REALM_SECURITY_MISMATCH')
   params={p['name']:p for p in op.get('parameters',[])}
   if method!='get':require(params.get('Idempotency-Key',{}).get('required') is True,'IDEMPOTENCY_REQUIRED')
   if method!='get' and '{id}' in path:require(params.get('If-Match',{}).get('required') is True and op.get('x-version-resource') in ['ServiceTerms','ServiceTrade'],'VERSION_REQUIRED')
   if path.endswith(('/review','/refund-decisions','/service-trade-settlements')):require(params.get('X-Reverify-Token',{}).get('required') is True and bool(op.get('x-reverify-action')),'REVERIFY_REQUIRED')
   if path.startswith(('/admin/','/merchant/')):require(bool(op.get('x-proposed-permissions')),'SEPARATE_PERMISSION_REQUIRED')
   if path.endswith('/credential'):require(op['responses']['200']['headers']['Cache-Control']['schema']['const']=='no-store','CREDENTIAL_CACHE_FORBIDDEN')
   if 'requestBody' in op:
    name=op['requestBody']['content']['application/json']['schema']['$ref'].rsplit('/',1)[1]
    if name in ['CreateServiceTrade','ServiceAttemptInput','ConsumerCancelInput','MerchantCancelInput','RefundDecisionInput','ServiceSettlementInput']:
     forbidden={'amount_fen','paid_fen','payable_fen','outcome','receipt_id','merchant_net_fen'}
     require(not forbidden.intersection(doc['components']['schemas'][name]['properties']),'CLIENT_MONEY_OVERRIDE')
   operations.append((path,method,op))
 require(len(operations)==23,'OPERATION_COUNT_CHANGED')
 positive=negative=0
 require(len(fixtures['cases'])>=38 and len({c['name'] for c in fixtures['cases']})==len(fixtures['cases']),'CASE_COVERAGE_REQUIRED')
 for c in fixtures['cases']:
  require(c['name'].startswith('TEST_ONLY_'),'CASE_NOT_SYNTHETIC')
  error=None
  try:validate_snapshot(doc,c['schema'],c['value'])
  except DesignError as e:error=str(e)
  require(error==c['expected_error'],'CASE_EXPECTATION_MISMATCH:'+c['name']+':'+str(error))
  if error:negative+=1
  else:positive+=1
 for c in fixtures['commission_cases']:require(refund_commission_delta(c['paid'],c['commission'],c['refunded_total'],c['previous_reversed'])==c['expected_delta'],'COMMISSION_ROUNDING_MISMATCH')
 # Standalone structural request/response examples for EVERY proposed operation.
 schemas=doc['components']['schemas'];u='00000000-0000-4000-8000-000000000001'
 custom={c['schema']:c['value'] for c in fixtures['cases'] if c['expected_error'] is None}
 custom['RefundDecision']=next(c['value'] for c in fixtures['cases'] if c['name']=='TEST_ONLY_REJECT_REFUND_WITHOUT_INTENT')
 custom['TradeCredential']={'trade_id':u,'credential':'a'*64,'valid_from':'2030-01-02T00:30:00Z','expires_at':'2030-01-02T02:00:00Z','simulated':True}
 def example(schema):
  if '$ref' in schema:
   name=schema['$ref'].rsplit('/',1)[1]
   return copy.deepcopy(custom[name]) if name in custom else example(schemas[name])
  if 'const' in schema:return schema['const']
  if 'enum' in schema:return schema['enum'][0]
  if 'anyOf' in schema:return None if any(x.get('type')=='null' for x in schema['anyOf']) else example(schema['anyOf'][0])
  kind=schema.get('type')
  if kind=='object':return {k:example(v) for k,v in schema.get('properties',{}).items()}
  if kind=='array':return [example(schema['items']) for _ in range(schema.get('minItems',0))]
  if kind=='boolean':return False
  if kind=='integer':return schema.get('minimum',0)
  if kind=='string':
   if schema.get('format')=='uuid':return u
   if schema.get('format')=='date-time':return '2030-01-02T00:00:00Z'
   if schema.get('pattern','').startswith('^[0-9a-f]'):return 'a'*64
   if schema.get('pattern','').startswith('^TEST_ONLY_'):return 'TEST_ONLY_DESIGN'
   return 'TEST_ONLY_DESIGN'
  return None
 examples=0
 for path,method,op in operations:
  for schema in ([op['requestBody']['content']['application/json']['schema']] if 'requestBody' in op else [])+[op['responses']['200']['content']['application/json']['schema']]:
   name=schema['$ref'].rsplit('/',1)[1];validate_snapshot(doc,name,example(schema));examples+=1
 return {'result':'PASS','stage':'V3.1.3-A-DESIGN','evidence_kind':'DESIGN_ONLY_SYNTHETIC','runtime_verified':False,'implementation_complete':False,'actual_http_responses':0,'operations':len(operations),'request_response_schema_examples':examples,'positive_snapshot_cases':positive,'negative_snapshot_cases':negative,'commission_boundary_cases':len(fixtures['commission_cases']),'pending_rule_gaps':len(gaps['gaps']),'production_ready':False,'protected_runtime_tree_unchanged':True,'runtime_contract':baseline['runtime_contract'],'current_phone_version':baseline['runtime_version'],'phone_operations_performed':False}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args()
 spec=importlib.util.spec_from_file_location('design_composer',ROOT/'scripts/compose-v313-design.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 inputs=load_inputs();require(inputs[0]==module.build(),'GENERATED_DESIGN_DRIFT')
 report=validate_artifact(*inputs);a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
