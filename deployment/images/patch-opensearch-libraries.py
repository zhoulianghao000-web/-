"""Replace only explicitly versioned vendor libraries using pinned upstream SHA-256."""
import hashlib
import io
import json
from pathlib import Path
import urllib.parse
import urllib.request
import zipfile


def patch(root, entries):
    root = root.resolve()
    replaced = []
    for entry in entries:
        url = urllib.parse.urlsplit(entry["url"])
        if url.scheme != "https" or url.netloc != "repo.maven.apache.org" or url.query or url.fragment:
            raise ValueError("Only official Maven HTTPS artifacts are permitted")
        old_name = entry["artifact"] + "-" + entry["old_version"] + ".jar"
        matches = list(root.rglob(old_name))
        # Optional JLine peers are aligned when present; all vulnerable components must exist.
        if not matches:
            if entry.get("optional"):
                continue
            raise ValueError("Expected vendor library missing: " + old_name)
        with urllib.request.urlopen(entry["url"], timeout=30) as response:
            data = response.read(16_000_001)
        if len(data) > 16_000_000 or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError("Vendor artifact integrity check failed")
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            metadata = archive.read("META-INF/maven/" + entry["group"] + "/" + entry["artifact"] + "/pom.properties").decode()
            properties = dict(line.split("=", 1) for line in metadata.splitlines() if "=" in line and not line.startswith("#"))
            if properties.get("version") != entry["version"] or properties.get("groupId") != entry["group"] or properties.get("artifactId") != entry["artifact"]:
                raise ValueError("Unexpected vendor artifact identity")
        for old in matches:
            if old.is_symlink() or not old.resolve().is_relative_to(root):
                raise ValueError("Vendor library outside the image runtime")
            target = old.with_name(entry["artifact"] + "-" + entry["version"] + ".jar")
            if target.exists():
                raise ValueError("Duplicate vendor library version")
            target.write_bytes(data)
            target.chmod(0o644)
            old.unlink()
            replaced.append({"path": str(target.relative_to(root)), "group": entry["group"], "artifact": entry["artifact"], "old_version": entry["old_version"], "version": entry["version"], "sha256": entry["sha256"]})
    return replaced


if __name__ == "__main__":
    root = Path("/usr/share/opensearch")
    entries = json.loads(Path(__file__).with_name("opensearch-library-patches.json").read_text())
    replaced = patch(root, entries)
    (root / "pawday-security-patches.json").write_text(json.dumps(replaced, indent=2) + "\n")
    print("Verified vendor library replacements:", len(replaced))
