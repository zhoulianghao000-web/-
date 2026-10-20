"""Compose implemented B2 service finance on the preserved B1 runtime contract."""
import argparse,copy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build():
 doc=json.loads((ROOT/'openapi/pawday-v3.1.3-b1.json').read_text(encoding='utf-8'))
 draft=json.loads((ROOT/'openapi/design/pawday-v3.1.3-draft.json').read_text(encoding='utf-8'))
 doc['info'].update(title='Pawday V3.1.3-B2 Synthetic Service Collections and Refunds',version='3.1.3-B2')
 schemas=doc['components']['schemas'];ref=lambda n:{'$ref':'#/components/schemas/'+n}
 for name in ['Proof','Reverify']:
  actions=schemas[name]['properties']['action']['enum']
  if 'service.trade.refund.review' not in actions:actions.append('service.trade.refund.review')
 for name in ['PaymentIntent','PaymentDetail']:schemas[name]['properties']['service_trade_id']={'anyOf':[{'type':'string','format':'uuid'},{'type':'null'}]}
 schemas['PaymentAttempt']['properties']['channel']['enum'].append('SIMULATED_TEST')
 schemas['PaymentDetail']['properties']['final_channel']['anyOf'][0]['enum'].append('SIMULATED_TEST')
 for name in ['EmptyInput','ServiceAttemptInput','ServicePayment','ConsumerCancelInput','MerchantCancelInput','RefundAssessment','RefundDecisionInput','ServiceRefund','RefundDecision','ServicePaymentEnvelope','ServiceRefundListEnvelope','RefundAssessmentEnvelope','RefundDecisionEnvelope']:
  schemas[name]=copy.deepcopy(draft['components']['schemas'][name])
 trade=schemas['ServiceTrade']
 for name in ['order_state','payment_state','capacity_state']:trade['properties'][name]=copy.deepcopy(draft['components']['schemas']['ServiceTrade']['properties'][name])
 trade['properties']['settlement_state']['enum']=['NOT_PAYABLE','WAITING_COMPLETION','FROZEN']
 for name in ['commission_fen','commission_reversed_fen','merchant_net_fen']:
  trade['properties'][name]={'anyOf':[copy.deepcopy(trade['properties'][name]),{'type':'null'}],'description':'B3 projection unavailable for paid trades; internal commission policy is not disclosed.'}
 paths=[('/consumer/service-trade-orders/{id}/payment-attempts','post'),('/consumer/service-trade-orders/{id}/payment-requery','post'),('/consumer/service-trade-orders/{id}/payment','get'),('/merchant/stores/{store_id}/service-trade-orders/{id}/cancel','post'),('/consumer/service-trade-orders/{id}/refunds','get'),('/admin/service-trade-orders/{id}/refund-assessments','post'),('/admin/service-trade-orders/{id}/refund-decisions','post')]
 for path,method in paths:
  op=copy.deepcopy(draft['paths'][path][method]);op={k:v for k,v in op.items() if not k.startswith('x-')}
  op['operationId']='v313b2_'+method+'_'+path.replace('{','').replace('}','').replace('/','_').replace('-','_')
  op['summary']='Synthetic service finance '+method+' '+path;op['x-implemented-in']='V3.1.3-B2'
  op['description']='Default off, non-production, both service simulation flags and an actual simulated payment adapter required. Client outcomes/amounts/receipts forbidden. Writes use idempotency and trade If-Match. UNKNOWN retains capacity and refund budget. Assessments expire after 5 minutes; review requires service.trade.refund.review and action-bound reverify. No goods side effects, real payment or settlement.'
  doc['paths'].setdefault(path,{})[method]=op
 cancel=doc['paths']['/consumer/service-trade-orders/{id}/cancel']['post']
 cancel['requestBody']['content']['application/json']['schema']={'oneOf':[ref('ServiceTradeEmpty'),ref('ConsumerCancelInput')]}
 cancel['description']='Unpaid B1 empty-body cancellation remains accepted; explicit CONSUMER_CANCELLED is also accepted. Paid cancellation before the frozen cutoff requests remaining original-route refund; pending refunds and late cancellation require review. Cancellation is not proof of refund arrival.'
 return doc
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();target=ROOT/'openapi/pawday-v3.1.3-b2.json';content=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
 if a.check:assert target.read_text(encoding='utf-8')==content,'B2 runtime contract drift'
 else:target.write_text(content,encoding='utf-8')
 print('V3.1.3-B2 contract '+('consistent' if a.check else 'generated'))
