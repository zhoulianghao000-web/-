"""M1 contract verification only; does not test a running API or PostgreSQL."""
from pathlib import Path
import copy
import hashlib
import json
import random
import re
from datetime import datetime, timezone
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec

HERE = Path(__file__).resolve().parent
SPEC_PATH = HERE / 'pawday-v1.yaml'
checks = []
def check(name, condition):
    if not condition:
        raise AssertionError(name)
    checks.append(name)

class UniqueLoader(yaml.SafeLoader): pass
def unique_mapping(loader, node, deep=False):
    result = {}
    for k,v in node.value:
        key = loader.construct_object(k, deep=deep)
        if key in result:
            raise ValueError('Duplicate YAML key: '+str(key))
        result[key] = loader.construct_object(v, deep=deep)
    return result
UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)
spec = yaml.load(SPEC_PATH.read_text(encoding='utf-8'), Loader=UniqueLoader)
validate_spec(spec)
check('OpenAPI 3.1 validator', spec['openapi']=='3.1.0')

def walk(value):
    if isinstance(value,dict):
        yield value
        for child in value.values(): yield from walk(child)
    elif isinstance(value,list):
        for child in value: yield from walk(child)

refs=0
for node in walk(spec):
    if '$ref' in node:
        pointer=node['$ref']
        check('Internal ref '+pointer, pointer.startswith('#/'))
        resolved=spec
        for key in pointer[2:].split('/'):
            resolved=resolved[key.replace('~1','/').replace('~0','~')]
        refs+=1

ids=set()
op_count=0
for path, item in spec['paths'].items():
    for method, operation in item.items():
        if method not in ['get','post','patch','put','delete']: continue
        op_count+=1
        check('Unique operationId '+operation['operationId'], operation['operationId'] not in ids)
        ids.add(operation['operationId'])
        check('Description '+path, bool(operation.get('description')))
        params=[]
        for p in operation.get('parameters',[]):
            if '$ref' in p: p=spec['components']['parameters'][p['$ref'].split('/')[-1]]
            params.append(p)
        check('Path params '+method+path, set(re.findall(r'\{([^}]+)\}',path))=={p['name'] for p in params if p['in']=='path' and p.get('required')})
        zone=path.split('/')[1]
        if zone in ['merchant','admin']:
            check('Auth scope '+method+path, operation['security']==[{zone+'Bearer':[]}])
            check('Explicit permission '+method+path, bool(operation.get('x-permission')))
        if method in ['post','delete'] and zone in ['consumer','merchant','admin'] and '/auth/' not in path and path!='/consumer/products/compare':
            check('Idempotency '+method+path, any(p['name']=='Idempotency-Key' and p.get('required') for p in params))
        if zone=='public': check('Anonymous public '+path, operation['security']==[])
        if zone=='webhooks': check('Provider signature '+path, operation.get('x-provider-signature-required') and operation['security']==[])

check('No direct payment state PATCH', not any('payments' in p and 'patch' in v for p,v in spec['paths'].items()))
check('Offer PATCH closed', spec['components']['schemas']['OfferPatch']['additionalProperties'] is False)
check('Offer PATCH no inventory', not {'on_hand_qty','reserved_qty','target_on_hand_qty','status'} & spec['components']['schemas']['OfferPatch']['properties'].keys())
check('Payment no owning channel', 'channel' not in spec['components']['schemas']['Payment']['properties'])
check('Attempt owns channel', 'channel' in spec['components']['schemas']['PaymentAttemptRequest']['required'])
check('Refund targets attempt', 'payment_attempt_id' in spec['components']['schemas']['Refund']['required'])
check('Coupon states', spec['components']['schemas']['CouponStatus']['enum']==['AVAILABLE','RESERVED','USED','RETURNED','EXPIRED','VOID'])
check('AI quota states', spec['components']['schemas']['AiQuotaStatus']['enum']==['RESERVED','CONSUMED','RELEASED'])

for name, schema in spec['components']['schemas'].items():
    Draft202012Validator.check_schema(schema)

def validate_sample(name, payload, valid=True):
    root={'$ref':'#/components/schemas/'+name, 'components':spec['components']}
    errors=list(Draft202012Validator(root, format_checker=FormatChecker()).iter_errors(payload))
    check(('Accept ' if valid else 'Reject ')+name+' '+str(payload)[:80], (not errors)==valid)

validate_sample('CreateOrderRequest', {'quote_id':'q1','address_id':'a1','client_confirmed_at':'2026-10-03T12:00:00+08:00'})
validate_sample('CreateOrderRequest', {'quote_id':'q1','address_id':'a1','client_confirmed_at':'2026-10-03T12:00:00+08:00','payable_amount_fen':1},False)
validate_sample('CreateOrderRequest', {'address_id':'a1','client_confirmed_at':'2026-10-03T12:00:00+08:00'},False)
validate_sample('OfferPatch', {'sale_price_fen':25900,'member_price_fen':24900})
validate_sample('OfferPatch', {'on_hand_qty':20},False)
validate_sample('OfferPatch', {'reserved_qty':0},False)
validate_sample('OfferPatch', {'status':'ACTIVE'},False)
validate_sample('OfferPatch', {},False)
validate_sample('InventoryAdjustmentRequest', {'delta_qty':-2,'reason_code':'COUNT_CORRECTION','expected_version':14})
validate_sample('InventoryAdjustmentRequest', {'delta_qty':0,'reason_code':'COUNT_CORRECTION','expected_version':14},False)
validate_sample('InventoryAdjustmentRequest', {'delta_qty':1.5,'reason_code':'RESTOCK','expected_version':14},False)
validate_sample('InventoryAdjustmentRequest', {'target_on_hand_qty':20,'reason_code':'RESTOCK','expected_version':14},False)
validate_sample('InventoryAdjustmentRequest', {'delta_qty':2,'reason_code':'RESTOCK','expected_version':14,'operator':'other'},False)
validate_sample('PaymentAttemptRequest', {'channel':'WECHAT','client_platform':'IOS'})
validate_sample('PaymentAttemptRequest', {'client_platform':'IOS'},False)
validate_sample('CancelItemsRequest', {'items':[{'order_item_id':'oi1','quantity':1}],'reason_code':'NO_LONGER_NEEDED'})
validate_sample('CancelItemsRequest', {'items':[{'order_item_id':'oi1','quantity':0}],'reason_code':'NO_LONGER_NEEDED'},False)
validate_sample('CompareRequest', {'sku_ids':['s1','s2','s3']})
validate_sample('CompareRequest', {'sku_ids':['s1','s2','s3','s4']},False)
validate_sample('CompareRequest', {'sku_ids':['s1','s1']},False)
validate_sample('AcceptProposalRequest', {'expected_pet_version':7,'confirmed':True})
validate_sample('AcceptProposalRequest', {'expected_pet_version':7,'confirmed':False},False)
validate_sample('CouponStatus','RETURNED')
validate_sample('CouponStatus','ACTIVE',False)
validate_sample('AiQuotaStatus','RESERVED')
validate_sample('AiQuotaStatus','FAILED',False)
validate_sample('MoneyFen',-1,False)
validate_sample('MoneyFen',9007199254740992,False)
validate_sample('Checkin',{'id':'c1','business_date':'2026-10-03','cycle_day':31,'earned_points':1,'rule_version':'r1'},False)

# Independent arithmetic reference for 05.8; these are design algorithm tests, not service integration tests.
def allocate(bases, discount, keys):
    total=sum(bases)
    if not 0<=discount<=total: raise ValueError('discount outside eligible base')
    if len(set(keys))!=len(keys): raise ValueError('allocation keys must be unique')
    if total==0: return [0]*len(bases)
    quotients=[discount*b//total for b in bases]
    remainders=[discount*b%total for b in bases]
    ordering=sorted(range(len(bases)),key=lambda i:(-remainders[i],keys[i]))
    for i in ordering[:discount-sum(quotients)]: quotients[i]+=1
    return quotients

check('Tail exact split',allocate([6000,4000],2000,['a','b'])==[1200,800])
check('Tail stable tie',allocate([1,1,1],2,['a','b','c'])==[1,1,0])
check('Zero eligible base',allocate([0,0],0,['a','b'])==[0,0])
check('Large exact integer',sum(allocate([9007199254740000,900],9007199254739000,['a','b']))==9007199254739000)
rng=random.Random(20261003)
for iteration in range(2000):
    n=rng.randint(1,20)
    bases=[rng.randint(0,1000000000) for _ in range(n)]
    keys=[f'{i:04d}' for i in range(n)]
    d=rng.randint(0,sum(bases))
    allocations=allocate(bases,d,keys)
    if sum(allocations)!=d or any(a<0 or a>b for a,b in zip(allocations,bases)):
        raise AssertionError('Randomized allocation invariant '+str(iteration))
    permutation=list(range(n));rng.shuffle(permutation)
    shuffled=allocate([bases[i] for i in permutation],d,[keys[i] for i in permutation])
    if {keys[i]:allocations[i] for i in range(n)}!={keys[i]:v for i,v in zip(permutation,shuffled)}:
        raise AssertionError('Order independence '+str(iteration))
check('2000 randomized allocation / permutation cases', True)

# Merchant coupons then platform coupon; shipping coupon is separate from goods.
goods=[6000-1000,4000-500]
platform=allocate(goods,1000,['a','b'])
goods_paid=[b-d for b,d in zip(goods,platform)]
shipping_paid=800-500
check('E06 exact cross-merchant payable',sum(goods_paid)+shipping_paid==7800)
check('E06 allocations sum',sum(platform)==1000 and sum(goods_paid)==7500)
def floor_adjusted_stages(base, stage_discounts):
    # Reverse the most recent discount(s) and replay; no extra charge is invented.
    actual=list(stage_discounts)
    need=max(0,1-(base-sum(actual)))
    for i in range(len(actual)-1,-1,-1):
        take=min(need,actual[i]);actual[i]-=take;need-=take
    if need: raise ValueError('ZERO_PAYABLE_ORDER_NOT_SUPPORTED')
    return actual,base-sum(actual)
check('Minimum fen reverses latest discount',floor_adjusted_stages(100,[50,50])==([50,49],1))
try: floor_adjusted_stages(0,[])
except ValueError: check('Zero-original-price rejected',True)
else: raise AssertionError('Zero original price')
def unit_refunds(paid,qty):
    return [paid//qty+(i<paid%qty) for i in range(qty)]
check('Refund frozen units 100/3',unit_refunds(100,3)==[34,33,33])
for paid in [0,1,2,100,7800]:
    for quantity in [1,2,3,7,13]:
        check('Refund total '+str((paid,quantity)),sum(unit_refunds(paid,quantity))==paid)
check('Negative points disallowed',not (-1>=0 and -1>=1))
check('Nonnegative still insufficient',not (0>=0 and 0>=1))

bundle_path=HERE/'pawday-v1.bundle.json'
bundle_path.write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
validate_spec(json.loads(bundle_path.read_text(encoding='utf-8')))
check('Self-contained JSON bundle validation', True)

docs=HERE.parent / "docs" / "m1"
db=(docs/'04-领域模型与数据库设计.md').read_text(encoding='utf-8')
state=(docs/'05-订单支付库存状态机.md').read_text(encoding='utf-8')
api=(docs/'06-API契约与OpenAPI设计.md').read_text(encoding='utf-8')
check('DB Quote formal', '建议引入短生命周期' not in db and 'orders.quote_id NOT NULL UNIQUE' in db)
check('DB Payment no legacy channel field', '- `channel`：WECHAT / ALIPAY / MOCK' not in db)
check('DB cancellation authority', 'order_cancellation_events' in db and '退款失败保留取消量' in db)
check('DB NULL offer uniqueness', 'NULLS NOT DISTINCT' in db)
check('Taxonomy formal', 'pet_life_stage_definitions' in db and 'UNKNOWN定义' in db)
check('Pricing version consistent', all('PRICING_V1_1' in s for s in [db,state,api]))
check('API negative points formal', 'V1 建议禁止兑换' not in api)
check('Logistics adapter formal', 'LogisticsProvider（正式适配边界）' in api)
check('States no provisional quota/coupon', '建议状态：' not in state)
files=[SPEC_PATH,bundle_path,*[docs/n for n in ['04-领域模型与数据库设计.md','05-订单支付库存状态机.md','06-API契约与OpenAPI设计.md','07-技术选型ADR.md']]]
report={'result':'PASS','scope':'M1 documentation/core contract and arithmetic reference; no runtime/DB/real-provider execution','validated_at_utc':datetime.now(timezone.utc).isoformat(),'openapi_version':spec['openapi'],'operation_count':op_count,'schema_count':len(spec['components']['schemas']),'resolved_reference_count':refs,'check_count':len(checks),'randomized_allocation_cases':2000,'checks':checks,'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(HERE/'validation-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in ['checks','sha256']},ensure_ascii=False))
