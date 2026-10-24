"""Only the ten implemented B1 operations enter the runtime contract."""
import argparse,copy,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build():
 doc=json.loads((ROOT/'openapi/pawday-v3.1.3-b3.json').read_text(encoding='utf-8'));draft=json.loads((ROOT/'openapi/design/pawday-v3.2-draft.json').read_text(encoding='utf-8'));schemas=doc['components']['schemas']
 doc['info'].update(title='Pawday V3.2-B1 Synthetic Inventory Integration',version='3.2-B1')
 for n in ['Proof','Reverify']:schemas[n]['properties']['action']['enum']+=['integration.manage','integration.mapping.write','integration.stock.apply']
 def converted(value):
  if isinstance(value,list):return [converted(v) for v in value]
  if not isinstance(value,dict):return value
  out={k:converted(v) for k,v in value.items()}
  if '$ref' in out:out['$ref']=out['$ref'].replace('#/components/schemas/','#/components/schemas/Integration')
  if 'enum' in out:out.setdefault('type','string')
  if 'const' in out and out['const'] is not None:out.setdefault('type','boolean' if type(out['const']) is bool else 'string')
  return out
 def include(name):
  target='Integration'+name
  if target in schemas:return
  value=converted(draft['components']['schemas'][name]);schemas[target]=value
  for ref in re.findall(r'#/components/schemas/Integration([A-Za-z0-9]+)',json.dumps(value)):include(ref)
 def envelope(result,listing):
  name='Integration'+result+('ListEnvelope' if listing else 'Envelope');include(result)
  props=dict(data=dict(type='array',items={'$ref':'#/components/schemas/Integration'+result}) if listing else {'$ref':'#/components/schemas/Integration'+result},meta={'$ref':'#/components/schemas/Meta'})
  if listing:props['page']={'$ref':'#/components/schemas/Page'}
  schemas[name]=dict(type='object',additionalProperties=False,properties=props,required=list(props));return name
 prefix='/merchant/stores/{store_id}/integration-connections'
 specs=[('', 'get','Connection',None,True),('', 'post','Connection','ConnectionInput',False),('/{connection_id}/state','put','Connection','ConnectionStateInput',False),('/{connection_id}/mappings','get','Mapping',None,True),('/{connection_id}/mappings','post','Mapping','MappingInput',False),('/{connection_id}/mappings/{mapping_id}/state','put','Mapping','MappingStateInput',False),('/{connection_id}/inventory-events','get','InventoryEvent',None,True),('/{connection_id}/inventory-events/{event_id}/previews','post','StockPreview','Empty',False),('/{connection_id}/inventory-previews/{preview_id}/apply','post','StockApplication','StockApplyInput',False),('/{connection_id}/inventory-applications','get','StockApplication',None,True)]
 for suffix,method,result,body,listing in specs:
  path=prefix+suffix;proposal=draft['paths'][path][method];op={k:copy.deepcopy(v) for k,v in proposal.items() if k in ['parameters','security']}
  # Runtime UUID cursor paging follows existing publishing interfaces.
  op['parameters']=[p for p in op.get('parameters',[]) if p['in']!='query']
  if listing:op['parameters'] += [dict(name='cursor',**{'in':'query'},required=False,schema=dict(type='string',format='uuid')),dict(name='limit',**{'in':'query'},required=False,schema=dict(type='integer',minimum=1,maximum=100,default=50))]
  response=lambda n:dict(description='Implemented synthetic response',content={'application/json':dict(schema={'$ref':'#/components/schemas/'+n})})
  op.update(operationId='v32b1_'+method+'_'+re.sub('[{}]','',path).replace('/','_').replace('-','_'),summary='Synthetic inventory '+method+' '+path,description='Default off, non-production SIMULATED_TEST only. No client stock, watermark, provider endpoint, credential or result authority. Snapshots are owner-bound for exactly five minutes; immutable source and current scope are rechecked under locks.',tags=['merchant'],responses={'200':response(envelope(result,listing)),**{code:response('ErrorEnvelope') for code in ['400','401','403','404','409','429','503']}},**{'x-implemented-in':'V3.2-B1'})
  if body:include(body);op['requestBody']=dict(required=True,content={'application/json':dict(schema={'$ref':'#/components/schemas/Integration'+body})})
  doc['paths'].setdefault(path,{})[method]=op
 return doc
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=ROOT/'openapi/pawday-v3.2-b1.json';value=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:assert path.read_text(encoding='utf-8')==value,'B1 runtime contract drift'
 else:path.write_bytes(value.encode('utf-8'))
 print('V3.2-B1 ten implemented operations consistent')
