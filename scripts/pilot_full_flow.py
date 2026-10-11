"""M6.6.3 full chain against actual pilot HTTP, PostgreSQL and broker/search outages.

Uses only the gate-owned synthetic environment. No production or provider credentials.
Authentication responses and local codes are never included in sampled evidence.
"""
import base64, hashlib, hmac, struct, time, uuid

def run_full_flow(request, record, fixture, env, root, compose, consumer):
    def key(): return str(uuid.uuid4())
    def api(path, body=None, token=None, method=None, headers=None, expected=200):
        status, data, _ = request('/api/v1'+path, body, token, method=method, extra=headers)
        if status != expected:
            raise RuntimeError('HTTP_'+str(status)+'_'+path+'_'+data.get('error',{}).get('code',''))
        return data.get('data')
    def post(path, body, token, headers=None):
        return api(path, body, token, headers={'Idempotency-Key':key(), **(headers or {})})
    def wait_for(check, seconds=45):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            value=check()
            if value:return value
            time.sleep(.5)
        return None
    last_step=-1
    def totp():
        nonlocal last_step
        while int(time.time()//30)<=last_step:time.sleep(.3)
        last_step=int(time.time()//30)
        digest=hmac.new(base64.b64decode(env['PAWDAY_DEMO_ADMIN_TOTP_BASE64']),struct.pack('>Q',last_step),hashlib.sha1).digest()
        offset=digest[-1]&15
        return str((struct.unpack('>I',digest[offset:offset+4])[0]&0x7fffffff)%1000000).zfill(6)
    merchants={}
    for name in ['a','b']:
        merchants[name]=api('/merchant/auth/login',dict(login_name='local-staff-'+name,password=env['PAWDAY_DEMO_MERCHANT_PASSWORD'],device_id='FULL_GATE'))['access_token']
    admin=api('/admin/auth/login',dict(login_name='local-admin',password=env['PAWDAY_DEMO_ADMIN_PASSWORD'],totp_code=totp(),device_id='FULL_GATE'))['access_token']
    record('full_three_real_identity_realms',api('/admin/me',token=admin)['realm']=='ADMIN' and api('/merchant/me',token=merchants['a'])['realm']=='MERCHANT')
    record('full_staff_cannot_impersonate_consumer',request('/api/v1/consumer/me',token=merchants['a'])[0]==403)
    def proof(action):return api('/admin/auth/reverify',dict(action=action,password=env['PAWDAY_DEMO_ADMIN_PASSWORD'],totp_code=totp()),admin)['reverify_token']
    record('full_settlement_policy_requires_reverify',request('/api/v1/admin/settlement-policies',dict(buffer_days=0),admin)[0]==403)
    post('/admin/settlement-policies',dict(buffer_days=0),admin,{'X-Reverify-Token':proof('settlement.policy.manage')})
    record('full_settlement_policy_zero_buffer_published',api('/admin/settlement-policies',token=admin)[-1]['buffer_days']==0)
    # A stopped broker must not roll back OTP creation. Only the local gateway receives it later.
    record('full_broker_actual_stop',compose('stop','rabbitmq').returncode==0)
    phone='+999000000002'
    otp=api('/consumer/auth/phone/request-code',dict(phone_e164=phone,purpose='LOGIN'))
    receipt=root/'sms'/(otp['id']+'.txt')
    time.sleep(1)
    record('full_broker_down_otp_commits_without_external_sms',not receipt.exists())
    record('full_broker_actual_recovery',compose('up','-d','--wait','--wait-timeout','120','rabbitmq').returncode==0)
    record('full_committed_otp_compensates_after_broker_recovery',bool(wait_for(receipt.is_file,90)))
    other=api('/consumer/auth/phone/verify',dict(phone_e164=phone,code=receipt.read_text().splitlines()[1],device_id='FULL_OTHER'))['access_token']
    # Derive actual pilot offer IDs from PostgreSQL-backed API, not a separate test catalogue.
    offers=api('/public/skus/'+fixture('sku-1')+'/offers',token=consumer)
    offer=offers[0]['offer_id']
    merchant_id=offers[0]['merchant_id']
    merchant=next(t for t in merchants.values() if api('/merchant/me',token=t)['merchant_id']==merchant_id)
    foreign=next(t for t in merchants.values() if t!=merchant)
    initial=api('/merchant/offers/'+offer,token=merchant)
    addresses=api('/consumer/addresses',token=consumer);address=addresses[0]['id']
    # Search loss must not prevent the PostgreSQL order transaction.
    record('full_search_actual_stop',compose('stop','opensearch').returncode==0)
    cart=post('/consumer/cart/items',dict(offer_id=offer,quantity=3),consumer)
    quote_key=key();quote_body=dict(cart_item_ids=[cart['id']],address_id=address,coupon_ids=[],use_membership=False)
    quote=api('/consumer/checkout/quotes',quote_body,consumer,headers={'Idempotency-Key':quote_key})
    record('full_quote_idempotent',api('/consumer/checkout/quotes',quote_body,consumer,headers={'Idempotency-Key':quote_key})['quote_id']==quote['quote_id'])
    order_key=key();body=dict(quote_id=quote['quote_id']);order=api('/consumer/orders',body,consumer,headers={'Idempotency-Key':order_key})
    record('full_search_down_business_order_commits',order['status']=='PENDING_PAYMENT')
    record('full_order_idempotent',api('/consumer/orders',body,consumer,headers={'Idempotency-Key':order_key})['id']==order['id'])
    record('full_order_cross_consumer_denied',request('/api/v1/consumer/orders/'+order['id'],token=other)[0] in [403,404])
    record('full_search_actual_recovery',compose('up','-d','--wait','--wait-timeout','120','opensearch').returncode==0)
    payment=order['payment']['id'];attempt_key=key();attempt_body=dict(channel='WECHAT',client_platform='ANDROID')
    pay=api('/consumer/payments/'+payment+'/attempts',attempt_body,consumer,headers={'Idempotency-Key':attempt_key})
    attempt=pay['attempts'][0]['id']
    record('full_payment_attempt_idempotent',api('/consumer/payments/'+payment+'/attempts',attempt_body,consumer,headers={'Idempotency-Key':attempt_key})['attempts'][0]['id']==attempt)
    paid=api('/consumer/payments/'+payment+'/simulation',dict(attempt_id=attempt,outcome='SUCCEEDED'),consumer)
    record('full_simulated_payment_succeeds',paid['status']=='SUCCEEDED')
    record('full_duplicate_payment_does_not_repeat_action',api('/consumer/payments/'+payment+'/simulation',dict(attempt_id=attempt,outcome='SUCCEEDED'),consumer)['successful_attempt_id']==paid['successful_attempt_id'])
    sub=order['suborders'][0];sid=sub['id'];item=sub['items'][0]['id']
    record('full_suborder_cross_merchant_denied',request('/api/v1/merchant/suborders/'+sid+'/fulfillment',token=foreign)[0] in [403,404])
    def fulfillment():return api('/consumer/suborders/'+sid+'/fulfillment',token=consumer)
    def match(v):return {'If-Match':'"'+str(v)+'"'}
    cancel_key=key();cancel_body=dict(reason_code='CONSUMER_CANCELLED',items=[dict(order_item_id=item,quantity=1)])
    cancel=api('/consumer/suborders/'+sid+'/cancellations',cancel_body,consumer,headers={'Idempotency-Key':cancel_key})
    record('full_paid_cancellation_idempotent',api('/consumer/suborders/'+sid+'/cancellations',cancel_body,consumer,headers={'Idempotency-Key':cancel_key})['id']==cancel['id'])
    record('full_cancel_refund_eventually_completes',bool(wait_for(lambda: api('/consumer/cancellations/'+cancel['id'],token=consumer)['status']=='COMPLETED')))
    record('full_cancel_quantity_authoritative',fulfillment()['items'][0]['cancelled_qty']==1)
    ship_body=dict(carrier_code='SF',tracking_no='PILOT'+uuid.uuid4().hex,items=[dict(order_item_id=item,quantity=2)])
    shipping=post('/merchant/suborders/'+sid+'/shipments',ship_body,merchant,match(fulfillment()['version']))
    shipment=shipping['shipments'][-1]['id']
    record('full_simulated_shipment_commits',len(shipping['shipments'])==1)
    record('full_stale_fulfillment_version_rejected',request('/api/v1/consumer/suborders/'+sid+'/confirm-receipt',dict(shipment_ids=[shipment]),consumer,extra={'Idempotency-Key':key(),'If-Match':'"0"'})[0]==409)
    received=post('/consumer/suborders/'+sid+'/confirm-receipt',dict(shipment_ids=[shipment]),consumer,match(fulfillment()['version']))
    record('full_explicit_receipt_commits',received['shipments'][0]['confirmed_at'] is not None and received['items'][0]['received_qty']==2)
    after=post('/consumer/suborders/'+sid+'/aftersales',dict(type='REFUND_ONLY',reason_code='QUALITY_ISSUE',reason_text='SYNTHETIC FULL GATE',items=[dict(order_item_id=item,quantity=1)],evidence=[]),consumer)
    aid=after['id']
    record('full_aftersale_cross_merchant_denied',request('/api/v1/merchant/aftersales/'+aid,token=foreign)[0] in [403,404])
    post('/merchant/aftersales/'+aid+'/decide',dict(action='APPROVE_REFUND',reason='SYNTHETIC FULL GATE'),merchant,match(after['version']))
    record('full_aftersale_refund_eventually_completes',bool(wait_for(lambda: api('/consumer/aftersales/'+aid,token=consumer)['status']=='COMPLETED')))
    record('full_no_overlapping_cancel_or_refund_units',request('/api/v1/consumer/suborders/'+sid+'/cancellations',dict(reason_code='CONSUMER_CANCELLED',items=[dict(order_item_id=item,quantity=3)]),consumer,extra={'Idempotency-Key':key()})[0] in [409,422])
    final=api('/merchant/offers/'+offer,token=merchant)
    record('full_inventory_conservation',final['inventory']['on_hand_qty']==initial['inventory']['on_hand_qty']-2 and final['inventory']['reserved_qty']==0)
    record('full_search_projection_recovers',bool(wait_for(lambda: len(api('/public/products?limit=100',token=consumer))==20)))
    record('full_financial_ledger_reconciles',api('/admin/finance/reconciliation',token=admin)['consistent'] is True)
    record('full_settlement_becomes_eligible',bool(wait_for(lambda: api('/merchant/finance-summary',token=merchant)['eligible_fen']>0,60)))
    record('full_settlement_execute_requires_reverify',request('/api/v1/admin/merchants/'+merchant_id+'/settlements',{},admin,extra={'Idempotency-Key':key()})[0]==403)
    grant=proof('settlement.execute');settlement_key=key();headers={'X-Reverify-Token':grant,'Idempotency-Key':settlement_key}
    settled=api('/admin/merchants/'+merchant_id+'/settlements',{},admin,headers=headers)
    record('full_simulated_settlement_completes',settled['status']=='SETTLED')
    record('full_settlement_idempotent',api('/admin/merchants/'+merchant_id+'/settlements',{},admin,headers=headers)['id']==settled['id'])
    record('full_financial_ledger_reconciles_after_disbursement',api('/admin/finance/reconciliation',token=admin)['consistent'] is True)
    record('full_foreign_merchant_settlement_denied',request('/api/v1/merchant/settlements/'+settled['id'],token=foreign)[0] in [403,404])
    record('full_admin_audit_is_readable',len(api('/admin/audit',token=admin))>0)
    record('full_consumer_audit_is_denied',request('/api/v1/admin/audit',token=consumer)[0]==403)
