import copy, datetime as dt, hashlib, importlib.util, json, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('admission',ROOT/'scripts/check-production-admission.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.evidence=Path(self.temp.name)
        self.manifest=json.loads((ROOT/'deployment/production-admission.json').read_text(encoding='utf8'))
        self.schema=json.loads((ROOT/'deployment/production-admission.schema.json').read_text(encoding='utf8'))
        self.commit='a'*40;self.now=dt.datetime(2026,10,9,8,tzinfo=dt.timezone.utc)
    def check(self,release=False):
        return gate.evaluate(self.manifest,self.schema,ROOT,self.evidence,release,self.commit,self.now)
    def verify_all(self,mutate=None):
        for row in self.manifest['gates']:
            report={'schema_version':'pawday-production-evidence/v1','gate_id':row['id'],'source_commit':self.commit,
                'environment':'production','result':'PASS','started_at':'2026-10-09T06:00:00Z','finished_at':'2026-10-09T07:00:00Z',
                'tests':{'passed':4,'failed':0,'errors':0,'skipped':0},'scenarios':{s:'PASS' for s in row['required_scenarios']}}
            if mutate: mutate(report)
            raw=json.dumps(report).encode()
            name=row['id']+'.json';(self.evidence/name).write_bytes(raw)
            row.update(status='VERIFIED',blockers=[],evidence=[{'path':name,'sha256':hashlib.sha256(raw).hexdigest()}])
    def invalid_evidence(self,change):
        self.verify_all(change)
        result=self.check(True)
        self.assertEqual('BLOCKED',result['result'])
        self.assertTrue(any('EVIDENCE_INVALID' in r for r in result['reasons']))
        self.assertFalse(result['production_ready'])
    def test_inventory_is_valid_but_not_release_ready(self):
        result=self.check();self.assertEqual('PASS',result['result']);self.assertFalse(result['production_ready']);self.assertEqual(14,result['pending'])
    def test_current_production_release_is_blocked(self):
        result=self.check(True);self.assertEqual('BLOCKED',result['result']);self.assertEqual(15,len(result['reasons']))
    def test_fake_attestations_cannot_remove_runtime_lock(self):
        self.verify_all();result=self.check(True);self.assertEqual(gate.IMPLEMENTATION_BLOCKERS,result['reasons']);self.assertFalse(result['production_ready'])
    def test_missing_gate_rejected(self):
        self.manifest['gates'].pop();self.assertEqual('FAIL',self.check()['result'])
    def test_duplicate_gate_rejected(self):
        self.manifest['gates'][0]=copy.deepcopy(self.manifest['gates'][1]);self.assertEqual('FAIL',self.check()['result'])
    def test_reduced_scenarios_rejected(self):
        self.manifest['gates'][0]['required_scenarios'].pop();self.assertEqual('FAIL',self.check()['result'])
    def test_false_verified_without_evidence_rejected(self):
        self.manifest['gates'][0]['status']='VERIFIED';self.assertEqual('FAIL',self.check()['result'])
    def test_unknown_secret_field_not_echoed(self):
        self.manifest['api_key']='TEST_ONLY_SECRET_VALUE'
        result=self.check();self.assertEqual('FAIL',result['result']);self.assertNotIn('SECRET_VALUE',json.dumps(result))
    def test_only_secret_reference_uris_allowed(self):
        self.manifest['secret_references']=['a-real-value-is-not-a-reference'];self.assertEqual('FAIL',self.check()['result'])
    def test_missing_source_rejected(self):
        self.manifest['gates'][0]['source_files']=['does-not-exist.java'];self.assertEqual('FAIL',self.check()['result'])
    def test_source_escape_rejected(self):
        self.manifest['gates'][0]['source_files']=['../m61-backend-focused.log'];self.assertEqual('FAIL',self.check()['result'])
    def test_evidence_hash_mismatch_rejected(self):
        self.verify_all();(self.evidence/'payment_refund.json').write_text('{}',encoding='utf8')
        self.assertTrue(any('EVIDENCE_INVALID' in r for r in self.check(True)['reasons']))
    def test_stale_evidence_rejected(self):
        self.invalid_evidence(lambda r:r.update(started_at='2025-01-01T00:00:00Z',finished_at='2025-01-01T01:00:00Z'))
    def test_future_evidence_rejected(self):
        self.invalid_evidence(lambda r:r.update(finished_at='2026-10-10T07:00:00Z'))
    def test_development_mock_is_not_production_evidence(self):
        self.invalid_evidence(lambda r:r.update(environment='development'))
    def test_wrong_source_commit_rejected(self):
        self.invalid_evidence(lambda r:r.update(source_commit='b'*40))
    def test_failed_or_skipped_evidence_rejected(self):
        for field in ['failed','errors','skipped']:
            with self.subTest(field=field):
                self.invalid_evidence(lambda r:r['tests'].update({field:1}))
    def test_missing_real_scenario_rejected(self):
        self.verify_all(lambda r:r['scenarios'].clear())
        self.assertTrue(any('SCENARIO_EVIDENCE_MISSING' in r for r in self.check(True)['reasons']))
    def test_evidence_path_escape_rejected(self):
        self.verify_all();self.manifest['gates'][0]['evidence'][0]['path']='../outside.json'
        self.assertEqual('FAIL',self.check(True)['result'])
    def test_unknown_report_fields_rejected(self):
        self.invalid_evidence(lambda r:r.update(private_token='TEST_ONLY'))
if __name__=='__main__':unittest.main()
