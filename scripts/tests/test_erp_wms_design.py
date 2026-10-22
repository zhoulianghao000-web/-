"""Design guard regressions, not integration tests or runtime payment evidence."""
import copy,importlib.util,sys,unittest,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'))
from erp_wms_design_contract import DesignError,stock_projection,delivery_result,paid_cancellation,shipment_application,event_identity
spec=importlib.util.spec_from_file_location('v32_validator',ROOT/'openapi/validate_v32_design.py');validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(validator)

class ErpWmsDesignTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.inputs=validator.load_inputs()
 def inputs_copy(self):return copy.deepcopy(self.inputs)
 def rejected(self,inputs,code):
  with self.assertRaisesRegex(DesignError,code):validator.validate_artifact(*inputs,actual_rows=validator.runtime_rows())
 def sample(self,name):return copy.deepcopy(next(c['input'] for c in self.inputs[1]['cases'] if c['name']==name))
 def test_all_golden_counterexamples_and_runtime_baseline(self):
  report=validator.validate_artifact(*self.inputs);self.assertEqual((report['positive_cases'],report['negative_cases']),(14,52));self.assertEqual(report['actual_http_responses'],0)
 def test_live_server_cannot_be_claimed_by_draft(self):
  inputs=self.inputs_copy();inputs[0]['servers'][0]['url']='https://example.com/api/v1';self.rejected(inputs,'DESIGN_SERVER_REQUIRED')
 def test_operation_cannot_claim_implemented(self):
  inputs=self.inputs_copy();next(iter(next(iter(inputs[0]['paths'].values())).values()))['x-runtime-implemented']=True;self.rejected(inputs,'OPERATION_NOT_DRAFT')
 def test_client_cannot_choose_endpoint_or_provider_outcome(self):
  for field in ['endpoint','credential','outcome']:
   with self.subTest(field=field):
    inputs=self.inputs_copy();inputs[0]['components']['schemas']['ConnectionInput']['properties'][field]={'type':'string'};self.rejected(inputs,'CLIENT_AUTHORITY_FORBIDDEN')
 def test_client_cannot_choose_stock_quantity_or_watermark(self):
  for field in ['target_on_hand_qty','external_remaining_qty','acknowledged_local_sequence']:
   with self.subTest(field=field):
    inputs=self.inputs_copy();inputs[0]['components']['schemas']['StockApplyInput']['properties'][field]={'type':'integer'};self.rejected(inputs,'CLIENT_AUTHORITY_FORBIDDEN')
 def test_idempotency_and_action_proof_cannot_be_removed(self):
  for field,code in [('Idempotency-Key','IDEMPOTENCY_REQUIRED'),('X-Reverify-Token','ACTION_PROOF_REQUIRED')]:
   with self.subTest(field=field):
    inputs=self.inputs_copy();op=next(v['post'] for p,v in inputs[0]['paths'].items() if p.endswith('/inventory-previews/{preview_id}/apply'));op['parameters']=[p for p in op['parameters'] if p['name']!=field];self.rejected(inputs,code)
 def test_original_fulfillment_permission_cannot_be_bypassed(self):
  inputs=self.inputs_copy();op=next(v['post'] for p,v in inputs[0]['paths'].items() if '/shipment-events/' in p);op['x-proposed-permissions'].remove('order.ship');self.rejected(inputs,'NATIVE_SHIPMENT_PERMISSION_REQUIRED')
 def test_real_supplier_gaps_cannot_be_invented(self):
  inputs=self.inputs_copy();inputs[2]['gaps'][0]['status']='CONFIRMED';self.rejected(inputs,'EXTERNAL_RULES_NOT_CONFIRMED')
 def test_stock_journal_missing_or_duplicated_facts_are_rejected(self):
  for field,value in [('sequence',4),('source_id','TEST_ONLY_SALE_1')]:
   with self.subTest(field=field):
    state=self.sample('TEST_ONLY_STOCK_SALE_AND_RETURN_WATERMARK');state['movements'][2][field]=value
    with self.assertRaisesRegex(DesignError,'MOVEMENT_CHAIN_INVALID'):stock_projection(state)
 def test_unknown_after_last_attempt_keeps_fixed_key_and_responsibility(self):
  state=self.sample('TEST_ONLY_DELIVERY_EXHAUSTED_RETAINS_RESPONSIBILITY');result=delivery_result(state);self.assertEqual(result,{'state':'NEEDS_REVIEW','responsibility_open':True,'business_key':'TEST_ONLY_ORDER_1'})
  rejected=self.sample('TEST_ONLY_DELIVERY_REJECTED');rejected['rejection_proven_no_external_order']=False
  with self.assertRaisesRegex(DesignError,'EXTERNAL_REJECTION_UNPROVEN'):delivery_result(rejected)
 def test_same_event_id_cannot_hide_changed_payload(self):
  self.assertEqual(event_identity('a'*64,'a'*64),'DUPLICATE_NO_SIDE_EFFECT')
  with self.assertRaisesRegex(DesignError,'EVENT_IDENTITY_CONFLICT'):event_identity('a'*64,'b'*64)
 def test_security_exception_cannot_expand_or_relax_scanning(self):
  inputs=self.inputs_copy();inputs[5]['changes'][0]['path']='backend/src/main/java/Unsafe.java';self.rejected(inputs,'SECURITY_AMENDMENT_SCOPE_INVALID')
  inputs=self.inputs_copy();inputs[5]['scan_policy_relaxed']=True;self.rejected(inputs,'SECURITY_AMENDMENT_SCOPE_INVALID')
 def test_generated_bundles_do_not_hide_real_or_new_runtime_inputs(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);names=['openapi/pawday-v3.1.3-b3.json','openapi/pawday-v1.bundle.json','openapi/pawday-m3.1.redocly.bundle.json','backend/src/main/java/Source.java']
   for name in names:
    p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('TEST_ONLY_ORIGINAL',encoding='utf-8')
   original=validator.source_rows(names,root);self.assertEqual(len(original),2)
   for name in names[1:3]:(root/name).write_text('TEST_ONLY_REGENERATED',encoding='utf-8')
   self.assertEqual(validator.source_rows(names,root),original)
   (root/names[-1]).write_text('TEST_ONLY_CHANGED_SOURCE',encoding='utf-8');self.assertNotEqual(validator.source_rows(names,root),original)
   new='openapi/pawday-v3.2-b1.json';(root/new).write_text('TEST_ONLY_NEW_CONTRACT',encoding='utf-8');self.assertEqual(len(validator.source_rows(names+[new],root)),3)
 def test_changed_runtime_file_cannot_pass_design_only_claim(self):
  rows=validator.runtime_rows();rows[0]['sha256']='0'*64
  with self.assertRaisesRegex(DesignError,'RUNTIME_SOURCE_CHANGED'):validator.validate_artifact(*self.inputs,actual_rows=rows)

if __name__=='__main__':unittest.main()
