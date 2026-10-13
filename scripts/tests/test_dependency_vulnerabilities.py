import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import io

spec = importlib.util.spec_from_file_location("dependency_scan", Path(__file__).parents[1] / "check-dependency-vulnerabilities.py")
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)


class DependencyGateTests(unittest.TestCase):
    def test_incomplete_database_response_cannot_be_pass(self):
        with patch.object(scanner.urllib.request, "urlopen", return_value=io.BytesIO(b'{"results":[]}')):
            with self.assertRaises(ValueError):
                scanner.scan([{"package": {"ecosystem": "Maven", "name": "TEST:test"}, "version": "1"}])

    def test_known_vulnerability_is_retained(self):
        with patch.object(scanner.urllib.request, "urlopen", return_value=io.BytesIO(b'{"results":[{"vulns":[{"id":"TEST-GHSA"}]}]}')):
            result = scanner.scan([{"package": {"ecosystem": "Maven", "name": "TEST:test"}, "version": "1"}])
            self.assertEqual("TEST-GHSA", result[0]["vulnerabilities"][0]["id"])

    def test_resolved_runtime_and_classifier_versions_not_test_dependencies(self):
        with tempfile.TemporaryDirectory() as root:
            maven, pub = Path(root)/"maven.txt", Path(root)/"pub.lock"
            maven.write_text("   test:app:jar:1.2:compile\n   test:native:jar:linux:2.3:runtime\n   test:unit:jar:9:test\n")
            pub.write_text('packages:\n  test_pub:\n    source: hosted\n    version: "3.4"\n  sdk:\n    source: sdk\n    version: "0.0"\n')
            values = scanner.packages(maven, pub)
            self.assertEqual(["1.2", "2.3", "3.4"], [v["version"] for v in values])

    def test_empty_dependency_manifest_is_not_a_clean_scan(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/"empty";path.write_text("")
            with self.assertRaises(ValueError):
                scanner.packages(path, path)
