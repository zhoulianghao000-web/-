"""Compose the isolated, NOT IMPLEMENTED service trade design contract."""
import argparse,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def build():
 def ref(n):return {'$ref':'#/components/schemas/'+n}
 def obj(p):return {'type':'object','additionalProperties':False,'properties':p,'required':list(p)}
 def enum(*values):return {'type':'string','enum':list(values)}
 uuid={'type':'string','format':'uuid'};time={'type':'string','format':'date-time'};nullable_time={'anyOf':[time,{'type':'null'}]};nullable_uuid={'anyOf':[uuid,{'type':'null'}]}
 sha={'type':'string','pattern':'^[0-9a-f]{64}$'};money={'type':'integer','minimum':0,'maximum':1_000_000_000};positive={**money,'minimum':1};version={'type':'integer','minimum':0,'maximum':9_007_199_254_740_991};sim={'type':'boolean','const':True}
 s={}
 s['Meta']=obj({'request_id':uuid,'correlation_id':uuid})
 s['Page']=obj({'next_cursor':nullable_uuid,'has_more':{'type':'boolean'}})
 s['ErrorEnvelope']=obj({'error':obj({'code':{'type':'string','minLength':1},'message':{'type':'string','minLength':1},'retryable':{'type':'boolean'},'details':{'type':'object'}}),'meta':ref('Meta')})
 s['Evidence']=obj({'kind':enum('TEST_SCENARIO'),'reference':{'type':'string','pattern':'^TEST_ONLY_[A-Z0-9_-]{1,100}$'}})
 s['ServiceTermsInput']=obj({'service_id':uuid,'currency':enum('CNY'),'amount_fen':positive,'billing_unit':enum('WHOLE_SLOT'),'cancel_cutoff_minutes':{'type':'integer','minimum':0,'maximum':129600},'consumer_late_cancel':enum('MANUAL_REVIEW'),'merchant_cancel':enum('FULL_REFUND'),'no_show':enum('MANUAL_REVIEW'),'commission_basis_points':{'type':'integer','minimum':0,'maximum':10000},'settlement_buffer_minutes':{'type':'integer','minimum':0,'maximum':129600},'evidence_refs':{'type':'array','minItems':1,'maxItems':20,'items':ref('Evidence')}})
 s['ServiceTerms']=obj({'id':uuid,'store_id':uuid,**s['ServiceTermsInput']['properties'],'state':enum('DRAFT','REVIEWED','REJECTED','RETIRED'),'version':version,'terms_sha256':sha,'authorization_status':enum('ENGINEERING_SCENARIO_ONLY'),'simulated':sim})
 s['ServiceTerms']['properties'].update(policy_snapshot_sha256=sha,service_title={'type':'string','minLength':1,'maxLength':120},service_kind=enum('GROOMING','BOARDING'));s['ServiceTerms']['required']+=['policy_snapshot_sha256','service_title','service_kind']
 s['ConsumerServiceTerms']=obj({k:s['ServiceTerms']['properties'][k] for k in ['id','store_id','service_id','service_title','service_kind','currency','amount_fen','billing_unit','cancel_cutoff_minutes','consumer_late_cancel','merchant_cancel','no_show','version','terms_sha256','simulated']})
 s['TermsReviewInput']=obj({'decision':enum('APPROVE_SIMULATION','REJECT'),'reason_code':enum('TEST_SCENARIO_REVIEWED','RULES_INCOMPLETE')})
 s['ServiceQuoteInput']=obj({'terms_id':uuid,'slot_id':uuid})
 s['ServiceQuote']=obj({'id':uuid,'store_id':uuid,'service_id':uuid,'slot_id':uuid,'terms_id':uuid,'terms_version':version,'terms_sha256':sha,'currency':enum('CNY'),'payable_fen':positive,'starts_at':time,'ends_at':time,'expires_at':time,'capacity_held':{'type':'boolean','const':False},'simulated':sim})
 s['CreateServiceTrade']=obj({'quote_id':uuid,'accepted_terms_sha256':sha})
 s['ServiceTrade']=obj({'id':uuid,'store_id':uuid,'service_id':uuid,'slot_id':uuid,'terms_id':uuid,'terms_sha256':sha,'currency':enum('CNY'),'payable_fen':positive,'paid_fen':money,'refunded_fen':money,'refund_reserved_fen':money,'commission_fen':money,'commission_reversed_fen':money,'merchant_net_fen':money,'order_state':enum('AWAITING_PAYMENT','CONFIRMED','CANCELLED','EXPIRED'),'payment_state':enum('PENDING','PROCESSING','UNKNOWN','SUCCEEDED','CLOSED'),'capacity_state':enum('HELD','CONFIRMED','RELEASED'),'fulfillment_state':enum('NOT_STARTED','CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION'),'settlement_state':enum('WAITING_COMPLETION','BUFFERING','FROZEN','ELIGIBLE','PROCESSING','SETTLED','ADJUSTED','NOT_PAYABLE'),'hold_expires_at':time,'starts_at':time,'receipt_id':nullable_uuid,'confirmed_at':nullable_time,'as_of':time,'settlement_buffer_ends_at':nullable_time,'open_dispute':{'type':'boolean'},'unresolved_collection_case':{'type':'boolean'},'version':version,'simulated':sim})
 s['ServiceTrade']['properties']['policy_snapshot_sha256']=sha;s['ServiceTrade']['required'].append('policy_snapshot_sha256')
 s['ServiceAttemptInput']=obj({'channel':enum('SIMULATED_TEST'),'client_platform':enum('ANDROID','WEB')})
 s['ServicePayment']=obj({'id':uuid,'trade_id':uuid,'state':s['ServiceTrade']['properties']['payment_state'],'attempt_id':nullable_uuid,'receipt_id':nullable_uuid,'collected_fen':money,'currency':enum('CNY'),'version':version,'simulated':sim})
 s['EmptyInput']=obj({})
 s['ConsumerCancelInput']=obj({'reason_code':enum('CONSUMER_CANCELLED')})
 s['MerchantCancelInput']=obj({'reason_code':enum('SERVICE_UNAVAILABLE')})
 s['RefundAssessment']=obj({'id':uuid,'trade_id':uuid,'terms_sha256':sha,'proposed_refund_fen':money,'basis_code':enum('BEFORE_CUTOFF','MERCHANT_CANCEL','MANUAL_REVIEW_REQUIRED'),'eligible_for_approval':{'type':'boolean'},'expires_at':time,'trade_version':version,'simulated':sim})
 s['RefundDecisionInput']=obj({'assessment_id':uuid,'decision':enum('APPROVE','REJECT'),'reason_code':enum('SNAPSHOT_RULES_APPLY','EVIDENCE_INSUFFICIENT')})
 s['ServiceRefund']=obj({'id':uuid,'trade_id':uuid,'amount_fen':positive,'state':enum('RESERVED','PROCESSING','UNKNOWN','SUCCEEDED','FAILED_RETRYABLE','NEEDS_REVIEW'),'version':version,'simulated':sim})
 s['RefundDecision']=obj({'id':uuid,'trade_id':uuid,'assessment_id':uuid,'decision':enum('APPROVE','REJECT'),'refund_id':nullable_uuid,'version':version,'simulated':sim})
 s['TradeCredential']=obj({'trade_id':uuid,'credential':sha,'valid_from':time,'expires_at':time,'simulated':sim})
 s['TradeFulfillmentInput']=obj({'status':enum('CHECKED_IN','COMPLETED','NO_SHOW','EXCEPTION'),'credential':{'type':'string','maxLength':64},'reason_code':enum('','SERVICE_UNAVAILABLE','SAFETY_STOP','CUSTOMER_DISPUTE')})
 s['TradeFulfillmentEvent']=obj({'id':uuid,'trade_id':uuid,'status':s['TradeFulfillmentInput']['properties']['status'],'reason_code':s['TradeFulfillmentInput']['properties']['reason_code'],'occurred_at':time,'version':version,'simulated':sim})
 s['ServiceLedgerEntry']=obj({'id':uuid,'trade_id':uuid,'source_event_id':uuid,'entry_type':enum('SERVICE_COLLECTION','SERVICE_COMMISSION','SERVICE_REFUND','SERVICE_COMMISSION_REVERSAL','SERVICE_SETTLEMENT','SERVICE_SETTLED_REFUND_ADJUSTMENT'),'direction':enum('CREDIT','DEBIT'),'amount_fen':positive,'occurred_at':time,'simulated':sim})
 s['ServiceSettlementPreview']=obj({'id':uuid,'merchant_id':uuid,'net_fen':money,'entry_count':{'type':'integer','minimum':0,'maximum':10000},'ledger_sha256':sha,'expires_at':time,'eligible':{'type':'boolean'},'blocked_reasons':{'type':'array','items':enum('UNKNOWN_PAYMENT','UNKNOWN_REFUND','OPEN_DISPUTE','BUFFER_NOT_DUE','TERMS_MISSING','NON_POSITIVE_BALANCE')},'simulated':sim})
 s['ServiceSettlementInput']=obj({'preview_id':uuid,'accepted_ledger_sha256':sha})
 s['ServiceSettlement']=obj({'id':uuid,'merchant_id':uuid,'net_fen':positive,'state':enum('PROCESSING','UNKNOWN','SETTLED','FAILED_RETRYABLE','NEEDS_REVIEW'),'version':version,'simulated':sim})
 for name in ['ServiceTerms','ConsumerServiceTerms','ServiceQuote','ServiceTrade','ServicePayment','RefundAssessment','RefundDecision','ServiceRefund','TradeCredential','TradeFulfillmentEvent','ServiceLedgerEntry','ServiceSettlementPreview','ServiceSettlement']:
  s[name+'Envelope']=obj({'data':ref(name),'meta':ref('Meta')})
  s[name+'ListEnvelope']=obj({'data':{'type':'array','items':ref(name)},'page':ref('Page'),'meta':ref('Meta')})
 # method, path, output schema, input, list, version, proposed permission, sensitive proof action
 operations=[
 ('get','/merchant/stores/{store_id}/service-trade-terms','ServiceTerms',None,True,False,'service.trade.terms.read',None),
 ('post','/merchant/stores/{store_id}/service-trade-terms','ServiceTerms','ServiceTermsInput',False,False,'service.trade.terms.write',None),
 ('post','/admin/service-trade-terms/{id}/review','ServiceTerms','TermsReviewInput',False,True,'service.trade.terms.review','service.trade.terms.review'),
 ('get','/consumer/service-trade-terms/{id}','ConsumerServiceTerms',None,False,False,None,None),
 ('post','/consumer/service-trade-quotes','ServiceQuote','ServiceQuoteInput',False,False,None,None),
 ('post','/consumer/service-trade-orders','ServiceTrade','CreateServiceTrade',False,False,None,None),
 ('get','/consumer/service-trade-orders/{id}','ServiceTrade',None,False,False,None,None),
 ('get','/merchant/stores/{store_id}/service-trade-orders','ServiceTrade',None,True,False,'service.trade.read',None),
 ('post','/consumer/service-trade-orders/{id}/payment-attempts','ServicePayment','ServiceAttemptInput',False,True,None,None),
 ('post','/consumer/service-trade-orders/{id}/payment-requery','ServicePayment','EmptyInput',False,True,None,None),
 ('get','/consumer/service-trade-orders/{id}/payment','ServicePayment',None,False,False,None,None),
 ('post','/consumer/service-trade-orders/{id}/cancel','ServiceTrade','ConsumerCancelInput',False,True,None,None),
 ('post','/merchant/stores/{store_id}/service-trade-orders/{id}/cancel','ServiceTrade','MerchantCancelInput',False,True,'service.trade.cancel',None),
 ('get','/consumer/service-trade-orders/{id}/refunds','ServiceRefund',None,True,False,None,None),
 ('post','/admin/service-trade-orders/{id}/refund-assessments','RefundAssessment','EmptyInput',False,True,'service.trade.refund.assess',None),
 ('post','/admin/service-trade-orders/{id}/refund-decisions','RefundDecision','RefundDecisionInput',False,True,'service.trade.refund.review','service.trade.refund.review'),
 ('get','/consumer/service-trade-orders/{id}/credential','TradeCredential',None,False,False,None,None),
 ('get','/consumer/service-trade-orders/{id}/fulfillment','TradeFulfillmentEvent',None,True,False,None,None),
 ('get','/merchant/stores/{store_id}/service-trade-orders/{id}/fulfillment','TradeFulfillmentEvent',None,True,False,'service.trade.read',None),
 ('post','/merchant/stores/{store_id}/service-trade-orders/{id}/fulfillment','ServiceTrade','TradeFulfillmentInput',False,True,'service.trade.fulfill',None),
 ('get','/merchant/stores/{store_id}/service-trade-ledger','ServiceLedgerEntry',None,True,False,'service.trade.finance.read',None),
 ('post','/admin/merchants/{merchant_id}/service-trade-settlement-previews','ServiceSettlementPreview','EmptyInput',False,False,'service.trade.settlement.preview',None),
 ('post','/admin/merchants/{merchant_id}/service-trade-settlements','ServiceSettlement','ServiceSettlementInput',False,False,'service.trade.settle','service.trade.settle'),
 ]
 paths={}
 for method,path,output,body,is_list,match,permission,proof in operations:
  realm=path.split('/')[1];params=[{'name':n,'in':'path','required':True,'schema':uuid} for n in __import__('re').findall(r'\{([^}]+)\}',path)]
  if is_list:params += [{'name':'cursor','in':'query','schema':uuid},{'name':'limit','in':'query','schema':{'type':'integer','minimum':1,'maximum':100,'default':50}}]
  if body:params.append({'name':'Idempotency-Key','in':'header','required':True,'schema':{'type':'string','minLength':16,'maxLength':128}})
  if match:params.append({'name':'If-Match','in':'header','required':True,'schema':{'type':'string','pattern':'^"[0-9]{1,13}"$'}})
  if proof:params.append({'name':'X-Reverify-Token','in':'header','required':True,'schema':{'type':'string','minLength':1}})
  responses={'200':{'description':'Proposed synthetic response; not runtime evidence','content':{'application/json':{'schema':ref(output+('ListEnvelope' if is_list else 'Envelope'))}}}}
  for code in ['400','401','403','404','409','429','503']:responses[code]={'description':'Validation, scope, unavailable terms, stale quote/version, capacity/payment/refund/settlement conflict or disabled feature','content':{'application/json':{'schema':ref('ErrorEnvelope')}}}
  op={'operationId':'draft_v313_'+method+'_'+path.replace('/','_').replace('-','_').replace('{','').replace('}',''),'tags':[realm],'summary':'DRAFT NOT IMPLEMENTED '+method+' '+path,'description':'Proposal only. Default-off non-production simulation with explicit TEST_SCENARIO terms; no actual money movement or accepted real merchant rules. Ownership and current store scope must be checked before idempotency replay. Assessment/preview snapshots create no financial intent. Missing terms fail closed. Refund and settlement decisions consume immutable server assessments with scope, version and expiry checks. Rejected refund decisions create no refund. Fulfillment requires confirmed collection; raw receipts are server-originated.','security':[{realm+'Bearer':[]}],'parameters':params,'responses':responses,'x-design-status':'DRAFT_NOT_IMPLEMENTED','x-runtime-implemented':False,'x-proposed-permissions':[] if permission is None else [permission],'x-reverify-action':proof}
  if match:op['x-version-resource']='ServiceTerms' if '/service-trade-terms/' in path else 'ServiceTrade'
  if path.endswith('/credential'):op['responses']['200']['headers']={'Cache-Control':{'schema':{'type':'string','const':'no-store'}}}
  if body:op['requestBody']={'required':True,'content':{'application/json':{'schema':ref(body)}}}
  paths.setdefault(path,{})[method]=op
 return {'openapi':'3.1.0','info':{'title':'Pawday service trade design — NOT IMPLEMENTED','version':'3.1.3-design.1','description':'V3.1.3-A design artifact. Synthetic schema examples are not HTTP responses. Active client contract remains pawday-v3.1.2.yaml. Real merchant policies remain PENDING.'},'servers':[{'url':'https://design.invalid/api/v1','description':'Reserved invalid domain. No deployed service.'}],'x-design-status':'DRAFT_NOT_IMPLEMENTED','x-runtime-implemented':False,'x-policy-status':'PENDING_OWNER_RULES','paths':paths,'components':{'securitySchemes':{realm+'Bearer':{'type':'http','scheme':'bearer'} for realm in ['consumer','merchant','admin']},'schemas':s}}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();path=ROOT/'openapi/design/pawday-v3.1.3-draft.json';data=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:
  if path.read_text(encoding='utf-8')!=data:raise SystemExit('Service trade design contract drift')
 else:path.parent.mkdir(parents=True,exist_ok=True);path.write_text(data,encoding='utf-8')
 print('V3.1.3-A isolated design contract '+('consistent' if a.check else 'generated'))
