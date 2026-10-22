"""Pure synthetic design models. Not a stock command, provider adapter or HTTP endpoint."""
import hashlib,json
class DesignError(ValueError):pass

def require(ok,code):
 if not ok:raise DesignError(code)

def integer(value,low=0,high=1_000_000_000):return type(value) is int and low<=value<=high

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def event_identity(previous,current):
 require(isinstance(current,str) and len(current)==64 and all(c in '0123456789abcdef' for c in current),'EVENT_HASH_INVALID')
 if previous is None:return 'NEW'
 require(previous==current,'EVENT_IDENTITY_CONFLICT')
 return 'DUPLICATE_NO_SIDE_EFFECT'

def stock_projection(s):
 # All fields represent persisted server/fixture facts; none is a public write body.
 require(s['scope_matches'],'SCOPE_MISMATCH')
 require(s['connection_active'] and s['mapping_active'],'INTEGRATION_INACTIVE')
 require(s['basis']=='DEDICATED_REMAINING_AFTER_WATERMARK' and s['unit']=='PIECE','STOCK_BASIS_UNSUPPORTED')
 require(s['mapping_version']==s['event_mapping_version'],'MAPPING_STALE')
 require(s['inventory_version']==s['expected_inventory_version'],'INVENTORY_STALE')
 require(s['preview_owned'] and not s['preview_used'] and s['accepted_snapshot_sha256']==s['current_snapshot_sha256'],'PREVIEW_SNAPSHOT_CHANGED')
 require(integer(s['external_version'],1) and integer(s['applied_external_version']) and s['external_version']>s['applied_external_version'],'EXTERNAL_VERSION_STALE')
 require(all(integer(s[k]) for k in ['external_remaining_qty','on_hand_qty','reserved_qty']),'QUANTITY_INVALID')
 require(s['reserved_qty']<=s['on_hand_qty'],'CURRENT_STOCK_INVALID')
 moves=s['movements'];require(type(moves) is list and len(moves)<=10000,'MOVEMENT_CHAIN_INVALID')
 require(s['expected_local_sequence']==len(moves),'MOVEMENT_CHAIN_CHANGED')
 ids=set()
 for n,m in enumerate(moves,1):
  require(m['sequence']==n and m['kind'] in ['SALE','ADJUSTMENT','RESTOCK'] and integer(m['delta_qty'],-1_000_000_000) and m['delta_qty']!=0 and m['source_id'] not in ids,'MOVEMENT_CHAIN_INVALID');ids.add(m['source_id'])
  require(m['kind']!='SALE' or m['delta_qty']<0,'MOVEMENT_SIGN_INVALID')
  require(m['kind']!='RESTOCK' or m['delta_qty']>0,'MOVEMENT_SIGN_INVALID')
 ack=s['acknowledged_local_sequence'];require(integer(ack,0,len(moves)) and integer(s['previous_acknowledged_sequence'],0,len(moves)) and ack>=s['previous_acknowledged_sequence'],'WATERMARK_INVALID')
 require((ack==0 or s['acknowledgement_proven']) and s['acknowledged_prefix_sha256']==digest(moves[:ack]),'WATERMARK_UNPROVEN')
 require(integer(s['preview_created_epoch'],0,10**12) and s['preview_expires_epoch']==s['preview_created_epoch']+300 and s['preview_created_epoch']<=s['as_of_epoch']<s['preview_expires_epoch'],'PREVIEW_EXPIRED')
 target=s['external_remaining_qty']+sum(m['delta_qty'] for m in moves[ack:])
 require(0<=target<=1_000_000_000,'PROJECTED_STOCK_OUT_OF_RANGE')
 require(target>=s['reserved_qty'],'RESERVED_STOCK_CONFLICT')
 return {'target_on_hand_qty':target,'delta_qty':target-s['on_hand_qty'],'available_qty':target-s['reserved_qty']}

def delivery_result(s):
 require(s['scope_matches'] and s['actor_authorized'],'DELIVERY_SCOPE_REVOKED')
 require(s['kind']=='GOODS','GOODS_ONLY')
 require(s['paid'] and not s['cancelled'] and s['external_hold_installed'],'LOCAL_ORDER_NOT_EXPORTABLE')
 require(s['prior_state']=='PROCESSING' and integer(s['attempt_count'],1,8),'DELIVERY_STATE_INVALID')
 require(s['lease_expires_epoch']==s['lease_created_epoch']+60,'LEASE_DURATION_INVALID')
 require(s['lease_token']==s['submitted_token'] and s['lease_created_epoch']<=s['as_of_epoch']<s['lease_expires_epoch'],'LEASE_LOST')
 require(s['business_key']==s['reply_business_key'] and s['payload_sha256']==s['reply_payload_sha256'],'EXTERNAL_RECEIPT_MISMATCH')
 require(s['outcome'] in ['ACCEPTED','REJECTED','UNKNOWN','NOT_FOUND'],'EXTERNAL_RESULT_INVALID')
 if s['outcome'] in ['ACCEPTED','REJECTED']:
  require(s['receipt_proven'],'EXTERNAL_RECEIPT_UNPROVEN')
  return {'state':s['outcome'],'responsibility_open':False,'business_key':s['business_key']}
 state='NEEDS_REVIEW' if s['attempt_count']==8 else 'UNKNOWN' if s['outcome']=='UNKNOWN' else 'READY'
 return {'state':state,'responsibility_open':True,'business_key':s['business_key']}

def paid_cancellation(s):
 require(s['kind']=='GOODS' and s['paid'] and not s['already_shipped'],'CANCELLATION_NOT_ELIGIBLE')
 if not s['ever_attempted'] and not s['external_hold_installed']:return 'LOCAL_RULES_MAY_CONTINUE'
 require(s['external_state']=='REJECTED' and s['rejection_proven_no_external_order'],'EXTERNAL_FULFILLMENT_REVIEW_REQUIRED')
 return 'LOCAL_RULES_MAY_CONTINUE'

def shipment_application(s):
 require(s['scope_matches'] and s['actor_authorized'],'SHIPMENT_SCOPE_REVOKED')
 require(s['connection_active'] and s['mapping_version']==s['event_mapping_version'],'SHIPMENT_MAPPING_STALE')
 require(s['kind']=='GOODS' and s['paid'] and not s['cancelled'] and s['delivery_accepted'],'SUBORDER_NOT_SHIPPABLE')
 require(s['suborder_version']==s['expected_suborder_version'],'SUBORDER_STALE')
 require(not s['tracking_already_used'],'TRACKING_NUMBER_IN_USE')
 require(type(s['items']) is list and 1<=len(s['items'])<=100,'SHIPMENT_ITEMS_INVALID')
 seen=set()
 for item in s['items']:
  key=item['order_item_id'];require(key in s['remaining'] and key not in seen and integer(item['quantity'],1,100000),'SHIPMENT_ITEMS_INVALID');seen.add(key)
  require(item['quantity']<=s['remaining'][key],'SHIPMENT_QUANTITY_EXCEEDED')
 require(s['native_fulfillment_checks_passed'],'NATIVE_FULFILLMENT_REQUIRED')
 return {'shipment_created':True,'consumer_receipt_confirmed':False,'money_changed':False}
