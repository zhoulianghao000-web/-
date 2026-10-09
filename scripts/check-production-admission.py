"""Offline integrity gate; never contacts providers or reads credentials.
Lint validates an honest inventory. Release also requires fresh production evidence.
A hash proves file integrity, not that an operator's attestation is authentic.
"""
import argparse, datetime as dt, hashlib, json, re
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

REQUIRED = {
  "payment_refund": [
    "verified_callback",
    "duplicate_callback",
    "unknown_result_query",
    "partial_refund_conservation"
  ],
  "settlement": [
    "provider_account_binding",
    "idempotent_disbursement",
    "ambiguous_result_recovery",
    "ledger_reconciliation"
  ],
  "sms": [
    "approved_template",
    "stable_send_key",
    "ambiguous_receipt",
    "outbox_recovery"
  ],
  "storage_media": [
    "private_upload_read_delete",
    "mime_hash_limits",
    "expired_grant",
    "retention_delete"
  ],
  "ai_live": [
    "official_inference",
    "evidence_boundary",
    "quota_failure_release",
    "cost_rate_limit"
  ],
  "logistics_navigation": [
    "tracking_authenticity",
    "installed_uninstalled_amap",
    "location_denied",
    "no_implicit_receipt"
  ],
  "operator_mfa": [
    "real_staff_enrollment",
    "one_use_reverify",
    "scope_denial",
    "mfa_loss_recovery"
  ],
  "privacy_delete": [
    "ownership",
    "legal_retention_decision",
    "object_reference_cleanup",
    "backup_recovery_deletion_reapply"
  ],
  "backup_restore": [
    "postgres_point_in_time",
    "encryption_key_restore",
    "media_restore",
    "search_rebuild",
    "outbox_inbox_no_duplicate"
  ],
  "observability": [
    "backlog_alert",
    "refund_unknown_alert",
    "settlement_mismatch_alert",
    "alert_delivery_and_recovery"
  ],
  "devices_security": [
    "signed_android",
    "signed_ios",
    "no_embedded_secrets",
    "session_logout",
    "device_permission_branches"
  ],
  "launch_data": [
    "authorized_product_sources",
    "verified_store_sources",
    "city_coverage",
    "operating_policy_version"
  ],
  "capacity_recovery": [
    "agreed_load_budget",
    "inventory_concurrency",
    "broker_search_outage_recovery",
    "restore_rpo_rto"
  ],
  "infrastructure_security": [
    "tls_identity_verification",
    "least_privilege_accounts",
    "secret_rotation",
    "restricted_management_network"
  ]
}
UTC = dt.timezone.utc
IMPLEMENTATION_BLOCKERS = ['RUNTIME:LIVE_PAYMENT_REFUND_SMS_STORAGE_DISBURSEMENT_NOT_IMPLEMENTED']
REPORT_KEYS = {'schema_version','gate_id','source_commit','environment','result','started_at','finished_at','tests','scenarios'}
def timestamp(value):
    result = dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    if result.tzinfo is None: raise ValueError('Timezone required')
    return result

def evaluate(manifest, schema, repo, evidence_root, release=False, commit=None, now=None):
    now = now or dt.datetime.now(UTC)
    reasons = []
    if list(Draft202012Validator(schema,format_checker=FormatChecker()).iter_errors(manifest)):
        return {'result':'FAIL','production_ready':False,'reasons':['MANIFEST_SCHEMA_INVALID']}
    rows = manifest['gates']
    if len({g['id'] for g in rows}) != len(REQUIRED) or {g['id'] for g in rows} != set(REQUIRED):
        reasons.append('REQUIRED_GATE_SET_MISMATCH')
    for gate in rows:
        gid = gate['id']
        if gate['required_scenarios'] != REQUIRED.get(gid): reasons.append(gid+':SCENARIO_SET_MISMATCH')
        for source in gate['source_files']:
            candidate = (repo/source).resolve()
            if not candidate.is_relative_to(repo.resolve()) or not candidate.is_file(): reasons.append(gid+':SOURCE_MISSING')
        if gate['status']=='VERIFIED' and (gate['blockers'] or not gate['evidence']): reasons.append(gid+':FALSE_VERIFIED')
    if reasons: return {'result':'FAIL','production_ready':False,'reasons':reasons}
    if not release:
        return {'result':'PASS','production_ready':False,'gate_count':len(rows),'pending':sum(g['status']=='PENDING' for g in rows),
                'reasons':['INVENTORY_LINT_ONLY_NOT_RELEASE_APPROVAL']}
    if not commit or not re.fullmatch('[0-9a-f]{40}',commit):
        return {'result':'FAIL','production_ready':False,'reasons':['RELEASE_COMMIT_REQUIRED']}
    reasons.extend(IMPLEMENTATION_BLOCKERS)
    for gate in rows:
        gid = gate['id']
        if gate['status']!='VERIFIED' or gate['blockers'] or not gate['evidence']:
            reasons.append(gid+':PRODUCTION_EVIDENCE_PENDING')
            continue
        covered=set()
        for ref in gate['evidence']:
            try:
                path=(evidence_root/ref['path']).resolve()
                if not path.is_relative_to(evidence_root.resolve()) or not path.is_file() or path.stat().st_size>1048576: raise ValueError()
                raw=path.read_bytes()
                if hashlib.sha256(raw).hexdigest()!=ref['sha256']: raise ValueError()
                report=json.loads(raw)
                if set(report)!=REPORT_KEYS or report['schema_version']!='pawday-production-evidence/v1': raise ValueError()
                if report['gate_id']!=gid or report['source_commit']!=commit or report['environment']!='production' or report['result']!='PASS': raise ValueError()
                start,end=timestamp(report['started_at']),timestamp(report['finished_at'])
                if start>end or end>now or now-end>dt.timedelta(days=30): raise ValueError()
                tests=report['tests']
                if set(tests)!={'passed','failed','errors','skipped'} or any(type(v) is not int for v in tests.values()): raise ValueError()
                if tests['passed']<1 or any(tests[k]!=0 for k in ['failed','errors','skipped']): raise ValueError()
                scenarios=report['scenarios']
                if type(scenarios) is not dict or any(v!='PASS' for v in scenarios.values()): raise ValueError()
                covered.update(scenarios)
            except (ValueError,TypeError,KeyError,AttributeError,OSError):
                reasons.append(gid+':EVIDENCE_INVALID_OR_STALE')
        if not set(REQUIRED[gid])<=covered: reasons.append(gid+':SCENARIO_EVIDENCE_MISSING')
    return {'result':'BLOCKED' if reasons else 'PASS','production_ready':not reasons,'gate_count':len(rows),'reasons':reasons,
            'operator_approval_still_required':True}

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--manifest',default='deployment/production-admission.json')
    p.add_argument('--schema',default='deployment/production-admission.schema.json')
    p.add_argument('--repo',default='.')
    p.add_argument('--evidence-root',default='deployment/production-evidence')
    p.add_argument('--release',action='store_true')
    p.add_argument('--commit')
    p.add_argument('--report')
    args=p.parse_args()
    try:
        result=evaluate(json.loads(Path(args.manifest).read_text(encoding='utf8')),json.loads(Path(args.schema).read_text(encoding='utf8')),
                        Path(args.repo),Path(args.evidence_root),args.release,args.commit)
    except (ValueError,OSError):
        result={'result':'FAIL','production_ready':False,'reasons':['INPUT_UNREADABLE_OR_INVALID']}
    output=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.report:
        dest=Path(args.report);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(output,encoding='utf8')
    print(output,end='')
    raise SystemExit(0 if result['result']=='PASS' else 2 if result['result']=='BLOCKED' else 1)
if __name__=='__main__':main()
