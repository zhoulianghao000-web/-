import datetime,hashlib,hmac,importlib.util,json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]))
import recovery_contract as r

class RecoveryContractTests(unittest.TestCase):
 def setUp(self):
  self.key=b'TEST_ONLY_REGISTRY_KEY_32_BYTES__!';self.backup='a'*32;self.system='12345';self.now='2026-10-09T12:00:00+00:00'
  self.m={'schema_version':'pawday-recovery-privacy/v1','backup_id':self.backup,'system_id':self.system,'covered_until':self.now,'last_sequence':1,'events':[{'sequence':1,'kind':'AI_CONVERSATION_DELETE','subject_id':'00000000-0000-4000-8000-000000000001','effective_at':'2026-10-09T11:00:00+00:00'}]}
 def check(self,m=None,**kwargs):
  data=json.dumps(self.m if m is None else m).encode();sig=hmac.new(self.key,data,hashlib.sha256).hexdigest()
  args=dict(backup_id=self.backup,system_id=self.system,required_until='2026-10-09T11:30:00+00:00',now=self.now);args.update(kwargs)
  return r.privacy_registry(data,sig,self.key,**args)
 def test_authenticated_current_registry(self): self.assertEqual(1,self.check()['last_sequence'])
 def test_wrong_backup(self):
  with self.assertRaises(r.RecoveryError):self.check(backup_id='b'*32)
 def test_wrong_cluster(self):
  with self.assertRaises(r.RecoveryError):self.check(system_id='OTHER')
 def test_stale_watermark(self):
  self.m['covered_until']='2026-10-09T11:00:00+00:00'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_future_watermark(self):
  self.m['covered_until']='2026-10-10T00:00:00+00:00'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_gap(self):
  self.m['events'][0]['sequence']=2
  with self.assertRaises(r.RecoveryError):self.check()
 def test_missing_tail(self):
  self.m['last_sequence']=2
  with self.assertRaises(r.RecoveryError):self.check()
 def test_unknown_kind(self):
  self.m['events'][0]['kind']='EXECUTE_SQL'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_subject_injection(self):
  self.m['events'][0]['subject_id']="'; DROP TABLE app_user; --"
  with self.assertRaises(r.RecoveryError):self.check()
 def test_unknown_field(self):
  self.m['secret']='NO_SECRET_ALLOWED'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_unsigned_or_tampered_registry(self):
  for sig in ['', '0'*64]:
   with self.assertRaises(r.RecoveryError):r.privacy_registry(b'{}',sig,self.key,backup_id=self.backup,system_id=self.system,required_until=self.now,now=self.now)
 def test_key_separation_is_required(self):
  with self.assertRaises(r.RecoveryError):r.privacy_registry(b'{}','',b'short',backup_id=self.backup,system_id=self.system,required_until=self.now,now=self.now)
 def test_event_beyond_watermark(self):
  self.m['events'][0]['effective_at']='2026-10-10T00:00:00+00:00'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_timezone_required(self):
  self.m['covered_until']='2026-10-09T12:00:00'
  with self.assertRaises(r.RecoveryError):self.check()
 def test_retention_pins_wal_objects_and_keys(self):
  for pin in ['wal/segment','media/version','secrets://history']:
   with self.assertRaises(r.RecoveryError):r.retention_plan([pin],[pin])
 def test_retention_is_never_delete_authorization(self):self.assertFalse(r.retention_plan(['obsolete'],[])['deletion_authorized'])
 def test_bundle_tamper_and_missing_wal(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'base').mkdir();(p/'wal').mkdir();(p/'base/backup_manifest').write_text('TEST_ONLY');w=p/'wal/000000010000000000000001';w.write_bytes(b'TEST_ONLY')
   m=dict(schema_version='pawday-pitr/v1',source_commit='a'*40,system_id=self.system,backup_id=self.backup,target_time=self.now,files=r.bundle_files(p));r.validate_bundle(p,m,commit='a'*40,system_id=self.system)
   w.write_bytes(b'CORRUPT')
   with self.assertRaises(r.RecoveryError):r.validate_bundle(p,m,commit='a'*40,system_id=self.system)
   w.unlink()
   with self.assertRaises(r.RecoveryError):r.validate_bundle(p,m,commit='a'*40,system_id=self.system)
 def test_external_tablespaces_fail_closed(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'base/pg_tblspc').mkdir(parents=True);(p/'base/pg_tblspc/123').write_text('OUTSIDE')
   with self.assertRaises(r.RecoveryError):r.bundle_files(p)
 def test_replay_sql_has_only_scrubbing_no_financial_or_delivery_mutation(self):
  text=r.privacy_replay_sql(self.check());self.assertIn('transaction_read_only=off',text);self.assertIn('revoked_at',text)
  for name in ['merchant_ledger_entries','outbox_event','payments','refunds','ai_quota_ledger']:self.assertNotIn(name,text)
 def test_replay_sql_defends_whitelist_again(self):
  self.m['events'][0]['kind']='EXECUTE_SQL'
  with self.assertRaises(r.RecoveryError):r.privacy_replay_sql(self.m)

if __name__=='__main__':unittest.main()
