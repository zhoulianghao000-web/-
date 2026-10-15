"""Require reference images, licenses and identity isolation in merchant artifacts."""
from pathlib import Path
import zipfile

root=Path(__file__).resolve().parents[1]
app=root/'merchant-app/flutter'
web=app/'build/web/assets'
apk=app/'build/app/outputs/flutter-apk/app-debug.apk'
with zipfile.ZipFile(apk) as archive:
    for source in [app/'assets/fonts/OFL.txt',*(app/'assets/reference').glob('*.jpg')]:
        relative=source.relative_to(app).as_posix()
        assert archive.read('assets/flutter_assets/'+relative)==source.read_bytes(),relative
        assert (web/relative).read_bytes()==source.read_bytes(),relative
        assert source.read_bytes()==(root/'consumer-app/flutter'/relative).read_bytes(),relative
    assert len(list((app/'assets/reference').glob('*.jpg')))==11
assert 'cn.pawday.pawday_merchant' in (app/'android/app/build.gradle.kts').read_text()
assert 'android:allowBackup="false"' in (app/'android/app/src/main/AndroidManifest.xml').read_text()
assert "'merchant.session'" in (app/'lib/api/client.dart').read_text()
print('PASS: merchant artifacts preserve all 11 photos/license; distinct package and storage keys')
