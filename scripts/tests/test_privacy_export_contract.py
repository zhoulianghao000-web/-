import base64,hashlib,hmac,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]))
from privacy_export_contract import verify_export
from recovery_contract import RecoveryError

class PrivacyExportContractTests(unittest.TestCase):
 def setUp(self):
  self.key=b'TEST_ONLY_M64_PRIVATE_EXPORT_32_BYTES';self.journal='64000000-0000-4000-8000-000000000001'
  self.m=dict(schema_version='pawday-privacy-export/v1',system_id='123',journal_id=self.journal,installed_at='2026-10-10T00:00:00Z',covered_until='2026-10-10T01:00:00Z',last_sequence=1,events=[dict(sequence=1,kind='MEDIA_DELETE',subject_id=self.journal,effective_at='2026-10-10T00:30:00Z')])
 def check(self,**overrides):
  raw=json.dumps(self.m).encode();outer=json.dumps(dict(payload=base64.b64encode(raw).decode(),signature=hmac.new(self.key,raw,hashlib.sha256).hexdigest())).encode()
  args=dict(system_id='123',journal_id=self.journal,required_until='2026-10-10T00:45:00Z',minimum_sequence=1,expected_checkpoint_sha256=hashlib.sha256(raw).hexdigest(),now='2026-10-10T02:00:00Z',backup_id='a'*32);args.update(overrides)
  return verify_export(outer,self.key,**args)
 def test_signed_current_prefix_binds_to_requested_backup(self):self.assertEqual('a'*32,self.check()['backup_id'])
 def test_old_authenticated_head_is_not_latest_proof(self):
  with self.assertRaisesRegex(RecoveryError,'TRUSTED_LATEST'):self.check(expected_checkpoint_sha256='b'*64)
 def test_empty_registry_cannot_cover_nonzero_tail(self):
  self.m.update(last_sequence=0,events=[])
  with self.assertRaisesRegex(RecoveryError,'TAIL_MISSING'):self.check()
 def test_missing_final_event_rejected(self):
  with self.assertRaises(RecoveryError):self.check(minimum_sequence=2)
 def test_coverage_must_include_current_review_time(self):
  with self.assertRaises(RecoveryError):self.check(required_until='2026-10-10T01:01:00Z')
 def test_other_database_rejected(self):
  with self.assertRaises(RecoveryError):self.check(system_id='OTHER')
 def test_other_journal_rejected(self):
  with self.assertRaises(RecoveryError):self.check(journal_id='64000000-0000-4000-8000-000000000002')
 def test_future_watermark_rejected(self):
  self.m['covered_until']='2026-10-11T00:00:00Z'
  with self.assertRaises(RecoveryError):self.check()
 def test_sequence_gap_rejected(self):
  self.m['events'][0]['sequence']=2
  with self.assertRaises(RecoveryError):self.check()
 def test_unknown_action_rejected(self):
  self.m['events'][0]['kind']='REFUND'
  with self.assertRaises(RecoveryError):self.check()
 def test_unknown_fields_rejected(self):
  self.m['credential']='DO_NOT_ACCEPT'
  with self.assertRaises(RecoveryError):self.check()
 def test_origin_must_predate_coverage(self):
  self.m['installed_at']='2026-10-11T00:00:00Z'
  with self.assertRaises(RecoveryError):self.check()
 def test_trusted_pin_is_mandatory(self):
  with self.assertRaises(RecoveryError):self.check(expected_checkpoint_sha256=None)
 def test_negative_watermark_rejected(self):
  with self.assertRaises(RecoveryError):self.check(minimum_sequence=-1)
