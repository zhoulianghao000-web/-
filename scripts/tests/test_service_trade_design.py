"""Mutation checks on design boundaries, not claims of live financial verification."""
import copy,importlib.util,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
spec=importlib.util.spec_from_file_location('v313_design',ROOT/'openapi/validate_v313_design.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
from service_trade_design_contract import DesignError,refund_commission_delta,validate_snapshot
class ServiceTradeDesignTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.inputs=m.load_inputs()
 def reject(self,index,mutate,code):
  inputs=copy.deepcopy(self.inputs);mutate(inputs[index])
  with self.assertRaisesRegex(DesignError,code):m.validate_artifact(*inputs)
 def test_design_cases_and_all_operation_shapes(self):
  report=m.validate_artifact(*self.inputs);self.assertEqual(23,report['operations']);self.assertEqual(0,report['actual_http_responses']);self.assertFalse(report['runtime_verified']);self.assertGreater(report['negative_snapshot_cases'],20)
 def test_draft_cannot_claim_runtime_implementation(self):self.reject(0,lambda d:d.update({'x-runtime-implemented':True}),'DESIGN_BOUNDARY_REQUIRED')
 def test_designed_endpoint_cannot_silently_lose_security(self):self.reject(0,lambda d:d['paths']['/consumer/service-trade-orders']['post'].update(security=[]),'REALM_SECURITY_MISMATCH')
 def test_examples_cannot_be_reported_as_actual_http(self):self.reject(1,lambda d:d.update(actual_http_responses=1),'SYNTHETIC_EVIDENCE_ONLY')
 def test_missing_policy_cannot_be_promoted_by_filling_a_default(self):self.reject(2,lambda d:d['gaps'][0].update(status='CONFIRMED',confirmed_value='default'),'UNSUPPORTED_RULE_CONFIRMATION')
 def test_runtime_source_baseline_is_enforced(self):self.reject(3,lambda d:d['protected_tree'].update(sha256='0'*64),'RUNTIME_BASELINE_CHANGED')
 def test_partial_refund_rounding_is_cumulative_and_replay_safe(self):
  self.assertEqual(1,refund_commission_delta(101,3,34,0));self.assertEqual(0,refund_commission_delta(101,3,34,1));self.assertEqual(2,refund_commission_delta(101,3,101,1))
  for args in [(101,3,102,1),(101,3,0,1),(0,0,0,0),(101,3,34.5,0)]:
   with self.assertRaises(DesignError):refund_commission_delta(*args)
 def test_clerk_cannot_inject_a_paid_result_or_negative_refund(self):
  for schema,value in [('ServiceAttemptInput',{'channel':'SIMULATED_TEST','client_platform':'ANDROID','outcome':'SUCCEEDED'}),('ServiceRefund',{'id':'00000000-0000-4000-8000-000000000001','trade_id':'00000000-0000-4000-8000-000000000001','amount_fen':-1,'state':'SUCCEEDED','version':1,'simulated':True})]:
   with self.assertRaisesRegex(DesignError,'SCHEMA_INVALID'):validate_snapshot(self.inputs[0],schema,value)
if __name__=='__main__':unittest.main()
