"""Scan tracked source and all four engineering runtime images. No private runtime data."""
from pathlib import Path
import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "backend/target/security-evidence"
TOOLS = ROOT / "backend/target/security-tools"


def tool(project, version, archive_name, checksum_name, binary):
    base = "https://github.com/" + project + "/releases/download/v" + version + "/"
    with urllib.request.urlopen(base + checksum_name, timeout=30) as response:
        checksums = response.read(1_000_000).decode()
    digest = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == archive_name)
    with urllib.request.urlopen(base + archive_name, timeout=60) as response:
        data = response.read(100_000_001)
    if len(data) > 100_000_000 or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError("Scanner release checksum mismatch")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        content = archive.extractfile(binary).read()
    path = TOOLS / binary
    path.write_bytes(content)
    path.chmod(0o700)
    return path


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    TOOLS.mkdir(parents=True, exist_ok=True)
    leaks = tool("gitleaks/gitleaks", "8.30.1", "gitleaks_8.30.1_linux_x64.tar.gz", "gitleaks_8.30.1_checksums.txt", "gitleaks")
    trivy = tool("aquasecurity/trivy", "0.75.0", "trivy_0.75.0_Linux-64bit.tar.gz", "trivy_0.75.0_checksums.txt", "trivy")
    # Only tracked project source; exclude private .pilot, credentials, live uploads and build output.
    with tempfile.TemporaryDirectory(prefix="pawday-security-source-") as temporary:
        source = Path(temporary)
        names = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
        for name in names:
            if not name:
                continue
            original, target = ROOT / name, source / name
            if not original.resolve().is_relative_to(ROOT) or not target.resolve().is_relative_to(source):
                raise ValueError("Source outside checkout")
            if original.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, target)
        subprocess.run([str(leaks), "dir", str(source), "--config", str(ROOT / ".gitleaks.toml"),
                        "--redact=100", "--no-banner", "--report-format", "json", "--report-path", str(OUT / "source-secrets.json")], check=True)
    images = ["pawday-postgres:17.11-security20261013", "pawday-redis:8.2.10-security20261013",
              "pawday-rabbitmq:4.3.6-security20261013", "pawday-opensearch:3.9.0-security20261013"]
    summaries = []
    for image in images:
        report = OUT / (image.split(":")[0] + ".json")
        subprocess.run([str(trivy), "image", "--scanners", "vuln", "--pkg-types", "os,library", "--no-progress",
                        "--timeout", "10m", "--exit-code", "1", "--format", "json", "--output", str(report), image], check=True)
        result = json.loads(report.read_text())
        findings = [v for r in result.get("Results", []) for v in r.get("Vulnerabilities", [])]
        if findings:
            raise ValueError("Runtime image contains known vulnerabilities")
        summaries.append({"image": image, "known_vulnerabilities": 0})
    summary = {"result": "PASS", "source_secrets": 0, "images": summaries,
               "tool_versions": {"gitleaks": "8.30.1", "trivy": "0.75.0"}, "scanner_release_checksums_verified": True}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary))


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
