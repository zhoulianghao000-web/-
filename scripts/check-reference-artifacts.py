"""Verify the supplied reference photographs in both standalone consumer builds."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parent.parent / 'consumer-app/flutter'
manifest = json.loads((root / 'assets/reference/manifest.json').read_text(encoding='utf8'))
with zipfile.ZipFile(root / 'build/app/outputs/flutter-apk/app-debug.apk') as apk:
    for asset in manifest['assets']:
        name = asset['file']
        expected = asset['sha256']
        for data in [(root / 'build/web/assets/assets/reference' / name).read_bytes(),
                     apk.read('assets/flutter_assets/assets/reference/' + name)]:
            assert hashlib.sha256(data).hexdigest() == expected, name
print('PASS: all 11 reference photographs match in Web and APK')
