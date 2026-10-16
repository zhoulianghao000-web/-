"""Pure design snapshot validation, never a financial command or runtime authority."""
import hashlib,json
from pathlib import Path
from datetime import datetime
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012

ROOT=Path(__file__).resolve().parents[1]
PROTECTED_DIRS=['backend/src/main','consumer-app/flutter/lib','merchant-web/src','admin-web/src','packages/api-client/src','packages/web-shell/src']
PROTECTED_FILES=['consumer-app/flutter/pubspec.yaml','consumer-app/flutter/pubspec.lock','backend/pom.xml','scripts/generate-api.mjs','scripts/compose-v31-contract.mjs','scripts/compose-v312-contract.mjs','openapi/pawday-v3.1.yaml','openapi/pawday-v3.1.2.yaml','deployment/privacy/data-inventory.json']
def protected_tree(root=ROOT):
 files=set(PROTECTED_FILES)
 for directory in PROTECTED_DIRS:files.update(p.relative_to(root).as_posix() for p in (root/directory).rglob('*') if p.is_file())
 def normalized(path):
  data=path.read_bytes()
  if path.suffix.lower() in {'.java','.sql','.yml','.yaml','.json','.properties','.dart','.vue','.ts','.css','.html','.md','.xml','.mjs','.lock'}:data=data.replace(b'\r\n',b'\n')
  return data
 rows=[(name,hashlib.sha256(normalized(root/name)).hexdigest()) for name in sorted(files)]
 return {'files':len(rows),'sha256':hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()}

class DesignError(ValueError):pass
def require(ok,code):
 if not ok:raise DesignError(code)
def at(value):return datetime.fromisoformat(value.replace('Z','+00:00'))
def validate_snapshot(doc,schema,value):
 registry=Registry().with_resource('urn:pawday:service-trade-design',Resource.from_contents(doc,default_specification=DRAFT202012))
 validator=Draft202012Validator({'$ref':'urn:pawday:service-trade-design#/components/schemas/'+schema},registry=registry,format_checker=FormatChecker())
 require(not list(validator.iter_errors(value)),'SCHEMA_INVALID')
 if schema=='ServiceQuote':
  require(at(value['ends_at'])>at(value['starts_at'])>at(value['expires_at']),'QUOTE_TIME_INVALID')
 if schema=='ServiceTrade':
  paid=value['paid_fen'];refunded=value['refunded_fen'];reserved=value['refund_reserved_fen'];commission=value['commission_fen'];reversed_amount=value['commission_reversed_fen']
  require(refunded+reserved<=paid,'REFUND_EXCEEDS_COLLECTION')
  require(0<=reversed_amount<=commission<=paid,'COMMISSION_INVALID')
  require(value['merchant_net_fen']==paid-refunded-commission+reversed_amount,'NET_MISMATCH')
  require(at(value['hold_expires_at'])<=at(value['starts_at']),'HOLD_AFTER_START')
  succeeded=value['payment_state']=='SUCCEEDED'
  require((paid>0)==succeeded,'PAYMENT_FACT_MISMATCH')
  require(succeeded==(value['receipt_id'] is not None and value['confirmed_at'] is not None),'RECEIPT_REQUIRED')
  if not succeeded:require(value['receipt_id'] is None and value['confirmed_at'] is None,'UNCONFIRMED_RECEIPT')
  if succeeded:require(paid==value['payable_fen'],'COLLECTION_MISMATCH')
  if value['order_state']=='CONFIRMED':require(succeeded and value['capacity_state']=='CONFIRMED','TRADE_CONFIRMATION_INVALID')
  if value['order_state']=='AWAITING_PAYMENT':require(not succeeded and value['capacity_state']=='HELD','PENDING_HOLD_INVALID')
  if value['order_state'] in ['CANCELLED','EXPIRED']:require(value['capacity_state']=='RELEASED','TERMINAL_CAPACITY_INVALID')
  if value['payment_state']=='UNKNOWN':require(value['order_state']=='AWAITING_PAYMENT' and value['capacity_state']=='HELD','UNKNOWN_RELEASED')
  if value['fulfillment_state']!='NOT_STARTED':require(succeeded,'UNPAID_FULFILLMENT')
  if refunded==paid and paid>0:require(reversed_amount==commission,'FULL_REFUND_COMMISSION_REMAINS')
  if value['settlement_state'] in ['ELIGIBLE','PROCESSING','SETTLED']:
   require(value['order_state']=='CONFIRMED' and succeeded and value['fulfillment_state']=='COMPLETED' and reserved==0 and value['merchant_net_fen']>0 and not value['open_dispute'] and not value['unresolved_collection_case'] and value['settlement_buffer_ends_at'] is not None and at(value['settlement_buffer_ends_at'])<=at(value['as_of']),'SETTLEMENT_NOT_ELIGIBLE')
 if schema=='ServicePayment':
  succeeded=value['state']=='SUCCEEDED'
  require(succeeded==(value['collected_fen']>0 and value['receipt_id'] is not None),'PAYMENT_RECEIPT_INVALID')
  if not succeeded:require(value['receipt_id'] is None and value['collected_fen']==0,'UNCONFIRMED_RECEIPT')
 if schema=='RefundDecision':require((value['decision']=='APPROVE')==(value['refund_id'] is not None),'REFUND_DECISION_INVALID')
 if schema=='TradeCredential':require(at(value['valid_from'])<at(value['expires_at']),'CREDENTIAL_TIME_INVALID')
 if schema=='TradeFulfillmentInput':
  require((value['status']=='EXCEPTION')==(value['reason_code']!=''),'FULFILLMENT_REASON_INVALID')
  require((value['status']=='CHECKED_IN' and len(value['credential'])==64 and all(c in '0123456789abcdef' for c in value['credential'])) or (value['status']!='CHECKED_IN' and value['credential']==''),'FULFILLMENT_CREDENTIAL_INVALID')
 if schema=='ServiceSettlementPreview':require(value['eligible']==(value['net_fen']>0 and value['entry_count']>0 and not value['blocked_reasons']),'SETTLEMENT_PREVIEW_INVALID')

def refund_commission_delta(paid,commission,refunded_total,previous_reversed):
 # Integer half-up formula in the DESIGN, not a payment/refund implementation.
 require(all(type(n) is int for n in [paid,commission,refunded_total,previous_reversed]),'MONEY_INTEGER_REQUIRED')
 require(0<paid<=1_000_000_000 and 0<=commission<=paid and 0<=refunded_total<=paid and 0<=previous_reversed<=commission,'MONEY_OUT_OF_RANGE')
 target=(2*commission*refunded_total+paid)//(2*paid)
 require(target>=previous_reversed,'REVERSAL_CANNOT_REGRESS')
 return target-previous_reversed
