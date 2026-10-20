"""Register implemented paid service operations; retain the B1/B2 historical contracts."""
import argparse,copy,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build():
 doc=json.loads((ROOT/'openapi/pawday-v3.1.3-b2.json').read_text(encoding='utf-8'));s=doc['components']['schemas']
 doc['info'].update(title='Pawday V3.1.3-B3 Synthetic Paid Service Operations',version='3.1.3-B3')
 ref=lambda n:{'$ref':'#/components/schemas/'+n}
 def obj(p):return dict(type='object',additionalProperties=False,properties=p,required=list(p))
 def string(values):return dict(type='string',enum=values)
 uid=dict(type='string',format='uuid');dt=dict(type='string',format='date-time');integer=dict(type='integer',minimum=0,maximum=9007199254740991);signed=dict(type='integer');sim=dict(type='boolean',const=True)
 for name in ['Proof','Reverify']:s[name]['properties']['action']['enum']+=['service.trade.dispute.review','service.trade.settle']
 s['ServiceTrade']['properties']['fulfillment_state']=string(['NOT_STARTED','CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION'])
 s['ServiceTrade']['properties']['settlement_state']=string(['NOT_PAYABLE','WAITING_COMPLETION','BUFFERING','FROZEN','ELIGIBLE','SETTLED','ADJUSTED'])
 for name in ['commission_fen','commission_reversed_fen','merchant_net_fen']:s['ServiceTrade']['properties'][name]['description']='Internal financial amounts withheld in the public trade projection; use scoped ledger for staff finance.'
 s['ServiceTradeCredential']=obj(dict(trade_id=uid,credential=dict(type='string',pattern='^[0-9a-f]{64}$'),valid_from=dt,expires_at=dt,simulated=sim))
 s['ServiceTradeFulfillmentInput']=obj(dict(status=string(['CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION']),credential=dict(type='string',maxLength=64),reason_code=string(['','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE'])))
 s['ServiceTradeFulfillmentEvent']=obj(dict(id=uid,trade_id=uid,version=integer,status=string(['CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION']),reason_code=string(['','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE']),occurred_at=dt,simulated=sim))
 evidence=dict(type='array',minItems=1,maxItems=20,items=ref('Evidence'))
 s['ServiceTradeDisputeInput']=obj(dict(reason_code=string(['SERVICE_QUALITY','BOOKING_MISMATCH','SAFETY_CONCERN']),evidence_refs=evidence))
 s['ServiceTradeDisputeDecisionInput']=obj(dict(decision=string(['RESOLVE_NO_FINANCIAL_CHANGE']),reason_code=string(['TEST_SCENARIO_REVIEWED']),evidence_refs=evidence))
 s['ServiceTradeDispute']=obj(dict(id=uid,trade_id=uid,version=integer,reason_code=string(['SERVICE_QUALITY','BOOKING_MISMATCH','SAFETY_CONCERN']),evidence_refs=evidence,opened_at=dt,state=string(['OPEN','RESOLVED']),resolved_at=dict(anyOf=[dt,dict(type='null')]),simulated=sim))
 s['ServiceTradeLedgerEntry']=obj(dict(id=uid,trade_id=uid,source_event_id=dict(anyOf=[uid,dict(type='null')]),settlement_id=dict(anyOf=[uid,dict(type='null')]),entry_type=string(['SERVICE_COLLECTION','SERVICE_COMMISSION','SERVICE_REFUND','SERVICE_COMMISSION_REVERSAL','SERVICE_SETTLEMENT','SERVICE_SETTLED_REFUND_ADJUSTMENT']),direction=string(['CREDIT','DEBIT']),amount_fen=dict(type='integer',minimum=1,maximum=1000000000),affects_balance=dict(type='boolean'),occurred_at=dt,simulated=sim))
 s['ServiceTradeSettlementPreview']=obj(dict(id=uid,merchant_id=uid,net_fen=dict(type='integer',minimum=0,maximum=1000000000),entry_count=dict(type='integer',minimum=0,maximum=10000),ledger_sha256=dict(type='string',pattern='^[0-9a-f]{64}$'),expires_at=dt,eligible=dict(type='boolean'),blocked_reasons=dict(type='array',uniqueItems=True,items=string(['TERMS_MISSING','OPEN_DISPUTE','UNKNOWN_PAYMENT','UNKNOWN_REFUND','WAITING_COMPLETION','BUFFER_NOT_DUE','NON_POSITIVE_BALANCE','CROSS_DOMAIN_DEBT'])),simulated=sim))
 s['ServiceTradeSettlementInput']=obj(dict(preview_id=uid,accepted_ledger_sha256=dict(type='string',pattern='^[0-9a-f]{64}$')))
 s['ServiceTradeSettlement']=obj(dict(id=uid,merchant_id=uid,net_fen=dict(type='integer',minimum=1,maximum=1000000000),state=string(['SETTLED']),version=dict(type='integer',const=0),simulated=sim))
 s['ServiceTradeReconciliation']=obj(dict(merchant_id=uid,goods_balance_fen=signed,service_balance_fen=signed,combined_balance_fen=signed,consistent=dict(type='boolean'),checks=dict(type='array',items=obj(dict(name=dict(type='string'),mismatches=integer))),as_of=dt,simulated=sim))
 def envelope(name,listing=False):
  n=name+('ListEnvelope' if listing else 'Envelope');p=dict(data=dict(type='array',items=ref(name)) if listing else ref(name),meta=ref('Meta'))
  if listing:p['page']=ref('Page')
  s[n]=obj(p);return n
 c='/consumer/service-trade-orders/{id}';m='/merchant/stores/{store_id}/service-trade-orders/{id}';a='/admin/service-trade-orders/{id}';mch='/admin/merchants/{merchant_id}'
 specs=[(c+'/credential','get','ServiceTradeCredential',None,False,False),(c+'/fulfillment','get','ServiceTradeFulfillmentEvent',None,True,False),(m+'/fulfillment','get','ServiceTradeFulfillmentEvent',None,True,False),(m+'/fulfillment','post','ServiceTrade','ServiceTradeFulfillmentInput',False,True),(c+'/disputes','get','ServiceTradeDispute',None,True,False),(c+'/disputes','post','ServiceTradeDispute','ServiceTradeDisputeInput',False,True),(m+'/disputes','get','ServiceTradeDispute',None,True,False),(a+'/disputes','get','ServiceTradeDispute',None,True,False),(a+'/disputes/{dispute_id}/decisions','post','ServiceTradeDispute','ServiceTradeDisputeDecisionInput',False,True),('/merchant/stores/{store_id}/service-trade-ledger','get','ServiceTradeLedgerEntry',None,True,False),(mch+'/service-trade-settlement-previews','post','ServiceTradeSettlementPreview','EmptyInput',False,False),(mch+'/service-trade-settlements','post','ServiceTradeSettlement','ServiceTradeSettlementInput',False,False),(mch+'/service-trade-reconciliation','get','ServiceTradeReconciliation',None,False,False)]
 for path,method,result,body,listing,match in specs:
  realm=path.split('/')[1];parameters=[dict(name=n,**{'in':'path'},required=True,schema=uid) for n in re.findall(r'\{([^}]+)\}',path)]
  if listing:parameters += [dict(name='cursor',**{'in':'query'},required=False,schema=uid),dict(name='limit',**{'in':'query'},required=False,schema=dict(type='integer',minimum=1,maximum=100,default=50))]
  if method=='post':parameters.append(dict(name='Idempotency-Key',**{'in':'header'},required=True,schema=dict(type='string',minLength=16,maxLength=128)))
  if match:parameters.append(dict(name='If-Match',**{'in':'header'},required=True,schema=dict(type='string',pattern='^"[0-9]{1,13}"$')))
  if path.endswith('/decisions') or path.endswith('/service-trade-settlements'):parameters.append(dict(name='X-Reverify-Token',**{'in':'header'},required=True,schema=dict(type='string')))
  response=lambda name,description:dict(description=description,content={'application/json':dict(schema=ref(name))})
  op=dict(operationId='v313b3_'+method+'_'+re.sub('[{}]','',path).replace('/','_').replace('-','_'),tags=[realm],summary='Synthetic paid service '+method+' '+path,description='Default off and non-production only. Separate paid credentials and immutable operational facts. Disputes resolve with no financial award. Settlement uses original frozen terms, cumulative half-up reversal, five-minute version/ledger snapshots and action-bound reverify. Database simulator only; no real payment or payout. Adjustment evidence with affects_balance=false must not be summed into balance.',security=[{realm+'Bearer':[]}],parameters=parameters,responses={'200':response(envelope(result,listing),'Implemented synthetic response'),**{code:response('ErrorEnvelope','Validation, authorization, hidden scope, conflict, pause or unavailable provider') for code in ['400','401','403','404','409','429','503']}},**{'x-implemented-in':'V3.1.3-B3'})
  if body:op['requestBody']=dict(required=True,content={'application/json':dict(schema=ref(body))})
  if path.endswith('/credential'):op['responses']['200']['headers']={'Cache-Control':dict(schema=dict(type='string',const='no-store'),description='Sensitive credential must not be cached')}
  doc['paths'].setdefault(path,{})[method]=op
 return doc
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args();path=ROOT/'openapi/pawday-v3.1.3-b3.json';value=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if args.check:assert path.read_text(encoding='utf-8')==value,'B3 runtime contract drift'
 else:path.write_bytes(value.encode('utf-8'))
 print('V3.1.3-B3 runtime contract consistent' if args.check else 'V3.1.3-B3 runtime contract generated')
