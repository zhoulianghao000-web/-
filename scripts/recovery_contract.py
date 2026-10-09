"""Offline recovery preconditions. No production promotion or deletion authority.

The privacy registry must be retained independently of the backup and authenticated
with a separate key. A complete, current registry is an operational prerequisite;
an empty/stale backup-local document is not proof that no deletions occurred.
"""
import datetime as dt, hashlib, hmac, json, re
from pathlib import Path
from operations_bundle import digest

class RecoveryError(ValueError): pass

def timestamp(value):
    try:
        t=dt.datetime.fromisoformat(value)
        if t.utcoffset() is None: raise ValueError()
        return t
    except (TypeError,ValueError): raise RecoveryError('INVALID_RECOVERY_TIME') from None

def privacy_registry(data,signature,key,*,backup_id,system_id,required_until,now):
    if not isinstance(key,bytes) or len(key)<32 or not isinstance(data,bytes) or len(data)>1024*1024: raise RecoveryError('INVALID_REGISTRY')
    if not isinstance(signature,str) or not hmac.compare_digest(hmac.new(key,data,hashlib.sha256).hexdigest(),signature): raise RecoveryError('REGISTRY_AUTHENTICATION_FAILED')
    try: m=json.loads(data)
    except (ValueError,UnicodeError): raise RecoveryError('INVALID_REGISTRY') from None
    if not isinstance(m,dict) or set(m)!={'schema_version','backup_id','system_id','covered_until','last_sequence','events'} or m['schema_version']!='pawday-recovery-privacy/v1' or m['backup_id']!=backup_id or m['system_id']!=system_id: raise RecoveryError('REGISTRY_BINDING_MISMATCH')
    covered=timestamp(m['covered_until'])
    if not timestamp(required_until)<=covered<=timestamp(now): raise RecoveryError('STALE_OR_FUTURE_REGISTRY')
    if not isinstance(m['events'],list) or len(m['events'])>10000 or type(m['last_sequence']) is not int or m['last_sequence']!=len(m['events']): raise RecoveryError('REGISTRY_SEQUENCE_GAP')
    for seq,e in enumerate(m['events'],1):
        if not isinstance(e,dict) or set(e)!={'sequence','kind','subject_id','effective_at'} or type(e['sequence']) is not int or e['sequence']!=seq: raise RecoveryError('REGISTRY_SEQUENCE_GAP')
        if e['kind'] not in {'AI_CONVERSATION_DELETE','AI_PERSONALIZATION_REVOKE','MEDIA_DELETE'} or not isinstance(e['subject_id'],str) or not re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}',e['subject_id']): raise RecoveryError('UNSUPPORTED_PRIVACY_ACTION')
        if timestamp(e['effective_at'])>covered: raise RecoveryError('REGISTRY_SEQUENCE_GAP')
    return m

def bundle_files(root):
    root=Path(root).absolute()
    if root.resolve()!=root or root.is_symlink(): raise RecoveryError('UNSAFE_RECOVERY_ROOT')
    files={}
    for p in root.rglob('*'):
        if p.is_symlink() or p.resolve()!=p.absolute(): raise RecoveryError('UNSAFE_RECOVERY_FILE')
        if not p.is_file(): continue
        name=p.relative_to(root).as_posix()
        if not re.fullmatch(r'base/[A-Za-z0-9_./-]+|wal/[0-9A-F]{24}(?:\.[0-9A-F]{8}\.backup)?|wal/[0-9A-F]{8}\.history',name) or '..' in name.split('/') or p.stat().st_nlink!=1: raise RecoveryError('UNEXPECTED_RECOVERY_FILE')
        if name.startswith('base/pg_tblspc/'): raise RecoveryError('EXTERNAL_TABLESPACE_UNSUPPORTED')
        files[name]={'size':p.stat().st_size,'sha256':digest(p)}
    if 'base/backup_manifest' not in files or not any(re.fullmatch('wal/[0-9A-F]{24}',f) for f in files): raise RecoveryError('INCOMPLETE_RECOVERY_BUNDLE')
    return files

def validate_bundle(root,manifest,*,commit,system_id):
    if set(manifest)!={'schema_version','source_commit','system_id','backup_id','target_time','files'} or manifest['schema_version']!='pawday-pitr/v1' or manifest['source_commit']!=commit or not re.fullmatch('[0-9a-f]{40}',commit) or manifest['system_id']!=system_id or not re.fullmatch('[0-9a-f]{32}',manifest['backup_id']): raise RecoveryError('RECOVERY_BINDING_MISMATCH')
    timestamp(manifest['target_time'])
    if bundle_files(root)!=manifest['files']: raise RecoveryError('RECOVERY_BUNDLE_HASH_MISMATCH')
    return manifest

def retention_plan(requested,pinned):
    # Deliberately never deletes files. A backup set pins its entire WAL chain,
    # object versions and historical key references until the set is retired.
    if not isinstance(requested,list) or not isinstance(pinned,list) or any(not isinstance(x,str) for x in requested+pinned): raise RecoveryError('INVALID_RETENTION_PLAN')
    if set(requested)&set(pinned): raise RecoveryError('RECOVERY_CHAIN_STILL_REQUIRED')
    return {'action':'REVIEW_ONLY','candidates':sorted(set(requested)),'deletion_authorized':False}

def privacy_replay_sql(registry):
    """Whitelisted offline scrubbing only. Caller must authenticate registry first.
    Never refunds, releases quota or replays an external effect. All existing
    sessions and pending profile proposals are invalidated conservatively.
    """
    statements=['BEGIN','SET LOCAL transaction_read_only=off']
    for e in registry['events']:
        subject=e['subject_id']
        if not re.fullmatch(r'[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}',subject): raise RecoveryError('UNSUPPORTED_PRIVACY_ACTION')
        if e['kind']=='AI_CONVERSATION_DELETE': statements.append(f"UPDATE ai_conversations SET status='DELETED',pet_id=NULL WHERE id='{subject}'")
        elif e['kind']=='AI_PERSONALIZATION_REVOKE':
            statements.extend([f"UPDATE ai_preferences SET personalization_enabled=false,version=version+1 WHERE user_id='{subject}' AND personalization_enabled",f"UPDATE ai_conversations SET pet_id=NULL WHERE user_id='{subject}'"])
        elif e['kind']=='MEDIA_DELETE': statements.append(f"UPDATE media_asset SET status='DELETED',upload_token_hash=NULL,claim_token=NULL,lease_expires_at=NULL,cleanup_claim_token=NULL,cleanup_lease_expires_at=NULL WHERE id='{subject}'")
        else: raise RecoveryError('UNSUPPORTED_PRIVACY_ACTION')
    statements.extend(["UPDATE ai_conversations SET status='EXPIRED',pet_id=NULL WHERE expires_at<=clock_timestamp() AND status='ACTIVE'",
        "UPDATE ai_messages SET user_text_ciphertext=NULL,result_ciphertext=NULL WHERE conversation_id IN (SELECT id FROM ai_conversations WHERE status IN ('DELETED','EXPIRED'))",
        "UPDATE ai_profile_proposals SET status='EXPIRED',pet_id=NULL,before_value=NULL,proposed_value=NULL,version=version+1 WHERE status<>'EXPIRED'",
        "UPDATE auth_session SET revoked_at=coalesce(revoked_at,clock_timestamp())",
        "UPDATE auth_refresh_token SET status='REVOKED' WHERE status='ACTIVE'",'COMMIT'])
    return ';\n'.join(statements)+';'
