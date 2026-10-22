"""Isolated ERP/WMS engineering proposal. Never included in runtime code generation."""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def build():
 ref=lambda n:{'$ref':'#/components/schemas/'+n}
 def obj(properties):return {'type':'object','additionalProperties':False,'properties':properties,'required':list(properties)}
 def integer(lo=0,hi=1_000_000_000):return {'type':'integer','minimum':lo,'maximum':hi}
 def array(schema,minimum=0,maximum=100):return {'type':'array','items':schema,'minItems':minimum,'maxItems':maximum}
 uid={'type':'string','format':'uuid'};date={'type':'string','format':'date-time'};sha={'type':'string','pattern':'^[0-9a-f]{64}$'};test={'type':'string','pattern':'^TEST_ONLY_[A-Za-z0-9_.:-]{1,100}$'};boolean={'type':'boolean'};nullable=lambda x:{'anyOf':[x,{'type':'null'}]}
 mode={'const':'SIMULATED_TEST'};basis={'const':'DEDICATED_REMAINING_AFTER_WATERMARK'};sim={'const':True};ver=integer(0,9_007_199_254_740_991)
 schemas={}
 schemas['Evidence']=obj({'kind':{'const':'TEST_SCENARIO'},'reference':test})
 schemas['Empty']=obj({})
 schemas['ConnectionInput']=obj({'label':test,'mode':mode,'inventory_basis':basis,'evidence_refs':array(ref('Evidence'),1,10)})
 schemas['ConnectionStateInput']=obj({'state':{'enum':['ACTIVE','PAUSED']},'reason_code':{'enum':['TEST_SCENARIO_START','OPERATOR_PAUSE']}})
 schemas['Connection']=obj({'id':uid,'merchant_id':uid,'store_id':uid,'label':test,'mode':mode,'inventory_basis':basis,'state':{'enum':['PAUSED','ACTIVE']},'version':ver,'simulated':sim})
 schemas['MappingInput']=obj({'offer_id':uid,'external_sku':test,'external_warehouse':test,'unit':{'const':'PIECE'},'evidence_refs':array(ref('Evidence'),1,10)})
 schemas['MappingStateInput']=obj({'state':{'const':'RETIRED'},'reason_code':{'const':'TEST_SCENARIO_RETIRED'}})
 schemas['Mapping']=obj({'id':uid,'connection_id':uid,'offer_id':uid,'external_sku':test,'external_warehouse':test,'unit':{'const':'PIECE'},'state':{'enum':['ACTIVE','RETIRED']},'version':ver,'simulated':sim})
 schemas['InventoryEvent']=obj({'id':uid,'connection_id':uid,'mapping_id':uid,'mapping_version':ver,'external_event_id':test,'external_version':integer(1),'external_remaining_qty':integer(),'acknowledged_local_sequence':ver,'acknowledgement_id':nullable(uid),'payload_sha256':sha,'observed_at':date,'simulated':sim})
 schemas['StockPreview']=obj({'id':uid,'event_id':uid,'mapping_id':uid,'inventory_version':ver,'local_sequence':ver,'on_hand_qty':integer(),'reserved_qty':integer(),'target_on_hand_qty':nullable(integer()),'delta_qty':nullable(integer(-1_000_000_000)),'snapshot_sha256':sha,'eligible':boolean,'blocked_reasons':array({'type':'string','minLength':1,'maxLength':80}),'created_at':date,'expires_at':date,'simulated':sim})
 schemas['StockApplyInput']=obj({'accepted_snapshot_sha256':sha})
 schemas['StockApplication']=obj({'id':uid,'preview_id':uid,'event_id':uid,'offer_id':uid,'before_on_hand_qty':integer(),'resulting_on_hand_qty':integer(),'reserved_qty':integer(),'resulting_inventory_version':ver,'simulated':sim})
 schemas['Delivery']=obj({'id':uid,'connection_id':uid,'suborder_id':uid,'business_key':test,'payload_sha256':sha,'state':{'enum':['READY','PROCESSING','UNKNOWN','ACCEPTED','REJECTED','NEEDS_REVIEW']},'attempt_count':integer(0,8),'responsibility_open':boolean,'version':ver,'simulated':sim})
 schemas['RetryInput']=obj({'reason_code':{'const':'TEST_SCENARIO_RETRY'}})
 schemas['ShipmentLine']=obj({'order_item_id':uid,'quantity':integer(1,100_000)})
 schemas['ShipmentEvent']=obj({'id':uid,'connection_id':uid,'delivery_id':uid,'external_event_id':test,'carrier_code':{'type':'string','pattern':'^[A-Z0-9_]{2,24}$'},'tracking_no':{'type':'string','pattern':'^[A-Za-z0-9-]{6,80}$'},'items':array(ref('ShipmentLine'),1),'payload_sha256':sha,'state':{'enum':['RECEIVED','APPLIED','CONFLICT','NEEDS_REVIEW']},'version':ver,'simulated':sim})
 schemas['ShipmentApplication']=obj({'id':uid,'event_id':uid,'shipment_id':uid,'suborder_id':uid,'version':ver,'simulated':sim})
 schemas['Reconciliation']=obj({'connection_id':uid,'mapping_conflicts':integer(),'stock_conflicts':integer(),'unknown_deliveries':integer(),'shipment_conflicts':integer(),'as_of':date,'simulated':sim})
 schemas['ResponsibilityInput']=obj({'decision':{'const':'ACKNOWLEDGE_FOR_MANUAL_REVIEW'},'reason_code':{'const':'TEST_SCENARIO_REVIEWED'},'evidence_refs':array(ref('Evidence'),1,10)})
 schemas['Responsibility']=obj({'id':uid,'connection_id':uid,'state':{'const':'NEEDS_REVIEW'},'responsibility_open':{'const':True},'version':ver,'simulated':sim})
 schemas['Error']=obj({'code':{'type':'string','minLength':1,'maxLength':100},'request_id':uid})
 schemas['Page']=obj({'has_more':boolean,'next_cursor':nullable(uid)})
 for name in ['Connection','Mapping','InventoryEvent','StockPreview','StockApplication','Delivery','ShipmentEvent','ShipmentApplication','Reconciliation','Responsibility']:
  schemas[name+'Envelope']=obj({'data':ref(name)})
  schemas[name+'ListEnvelope']=obj({'data':array(ref(name)),'page':ref('Page')})
 paths={}
 prefix='/merchant/stores/{store_id}/integration-connections'
 connection=prefix+'/{connection_id}'
 operations=[
  (prefix,'get',None,'ConnectionListEnvelope','integration.read',None,None,'B1'),
  (prefix,'post','ConnectionInput','ConnectionEnvelope','integration.manage','integration.manage',None,'B1'),
  (connection+'/state','put','ConnectionStateInput','ConnectionEnvelope','integration.manage','integration.manage','Connection','B1'),
  (connection+'/mappings','get',None,'MappingListEnvelope','integration.read',None,None,'B1'),
  (connection+'/mappings','post','MappingInput','MappingEnvelope','integration.mapping.write','integration.mapping.write','Connection','B1'),
  (connection+'/mappings/{mapping_id}/state','put','MappingStateInput','MappingEnvelope','integration.mapping.write','integration.mapping.write','Mapping','B1'),
  (connection+'/inventory-events','get',None,'InventoryEventListEnvelope','integration.read',None,None,'B1'),
  (connection+'/inventory-events/{event_id}/previews','post','Empty','StockPreviewEnvelope','integration.stock.assess',None,None,'B1'),
  (connection+'/inventory-previews/{preview_id}/apply','post','StockApplyInput','StockApplicationEnvelope','integration.stock.apply','integration.stock.apply',None,'B1'),
  (connection+'/inventory-applications','get',None,'StockApplicationListEnvelope','integration.read',None,None,'B1'),
  (connection+'/order-deliveries','get',None,'DeliveryListEnvelope','integration.read',None,None,'B2'),
  (connection+'/order-deliveries/{delivery_id}/requery','post','Empty','DeliveryEnvelope','integration.delivery.requery',None,'Delivery','B2'),
  (connection+'/order-deliveries/{delivery_id}/retry','post','RetryInput','DeliveryEnvelope','integration.delivery.retry','integration.delivery.retry','Delivery','B2'),
  (connection+'/shipment-events','get',None,'ShipmentEventListEnvelope','integration.read',None,None,'B3'),
  (connection+'/shipment-events/{event_id}/apply','post','Empty','ShipmentApplicationEnvelope','integration.shipment.apply','integration.shipment.apply','ShipmentEvent','B3'),
  (connection+'/reconciliation','get',None,'ReconciliationEnvelope','integration.read',None,None,'B3'),
  ('/admin/merchants/{merchant_id}/integration-connections','get',None,'ConnectionListEnvelope','integration.admin.read',None,None,'B3'),
  ('/admin/integration-responsibilities/{responsibility_id}/review','post','ResponsibilityInput','ResponsibilityEnvelope','integration.responsibility.review','integration.responsibility.review','Responsibility','B3')]
 for path,method,input_name,output,permission,proof,version,phase in operations:
  import re
  parameters=[{'in':'path','name':n,'required':True,'schema':uid} for n in re.findall(r'{([^}]+)}',path)]
  if method=='get' and output.endswith('ListEnvelope'):parameters += [{'in':'query','name':'cursor','schema':uid},{'in':'query','name':'limit','schema':integer(1,100)}]
  if method!='get':parameters.append({'in':'header','name':'Idempotency-Key','required':True,'schema':{'type':'string','minLength':16,'maxLength':128}})
  if version:parameters.append({'in':'header','name':'If-Match','required':True,'schema':{'type':'string','pattern':'^"[0-9]{1,16}"$'}})
  if proof:parameters.append({'in':'header','name':'X-Reverify-Token','required':True,'schema':{'type':'string','minLength':16,'maxLength':200}})
  realm=path.split('/')[1]
  op={'operationId':'v32design_'+method+'_'+path.replace('/','_').replace('{','').replace('}','').replace('-','_'),'summary':'Proposed synthetic ERP/WMS '+method+' '+path,'x-design-status':'DRAFT_NOT_IMPLEMENTED','x-runtime-implemented':False,'x-proposed-phase':'V3.2-'+phase,'x-proposed-permissions':[permission],'security':[{realm+'Bearer':[]}],'parameters':parameters,'responses':{'200':{'description':'Proposed synthetic result, not deployed.','content':{'application/json':{'schema':ref(output)}}}}}
  for code in ['400','401','403','404','409','503']:op['responses'][code]={'description':'Proposed failure; actual coverage required in implementation.','content':{'application/json':{'schema':ref('Error')}}}
  if '/shipment-events/' in path and method=='post':op['x-proposed-permissions'].append('order.ship')
  if input_name:op['requestBody']={'required':True,'content':{'application/json':{'schema':ref(input_name)}}}
  if version:op['x-version-resource']=version
  if proof:op['x-reverify-action']=proof
  paths.setdefault(path,{})[method]=op
 return {'openapi':'3.1.0','info':{'title':'Pawday V3.2 isolated ERP/WMS engineering design','version':'3.2.0-DRAFT'},'x-design-status':'DRAFT_NOT_IMPLEMENTED','x-runtime-implemented':False,'x-supplier-status':'PENDING_REAL_SYSTEM','servers':[{'url':'https://design.invalid/api/v1','description':'Reserved invalid domain; no deployed service.'}],'paths':paths,'components':{'securitySchemes':{r+'Bearer':{'type':'http','scheme':'bearer'} for r in ['merchant','admin']},'schemas':schemas}}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=ROOT/'openapi/design/pawday-v3.2-draft.json';data=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:assert path.read_text(encoding='utf-8')==data,'V32_DESIGN_DRIFT'
 else:path.parent.mkdir(parents=True,exist_ok=True);path.write_text(data,encoding='utf-8')
