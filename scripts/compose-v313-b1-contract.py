"""Compose only implemented B1 operations; the A draft remains an unimplemented design archive."""
import argparse,copy,json,re
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
class RuntimeLoader(yaml.SafeLoader):
 """Match the existing runtime's YAML 1.2 boolean semantics (YES/NO are strings)."""
 yaml_implicit_resolvers={k:[(tag,pattern) for tag,pattern in values if tag!='tag:yaml.org,2002:bool'] for k,values in yaml.SafeLoader.yaml_implicit_resolvers.items()}
RuntimeLoader.add_implicit_resolver('tag:yaml.org,2002:bool',re.compile(r'^(?:true|True|TRUE|false|False|FALSE)$'),list('tTfF'))
def build():
 doc=yaml.load((ROOT/'openapi/pawday-v3.1.2.yaml').read_text(encoding='utf-8'),Loader=RuntimeLoader)
 draft=json.loads((ROOT/'openapi/design/pawday-v3.1.3-draft.json').read_text(encoding='utf-8'))
 doc['info'].update(title='Pawday V3.1.3-B1 Synthetic Service Terms Quotes and Unpaid Holds',version='3.1.3-B1')
 schemas=doc['components']['schemas'];ref=lambda n:{'$ref':'#/components/schemas/'+n}
 for schema in schemas.values():
  action=schema.get('properties',{}).get('action',{})
  if 'enum' in action and 'nearby.moderate' in action['enum'] and 'service.terms.review' not in action['enum']:action['enum'].append('service.terms.review')
 def obj(p):return {'type':'object','additionalProperties':False,'properties':p,'required':list(p)}
 names=['Evidence','ServiceTermsInput','ServiceTerms','ConsumerServiceTerms','TermsReviewInput','ServiceQuoteInput','ServiceQuote','CreateServiceTrade','ServiceTrade','ServiceTermsEnvelope','ServiceTermsListEnvelope','ConsumerServiceTermsEnvelope','ServiceQuoteEnvelope','ServiceTradeEnvelope','ServiceTradeListEnvelope']
 for n in names:schemas[n]=copy.deepcopy(draft['components']['schemas'][n])
 # Internal policy digest is not disclosed to consumers or in store order lists.
 del schemas['ServiceTrade']['properties']['policy_snapshot_sha256'];schemas['ServiceTrade']['required'].remove('policy_snapshot_sha256')
 for name,values in [('order_state',['AWAITING_PAYMENT','CANCELLED','EXPIRED']),('payment_state',['PENDING','CLOSED']),('capacity_state',['HELD','RELEASED']),('fulfillment_state',['NOT_STARTED']),('settlement_state',['NOT_PAYABLE'])]:schemas['ServiceTrade']['properties'][name]['enum']=values
 schemas['ServiceTradeEmpty']=obj({})
 selected=[(p,m) for p,v in draft['paths'].items() for m in v if p in ['/merchant/stores/{store_id}/service-trade-terms','/admin/service-trade-terms/{id}/review','/consumer/service-trade-terms/{id}','/consumer/service-trade-quotes','/consumer/service-trade-orders','/consumer/service-trade-orders/{id}','/merchant/stores/{store_id}/service-trade-orders']]
 for path,method in selected:
  op=copy.deepcopy(draft['paths'][path][method]);op={k:v for k,v in op.items() if not k.startswith('x-')};op['operationId']='v313b1_'+method+'_'+path.replace('{','').replace('}','').replace('/','_').replace('-','_');op['x-implemented-in']='V3.1.3-B1';op['summary']='Synthetic unpaid service trade '+method+' '+path
  op['description']='Default off; non-production and booking simulation required. Explicit TEST_SCENARIO only. B1 has no payment, refund or settlement authority. Quotes last at most 5 minutes and do not hold capacity; unpaid orders hold at most 10 minutes, bounded by slot start. Read/close owned orders remains available for hidden stores. UUID pagination. Separate service permissions and action-bound proof for terms review.'
  for response in op['responses'].values():
   if 'content' in response and response['content']['application/json']['schema'].get('$ref')=='#/components/schemas/ErrorEnvelope':response['content']['application/json']['schema']=ref('ErrorEnvelope')
  doc['paths'].setdefault(path,{})[method]=op
 # Discovery/recovery reads and unpaid cancellation needed for a usable B1 lifecycle.
 extras=[('/admin/service-trade-terms','get','/merchant/stores/{store_id}/service-trade-terms','get'),('/consumer/booking-services/{id}/trade-terms','get','/consumer/service-trade-terms/{id}','get'),('/consumer/service-trade-orders','get','/merchant/stores/{store_id}/service-trade-orders','get'),('/consumer/service-trade-orders/{id}/cancel','post','/consumer/service-trade-orders/{id}','get')]
 for path,method,source,sm in extras:
  op=copy.deepcopy(doc['paths'][source][sm]);realm=path.split('/')[1];op['security']=[{realm+'Bearer':[]}];op['operationId']='v313b1_'+method+'_'+path.replace('{','').replace('}','').replace('/','_').replace('-','_');op['parameters']=[p for p in op.get('parameters',[]) if p['in']!='path' or '{'+p['name']+'}' in path]
  if method=='post':
   op['parameters'] += [{'name':'Idempotency-Key','in':'header','required':True,'schema':{'type':'string','minLength':16,'maxLength':128}},{'name':'If-Match','in':'header','required':True,'schema':{'type':'string','pattern':'^"[0-9]{1,13}"$'}}]
   op['requestBody']={'required':True,'content':{'application/json':{'schema':ref('ServiceTradeEmpty')}}}
  op['summary']='Synthetic unpaid service trade '+method+' '+path;doc['paths'].setdefault(path,{})[method]=op
 return doc
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=ROOT/'openapi/pawday-v3.1.3-b1.json';output=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:assert path.read_text(encoding='utf-8')==output,'B1 runtime contract drift'
 else:path.write_text(output,encoding='utf-8')
