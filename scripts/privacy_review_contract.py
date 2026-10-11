"""Read-only privacy coverage and recovery rejoin review. Never authorizes deletion.

Schema inputs contain metadata only. Rejoin inputs are private snapshot facts and
an independently authenticated registry; callers MUST verify_export first. Reports
contain fixed reason codes and aggregate counts, never event subjects or payloads.
"""
import collections, datetime as dt, hashlib, json, re
from pathlib import Path
from recovery_contract import RecoveryError, timestamp

SCHEMA_SQL = """SELECT coalesce(json_agg(row_to_json(s) ORDER BY s.table_name,s.ordinal_position),'[]') FROM (SELECT table_name,column_name,ordinal_position,udt_name,is_nullable,character_maximum_length FROM information_schema.columns WHERE table_schema='public' AND table_name NOT IN ('flyway_schema_history','m63_fixture')) s"""
# All statements are fixed, with no account ID or SQL from a request interpolated.
REJOIN_SQL = """SELECT json_build_object(
 'system_id',(SELECT system_identifier::text FROM pg_control_system()),
 'journal_id',(SELECT journal_id FROM privacy_journal_head),
 'last_sequence',(SELECT last_sequence FROM privacy_journal_head),
 'events',(SELECT coalesce(json_agg(json_build_object('sequence',sequence,'kind',kind,'subject_id',subject_id,'effective_at',effective_at) ORDER BY sequence),'[]') FROM privacy_journal),
 'pending_outbox',(SELECT count(*) FROM outbox_event WHERE status<>'PUBLISHED'),
 'processed_inbox',(SELECT count(*) FROM processed_event),
 'payment_attempts',(SELECT count(*) FROM payment_attempts),
 'refunds',(SELECT count(*) FROM refunds),
 'settlements',(SELECT count(*) FROM settlements),
 'active_sessions',(SELECT count(*) FROM auth_session WHERE revoked_at IS NULL),
 'active_refresh_tokens',(SELECT count(*) FROM auth_refresh_token WHERE status='ACTIVE'))"""

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()

def schema_digest(rows):
    if not isinstance(rows,list) or not rows: raise RecoveryError('INVALID_SCHEMA_METADATA')
    fields={'table_name','column_name','ordinal_position','udt_name','is_nullable','character_maximum_length'}
    keys=set()
    for r in rows:
        if not isinstance(r,dict) or set(r)!=fields: raise RecoveryError('INVALID_SCHEMA_METADATA')
        if any(not isinstance(r[k],str) or not re.fullmatch('[a-z0-9_]+',r[k]) for k in ['table_name','column_name','udt_name']): raise RecoveryError('INVALID_SCHEMA_METADATA')
        if type(r['ordinal_position']) is not int or r['ordinal_position']<1 or r['is_nullable'] not in {'YES','NO'}: raise RecoveryError('INVALID_SCHEMA_METADATA')
        size=r['character_maximum_length']
        if size is not None and (type(size) is not int or size<1): raise RecoveryError('INVALID_SCHEMA_METADATA')
        key=(r['table_name'],r['column_name'])
        if key in keys: raise RecoveryError('DUPLICATE_SCHEMA_COLUMN')
        keys.add(key)
    return hashlib.sha256(canonical(sorted(rows,key=lambda r:(r['table_name'],r['ordinal_position'])))).hexdigest()

def review_inventory(manifest,rows,migration_dir):
    fields={'schema_version','source_baseline','schema_sha256','retention_authority','deletion_authorized','migrations','tables','policies','external_surfaces'}
    if not isinstance(manifest,dict) or set(manifest)!=fields or manifest['schema_version']!='pawday-privacy-inventory/v1' or manifest['retention_authority']!='PENDING_OWNER_POLICY' or manifest['deletion_authorized'] is not False: raise RecoveryError('INVALID_PRIVACY_INVENTORY')
    if not re.fullmatch('[a-f0-9]{40}',manifest['source_baseline']): raise RecoveryError('INVALID_PRIVACY_INVENTORY')
    migrations={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(migration_dir).glob('V*.sql')}
    if manifest['migrations']!=migrations: raise RecoveryError('UNREVIEWED_MIGRATION')
    digest=schema_digest(rows)
    if digest!=manifest['schema_sha256']: raise RecoveryError('UNREVIEWED_SCHEMA_CHANGE')
    actual=collections.defaultdict(list)
    for row in sorted(rows,key=lambda r:(r['table_name'],r['ordinal_position'])): actual[row['table_name']].append(row['column_name'])
    covered={};domains=collections.Counter()
    for t in manifest['tables']:
        if not isinstance(t,dict) or set(t)!={'name','domain','retention_status','disposition','columns'} or t['name'] in covered: raise RecoveryError('INVALID_TABLE_REVIEW')
        if t['retention_status']!='PENDING_OWNER_POLICY' or t['disposition'] not in {'REVIEW_REQUIRED','PRESERVE_FACTS_REVIEW_PII','DERIVED_REBUILD_REVIEW'}: raise RecoveryError('UNAPPROVED_RETENTION_POLICY')
        if not isinstance(t['domain'],str) or not re.fullmatch('[a-z_]+',t['domain']): raise RecoveryError('INVALID_TABLE_REVIEW')
        covered[t['name']]=t['columns'];domains[t['domain']]+=1
    if dict(actual)!=covered: raise RecoveryError('INCOMPLETE_PRIVACY_COVERAGE')
    policies=manifest['policies']
    if not isinstance(policies,list) or len(policies)!=len(domains) or {p.get('domain') for p in policies}!=set(domains): raise RecoveryError('INCOMPLETE_POLICY_REVIEW')
    for p in policies:
        if set(p)!={'domain','status','retention_basis','retention_days'} or p['status']!='PENDING' or p['retention_basis'] is not None or p['retention_days'] is not None: raise RecoveryError('UNAPPROVED_RETENTION_POLICY')
    surfaces=manifest['external_surfaces']
    expected={'object_versions','search_indices','rabbitmq_messages','redis_identity_cache','application_audit_logs','backup_wal_historical_keys','external_providers'}
    if not isinstance(surfaces,list) or len(surfaces)!=len(expected) or {s.get('name') for s in surfaces}!=expected or any(set(s)!={'name','status'} or s['status']!='PENDING' for s in surfaces): raise RecoveryError('INCOMPLETE_EXTERNAL_SURFACES')
    return dict(result='PASS',schema_version='pawday-privacy-review/v1',scope='SCHEMA_COVERAGE_ONLY',tables=len(covered),columns=len(rows),schema_sha256=digest,domains=dict(sorted(domains.items())),pending_policy_domains=len(policies),pending_external_surfaces=len(surfaces),account_deletion_ready=False,deletion_authorized=False,production_ready=False)

def review_rejoin(snapshot,verified_registry,*,system_id,journal_id):
    fields={'system_id','journal_id','last_sequence','events','pending_outbox','processed_inbox','payment_attempts','refunds','settlements','active_sessions','active_refresh_tokens'}
    if not isinstance(snapshot,dict) or set(snapshot)!=fields: raise RecoveryError('INVALID_REJOIN_SNAPSHOT')
    if snapshot['system_id']!=system_id or snapshot['journal_id']!=journal_id or verified_registry.get('system_id')!=system_id: raise RecoveryError('REJOIN_SOURCE_MISMATCH')
    for k in fields-{'system_id','journal_id','events'}:
        if type(snapshot[k]) is not int or snapshot[k]<0: raise RecoveryError('INVALID_REJOIN_SNAPSHOT')
    events=snapshot['events'];independent=verified_registry.get('events')
    if not isinstance(events,list) or not isinstance(independent,list) or len(events)>10000 or len(independent)>10000: raise RecoveryError('INVALID_REJOIN_SNAPSHOT')
    if snapshot['last_sequence']!=len(events) or verified_registry.get('last_sequence')!=len(independent): raise RecoveryError('REJOIN_SEQUENCE_GAP')
    def normalize(items):
        normalized=[]
        for seq,e in enumerate(items,1):
            if not isinstance(e,dict) or set(e)!={'sequence','kind','subject_id','effective_at'} or type(e['sequence']) is not int or e['sequence']!=seq: raise RecoveryError('REJOIN_SEQUENCE_GAP')
            if e['kind'] not in {'AI_CONVERSATION_DELETE','AI_PERSONALIZATION_REVOKE','MEDIA_DELETE'} or not isinstance(e['subject_id'],str) or not re.fullmatch('[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}',e['subject_id']): raise RecoveryError('INVALID_REJOIN_EVENT')
            normalized.append((seq,e['kind'],e['subject_id'],timestamp(e['effective_at']).astimezone(dt.timezone.utc)))
        return normalized
    local=normalize(events);remote=normalize(independent)
    reasons=['PRIVACY_RETENTION_POLICY_PENDING','RESTORE_REJOIN_PROTOCOL_PENDING','EXTERNAL_EFFECT_RECONCILIATION_PENDING','PRODUCTION_ADMISSION_PENDING']
    if local!=remote: reasons.append('RESTORED_JOURNAL_FORK_OR_INCOMPLETE')
    if snapshot['pending_outbox']: reasons.append('PENDING_OUTBOX_REQUIRES_RECONCILIATION')
    if snapshot['active_sessions'] or snapshot['active_refresh_tokens']: reasons.append('RESTORED_AUTHORITY_STILL_ACTIVE')
    return dict(result='BLOCKED',scope='OFFLINE_REJOIN_REVIEW_ONLY',reasons=reasons,local_sequence=len(local),independent_sequence=len(remote),journal_matches_independent=local==remote,counts={k:snapshot[k] for k in sorted(fields-{'system_id','journal_id','events','last_sequence'})},quarantine_released=False,workers_authorized=False,exporter_authorized=False,deletion_authorized=False,production_ready=False)
