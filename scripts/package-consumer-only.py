"""Package the current source with verified, unchanged V2.3 runtime artifacts.

Never reads .pilot or copies untracked workspace files. Historical merchant App
source, binaries and preview are explicitly excluded from both deliverables.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import zipfile


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def allowed(name):
    parts = PurePosixPath(name).parts
    return (not name.startswith(('merchant-app/', 'release/merchant-web/app/'))
            and not any(part in {'.pilot', '.maintenance', '.git', 'node_modules'} for part in parts)
            and (not name.lower().endswith('.apk') or name == 'release/consumer.apk'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--installation', type=Path, required=True)
    parser.add_argument('--baseline-development', type=Path, required=True)
    parser.add_argument('--baseline-verification', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    source, installed = args.source.resolve(), args.installation.resolve()
    verification = json.loads(args.baseline_verification.read_text(encoding='utf-8-sig'))
    assert verification['result'] == 'PASS'
    expected = verification['packages'][args.baseline_development.name]['sha256']
    assert digest(args.baseline_development) == expected, 'Baseline Development ZIP mismatch'
    for name, key in [('release/consumer.apk', 'Pawday-Consumer-2.0.3-debug.apk')]:
        assert digest(installed / name) == verification['packages'][key]['sha256'], name
    # The recorded backend bytes are checked against the baseline archive below.
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=source).decode().split('\0')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source).decode().strip()
    subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--'], cwd=source, check=True)
    names = [name for name in names if name and allowed(name)]
    for name in names:
        assert (source / name).resolve().is_relative_to(source), name
    manifest = json.loads((installed / 'release/desktop-manifest.json').read_text(encoding='utf-8-sig'))
    manifest = {key: value for key, value in manifest.items() if not key.startswith('merchant_')}
    manifest.update(version='2.0.3-consumer-only', delivery_commit=commit,
                    scope_code_commit=commit, android_targets=['consumer'],
                    web_targets=['consumer', 'merchant', 'admin'], retired_merchant_app=True)
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
    args.out.mkdir(parents=True, exist_ok=True)
    packages = {}
    with zipfile.ZipFile(args.baseline_development) as baseline:
        for name in ['release/consumer.apk', 'release/pawday-backend.jar']:
            assert hashlib.sha256(baseline.read(name)).hexdigest() == digest(installed / name), name
        runtime_names = [name for name in baseline.namelist()
                         if name.startswith(('runtime/', 'release/', 'desktop/dist/')) and not name.endswith('/')
                         and allowed(name) and name != 'release/desktop-manifest.json']
        # Every retained installed runtime artifact must still match the verified ZIP.
        for name in runtime_names:
            assert hashlib.sha256(baseline.read(name)).hexdigest() == digest(installed / name), name
        for kind in ['Source', 'Development']:
            path = args.out / f'Pawday-V2-{kind}-2.0.3-consumer-only.zip'
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for name in names:
                    archive.write(source / name, name)
                for name in ['PawdayV1实施计划.md', 'PawdayV2实施计划.md']:
                    archive.write(source / 'docs' / name, name)
                if kind == 'Development':
                    for name in runtime_names:
                        archive.writestr(name, baseline.read(name))
                    archive.writestr('release/desktop-manifest.json', manifest_bytes)
            with zipfile.ZipFile(path) as archive:
                assert all(allowed(name) for name in archive.namelist())
                apk_names = [name for name in archive.namelist() if name.endswith('.apk')]
                assert apk_names == (['release/consumer.apk'] if kind == 'Development' else [])
            packages[path.name] = {'sha256': digest(path), 'size': path.stat().st_size}
    (args.out / 'package-hashes.json').write_text(json.dumps({
        'result': 'PASS', 'delivery_commit': commit, 'packages': packages,
        'android_targets': ['consumer'], 'retired_artifacts_excluded': True,
        'runtime_reused_from_verified_v23': True,
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'result': 'PASS', 'packages': packages}, indent=2))


if __name__ == '__main__':
    main()
