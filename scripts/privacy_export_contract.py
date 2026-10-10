"""Independent, signed full-prefix export. A trusted latest checkpoint pin must
come from outside the restored backup. HMAC alone cannot prove completeness.
No release/promotion authorization is returned by this module.
"""
import base64,hashlib,hmac,json,re
from recovery_contract import RecoveryError,privacy_registry,timestamp

def strict_json(data):
    def pairs(items):
        result={}
        for k,v in items:
            if k in result:raise RecoveryError('DUPLICATE_EXPORT_FIELD')
            result[k]=v
        return result
    try:return json.loads(data,object_pairs_hook=pairs)
    except (ValueError,UnicodeError):raise RecoveryError('INVALID_INDEPENDENT_EXPORT') from None

def verify_export(envelope,key,*,system_id,journal_id,required_until,minimum_sequence,expected_checkpoint_sha256,now,backup_id):
    if not isinstance(envelope,bytes) or len(envelope)>1500000 or not isinstance(key,bytes) or len(key)<32:raise RecoveryError('INVALID_INDEPENDENT_EXPORT')
    outer=strict_json(envelope)
    if not isinstance(outer,dict) or set(outer)!={'payload','signature'}:raise RecoveryError('INVALID_INDEPENDENT_EXPORT')
    try:data=base64.b64decode(outer['payload'],validate=True)
    except (ValueError,TypeError):raise RecoveryError('INVALID_INDEPENDENT_EXPORT') from None
    if len(data)>1048576 or not isinstance(outer['signature'],str) or not re.fullmatch('[0-9a-f]{64}',outer['signature']) or not hmac.compare_digest(hmac.new(key,data,hashlib.sha256).hexdigest(),outer['signature']):raise RecoveryError('INVALID_EXPORT_SIGNATURE')
    digest=hashlib.sha256(data).hexdigest()
    if not isinstance(expected_checkpoint_sha256,str) or not re.fullmatch('[0-9a-f]{64}',expected_checkpoint_sha256) or not hmac.compare_digest(digest,expected_checkpoint_sha256):raise RecoveryError('TRUSTED_LATEST_CHECKPOINT_REQUIRED')
    m=strict_json(data)
    if not isinstance(m,dict) or set(m)!={'schema_version','system_id','journal_id','installed_at','covered_until','last_sequence','events'} or m['schema_version']!='pawday-privacy-export/v1' or m['system_id']!=system_id or m['journal_id']!=journal_id:raise RecoveryError('EXPORT_ORIGIN_MISMATCH')
    if not isinstance(journal_id,str) or not re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}',journal_id):raise RecoveryError('EXPORT_ORIGIN_MISMATCH')
    if type(minimum_sequence) is not int or minimum_sequence<0 or type(m['last_sequence']) is not int or m['last_sequence']<minimum_sequence:raise RecoveryError('EXPORT_TAIL_MISSING')
    if timestamp(m['installed_at'])>timestamp(m['covered_until']):raise RecoveryError('EXPORT_ORIGIN_MISMATCH')
    registry={k:m[k] for k in ['system_id','covered_until','last_sequence','events']}
    registry.update(schema_version='pawday-recovery-privacy/v1',backup_id=backup_id)
    bound=json.dumps(registry,sort_keys=True).encode()
    return privacy_registry(bound,hmac.new(key,bound,hashlib.sha256).hexdigest(),key,backup_id=backup_id,system_id=system_id,required_until=required_until,now=now)
