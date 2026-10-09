from pathlib import Path
import importlib.util,json,tempfile,unittest

spec=importlib.util.spec_from_file_location('operations_bundle',Path(__file__).parents[1]/'operations_bundle.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name);self.dump=self.root/'input.dump';self.dump.write_bytes(b'TEST_ONLY_DUMP');self.media=self.root/'objects';(self.media/'media').mkdir(parents=True);self.object=self.media/'media/00000000-0000-0000-0000-000000000001.png';self.object.write_bytes(b'TEST_ONLY_IMAGE');self.out=self.root/'bundle';self.sha='a'*40
    def create(self):return b.create_bundle(self.dump,self.media,self.out,self.sha,['secrets://pawday/test-only/auth'],quiesced=True)
    def mutate(self,fn):
        p=self.out/'manifest.json';m=json.loads(p.read_text());fn(m);p.write_text(json.dumps(m))
    def test_bundle_hashes_and_references(self):
        self.create();m=b.verify_bundle(self.out,self.sha);self.assertEqual(2,len(m['files']));self.assertNotIn('key_values',m)
    def test_quiescence_required(self):
        with self.assertRaises(b.BundleError):b.create_bundle(self.dump,self.media,self.out,self.sha,[],quiesced=False)
        self.assertFalse(self.out.exists())
    def test_existing_destination_not_overwritten(self):
        self.create()
        with self.assertRaises(b.BundleError):self.create()
    def test_dump_tamper(self):
        self.create();(self.out/'database.dump').write_bytes(b'CORRUPT')
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_object_tamper(self):
        self.create();next((self.out/'media').glob('*')).write_bytes(b'CORRUPT')
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_path_traversal(self):
        self.create();self.mutate(lambda m:m['files'].update({'../outside':m['files'].pop('database.dump')}))
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_wrong_commit(self):
        self.create()
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,'b'*40)
    def test_secret_value_cannot_replace_reference(self):
        self.create();self.mutate(lambda m:m.update(key_references=['PRIVATE_VALUE']))
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_extra_file_rejected(self):
        self.create();(self.out/'.env').write_text('PRIVATE')
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_unknown_fields_rejected(self):
        self.create();self.mutate(lambda m:m.update(credentials='PRIVATE'))
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_future_time_rejected(self):
        self.create();self.mutate(lambda m:m.update(created_at='2099-01-01T00:00:00+00:00'))
        with self.assertRaises(b.BundleError):b.verify_bundle(self.out,self.sha)
    def test_source_object_outside_keyspace_rejected(self):
        (self.media/'.env').write_text('PRIVATE')
        with self.assertRaises(b.BundleError):self.create()
        self.assertFalse(self.out.exists())
    def test_source_hard_link_rejected(self):
        import os
        os.link(self.object,self.media/'media/00000000-0000-0000-0000-000000000002.png')
        with self.assertRaises(b.BundleError):self.create()
        self.assertFalse(self.out.exists())

if __name__=='__main__':unittest.main()
