import importlib.util
import hashlib
import io
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
import zipfile

spec = importlib.util.spec_from_file_location("vendor_patch", Path(__file__).parents[2]/"deployment/images/patch-opensearch-libraries.py")
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)


class VendorPatchIntegrityTests(unittest.TestCase):
    def artifact(self):
        content=io.BytesIO()
        with zipfile.ZipFile(content, "w") as archive:
            archive.writestr("META-INF/maven/test/library/pom.properties", "groupId=test\nartifactId=library\nversion=1.1\n")
        data=content.getvalue()
        return data, {"group":"test", "artifact":"library", "old_version":"1.0", "version":"1.1", "url":"https://repo.maven.apache.org/maven2/test/library/1.1/library-1.1.jar", "sha256":hashlib.sha256(data).hexdigest()}

    def test_all_duplicate_plugin_libraries_replaced_without_old_version(self):
        data, entry=self.artifact()
        with tempfile.TemporaryDirectory() as root:
            root=Path(root)
            for name in ["lib", "plugins/test"]:
                folder=root/name;folder.mkdir(parents=True);(folder/"library-1.0.jar").write_bytes(b"OLD")
            with patch.object(vendor.urllib.request,"urlopen",return_value=io.BytesIO(data)):
                result=vendor.patch(root,[entry])
            self.assertEqual(2,len(result));self.assertFalse(list(root.rglob("library-1.0.jar")))
            self.assertEqual(2,len(list(root.rglob("library-1.1.jar"))))

    def test_integrity_failure_preserves_original_library(self):
        data, entry=self.artifact()
        with tempfile.TemporaryDirectory() as root:
            root=Path(root);old=root/"library-1.0.jar";old.write_bytes(b"OLD")
            with patch.object(vendor.urllib.request,"urlopen",return_value=io.BytesIO(data+b"TAMPER")):
                with self.assertRaises(ValueError):vendor.patch(root,[entry])
            self.assertEqual(b"OLD",old.read_bytes());self.assertFalse((root/"library-1.1.jar").exists())

    def test_missing_required_library_fails_instead_of_silent_success(self):
        _, entry=self.artifact()
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(ValueError):vendor.patch(Path(root),[entry])

    def test_nonofficial_download_destination_refused(self):
        _, entry=self.artifact();entry["url"]="https://untrusted.invalid/library.jar"
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(ValueError):vendor.patch(Path(root),[entry])
