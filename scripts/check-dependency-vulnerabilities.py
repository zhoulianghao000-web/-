"""Fail-closed OSV lookup of resolved runtime Maven and locked hosted Pub versions."""
import argparse
import datetime
import json
from pathlib import Path
import time
import urllib.request
import yaml


def packages(maven, pub):
    found = []
    for line in Path(maven).read_text(encoding="utf-8").splitlines():
        parts = line.strip().split(" -- ")[0].split(":")
        if len(parts) >= 5 and parts[-1] in ("compile", "runtime"):
            found.append({"package": {"ecosystem": "Maven", "name": parts[0] + ":" + parts[1]}, "version": parts[-2]})
    if not found:
        raise ValueError("No resolved Maven packages: dependency coverage is empty")
    data = yaml.safe_load(Path(pub).read_text(encoding="utf-8"))["packages"]
    hosted = [{"package": {"ecosystem": "Pub", "name": name}, "version": item["version"]}
              for name, item in data.items() if item.get("source") == "hosted"]
    if not hosted:
        raise ValueError("No locked hosted Pub packages: dependency coverage is empty")
    return found + hosted


def scan(queries):
    findings = []
    for start in range(0, len(queries), 100):
        batch = queries[start:start + 100]
        request = urllib.request.Request("https://api.osv.dev/v1/querybatch",
                                        data=json.dumps({"queries": batch}).encode(),
                                        headers={"Content-Type": "application/json"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    value = json.load(response)
                break
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(attempt + 1)
        results = value.get("results")
        if not isinstance(results, list) or len(results) != len(batch):
            raise ValueError("Incomplete vulnerability database response")
        for package, result in zip(batch, results):
            if not isinstance(result, dict) or result.get("next_page_token"):
                raise ValueError("Incomplete vulnerability coverage")
            if result.get("vulns"):
                findings.append({"package": package, "vulnerabilities": result["vulns"]})
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maven-dependencies", required=True)
    parser.add_argument("--pub-lock", default="consumer-app/flutter/pubspec.lock")
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report = {"result": "ERROR", "source": "https://api.osv.dev/v1/querybatch",
              "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        queries = packages(args.maven_dependencies, args.pub_lock)
        findings = scan(queries)
        report.update(result="FAIL" if findings else "PASS", checked_packages=len(queries), queries=queries, findings=findings)
    except Exception as error:
        report["error_type"] = type(error).__name__
    target = Path(args.report)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("result", "checked_packages", "findings", "error_type") if k in report}))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
