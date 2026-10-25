"""Register only the three implemented goods delivery operations; preserve B1 and design history."""
import argparse,copy,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def build():
 doc=json.loads((ROOT/'openapi/pawday-v3.2-b1.json').read_text(encoding='utf-8'))
 draft=json.loads((ROOT/'openapi/design/pawday-v3.2-draft.json').read_text(encoding='utf-8'))
 doc['info'].update(title='Pawday V3.2-B2 Synthetic Goods Order Recovery',version='3.2-B2')
 schemas=doc['components']['schemas']
 for n in ['Proof','Reverify']:schemas[n]['properties']['action']['enum']+=['integration.delivery.retry']
 delivery=copy.deepcopy(draft['components']['schemas']['Delivery'])
 delivery['properties']['responsibility_open']['description']='Unresolved delivery result only. Consult fulfillment_hold_open for the independent native-write protection, including ACCEPTED.'
 delivery['properties']['fulfillment_hold_open']={'type':'boolean','description':'External fulfillment hold survives ACCEPTED. Only a proven matching REJECTED releases native automatic writes.'}
 delivery['required'].append('fulfillment_hold_open')
 delivery['allOf'].append({'if':{'properties':{'state':{'const':'REJECTED'}}},'then':{'properties':{'fulfillment_hold_open':{'const':False}}},'else':{'properties':{'fulfillment_hold_open':{'const':True}}}})
 def typed(value):
  if isinstance(value,list):return [typed(v) for v in value]
  if not isinstance(value,dict):return value
  v={k:typed(x) for k,x in value.items()}
  if 'enum' in v:v.setdefault('type','string')
  if 'const' in v:v.setdefault('type','boolean' if type(v['const']) is bool else 'string')
  return v
 schemas['IntegrationOrderDelivery']=typed(delivery)
 schemas['IntegrationOrderRetryInput']=typed(draft['components']['schemas']['RetryInput'])
 for listing in [False,True]:
  props={'data':{'type':'array','items':{'$ref':'#/components/schemas/IntegrationOrderDelivery'}} if listing else {'$ref':'#/components/schemas/IntegrationOrderDelivery'},'meta':{'$ref':'#/components/schemas/Meta'}}
  if listing:props['page']={'$ref':'#/components/schemas/Page'}
  schemas['IntegrationOrderDelivery'+('ListEnvelope' if listing else 'Envelope')]={'type':'object','additionalProperties':False,'properties':props,'required':list(props)}
 prefix='/merchant/stores/{store_id}/integration-connections/{connection_id}/order-deliveries'
 for suffix,method,body in [('', 'get',None),('/{delivery_id}/requery','post','IntegrationEmpty'),('/{delivery_id}/retry','post','IntegrationOrderRetryInput')]:
  path=prefix+suffix;proposal=draft['paths'][path][method];op={k:copy.deepcopy(v) for k,v in proposal.items() if k in ['parameters','security']}
  if method=='get':
   for param in op['parameters']:
    if param['name']=='limit':param['schema']['default']=50
  response=lambda n:dict(description='Implemented synthetic goods delivery response',content={'application/json':{'schema':{'$ref':'#/components/schemas/'+n}}})
  op.update(operationId='v32b2_'+method+'_'+re.sub('[{}]','',path).replace('/','_').replace('-','_'),summary='Synthetic goods order '+method+' '+path,tags=['merchant'],description='Default off; non-production SIMULATED_TEST only. Server declaration requires actual goods collection. Clients cannot choose outcomes or amounts. Fixed identity, query before send, 60-second lease, eight attempts; pause, revocation and exhaustion preserve external fulfillment responsibility. No shipment, stock-prefix ACK or consumer receipt is created. Retry replays its original claim and returns the current authorized state.',responses={'200':response('IntegrationOrderDelivery'+('ListEnvelope' if method=='get' else 'Envelope')),**{c:response('ErrorEnvelope') for c in ['400','401','403','404','409','429','503']}},**{'x-implemented-in':'V3.2-B2'})
  if body:op['requestBody']={'required':True,'content':{'application/json':{'schema':{'$ref':'#/components/schemas/'+body}}}}
  doc['paths'][path]={method:op}
 return doc

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=ROOT/'openapi/pawday-v3.2-b2.json';value=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:assert path.read_text(encoding='utf-8')==value,'B2 runtime contract drift'
 else:path.write_bytes(value.encode('utf-8'))
 print('V3.2-B2 three implemented operations consistent')
