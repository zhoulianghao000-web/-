import copy,hashlib,json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]))
from privacy_review_contract import *

class PrivacyReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.migrations=Path(self.tmp.name)
        (self.migrations/'V001__test.sql').write_bytes(b'-- TEST_ONLY')
        self.rows=[dict(table_name='app_user',column_name='id',ordinal_position=1,udt_name='uuid',is_nullable='NO',character_maximum_length=None)]
        self.m=dict(schema_version='pawday-privacy-inventory/v1',source_baseline='a'*40,schema_sha256=schema_digest(self.rows),retention_authority='PENDING_OWNER_POLICY',deletion_authorized=False,migrations={'V001__test.sql':hashlib.sha256(b'-- TEST_ONLY').hexdigest()},tables=[dict(name='app_user',domain='identity_audit',retention_status='PENDING_OWNER_POLICY',disposition='REVIEW_REQUIRED',columns=['id'])],policies=[dict(domain='identity_audit',status='PENDING',retention_basis=None,retention_days=None)],external_surfaces=[dict(name=s,status='PENDING') for s in ['object_versions','search_indices','rabbitmq_messages','redis_identity_cache','application_audit_logs','backup_wal_historical_keys','external_providers']])
        self.event=dict(sequence=1,kind='MEDIA_DELETE',subject_id='00000000-0000-4000-8000-000000000001',effective_at='2026-10-11T08:00:00+00:00')
        self.registry=dict(system_id='12345',events=[self.event.copy()],last_sequence=1)
        self.s=dict(system_id='12345',journal_id='00000000-0000-4000-8000-000000000002',last_sequence=1,events=[self.event.copy()],pending_outbox=0,processed_inbox=1,payment_attempts=0,refunds=0,settlements=0,active_sessions=0,active_refresh_tokens=0)
    def inventory(self):return review_inventory(self.m,self.rows,self.migrations)
    def rejoin(self):return review_rejoin(self.s,self.registry,system_id='12345',journal_id='00000000-0000-4000-8000-000000000002')
    def test_complete_coverage_is_not_deletion_approval(self):
        r=self.inventory();self.assertEqual('PASS',r['result']);self.assertFalse(r['deletion_authorized']);self.assertFalse(r['account_deletion_ready']);self.assertEqual(1,r['pending_policy_domains'])
    def test_new_table_is_blocked(self):
        self.rows.append(dict(self.rows[0],table_name='unreviewed'));self.assertRaises(RecoveryError,self.inventory)
    def test_new_json_or_text_field_is_blocked(self):
        self.rows.append(dict(self.rows[0],column_name='private_json',ordinal_position=2,udt_name='jsonb'));self.assertRaises(RecoveryError,self.inventory)
    def test_type_or_nullability_change_is_blocked(self):
        self.rows[0]['is_nullable']='YES';self.assertRaises(RecoveryError,self.inventory)
    def test_metadata_payload_cannot_include_values(self):
        self.rows[0]['value']='TEST_ONLY_PRIVATE';self.assertRaises(RecoveryError,self.inventory)
    def test_duplicate_schema_column_is_blocked(self):
        self.rows.append(self.rows[0].copy());self.assertRaises(RecoveryError,self.inventory)
    def test_new_migration_requires_review(self):
        (self.migrations/'V002__new.sql').write_bytes(b'-- NEW');self.assertRaises(RecoveryError,self.inventory)
    def test_omitted_table_is_blocked_even_with_matching_digest(self):
        self.m['tables']=[];self.assertRaises(RecoveryError,self.inventory)
    def test_omitted_column_is_blocked(self):
        self.m['tables'][0]['columns']=[];self.assertRaises(RecoveryError,self.inventory)
    def test_duplicate_table_is_blocked(self):
        self.m['tables'].append(self.m['tables'][0].copy());self.assertRaises(RecoveryError,self.inventory)
    def test_fabricated_retention_days_are_rejected(self):
        self.m['policies'][0]['retention_days']=30;self.assertRaises(RecoveryError,self.inventory)
    def test_missing_policy_domain_is_rejected(self):
        self.m['policies']=[];self.assertRaises(RecoveryError,self.inventory)
    def test_missing_external_sink_is_rejected(self):
        self.m['external_surfaces'].pop();self.assertRaises(RecoveryError,self.inventory)
    def test_injected_deletion_authority_is_rejected(self):
        self.m['deletion_authorized']=True;self.assertRaises(RecoveryError,self.inventory)
    def test_matching_journal_never_releases_quarantine(self):
        r=self.rejoin();self.assertTrue(r['journal_matches_independent']);self.assertEqual('BLOCKED',r['result']);self.assertFalse(any(r[k] for k in ['quarantine_released','workers_authorized','exporter_authorized','deletion_authorized','production_ready']))
    def test_equivalent_timezone_is_not_a_fork(self):
        self.s['events'][0]['effective_at']='2026-10-11T16:00:00+08:00';self.assertTrue(self.rejoin()['journal_matches_independent'])
    def test_offline_replay_timestamp_fork_is_detected(self):
        self.s['events'][0]['effective_at']='2026-10-11T08:01:00+00:00';self.assertIn('RESTORED_JOURNAL_FORK_OR_INCOMPLETE',self.rejoin()['reasons'])
    def test_missing_independent_tail_is_detected(self):
        self.s.update(events=[],last_sequence=0);self.assertFalse(self.rejoin()['journal_matches_independent'])
    def test_local_counter_gap_is_rejected(self):
        self.s['last_sequence']=2;self.assertRaises(RecoveryError,self.rejoin)
    def test_wrong_cluster_or_journal_is_rejected(self):
        self.s['journal_id']='00000000-0000-4000-8000-000000000099';self.assertRaises(RecoveryError,self.rejoin)
    def test_pending_outbox_and_restored_sessions_are_reported(self):
        self.s.update(pending_outbox=2,active_sessions=1);r=self.rejoin();self.assertIn('PENDING_OUTBOX_REQUIRES_RECONCILIATION',r['reasons']);self.assertIn('RESTORED_AUTHORITY_STILL_ACTIVE',r['reasons'])
    def test_subjects_and_payloads_never_enter_public_report(self):
        r=self.rejoin();self.assertNotIn(self.event['subject_id'],json.dumps(r));self.assertNotIn('events',r)
    def test_unsupported_action_or_subject_sql_is_rejected(self):
        self.s['events'][0]['kind']='DELETE_ACCOUNT';self.assertRaises(RecoveryError,self.rejoin)
    def test_mutation_payload_in_snapshot_is_rejected(self):
        self.s['execute']='DROP TABLE app_user';self.assertRaises(RecoveryError,self.rejoin)

if __name__=='__main__':unittest.main()
