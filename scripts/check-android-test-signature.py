"""Compare the actual APK v2 certificate to the configured internal debug key."""
import argparse
import hashlib
from pathlib import Path
import struct
import subprocess


def certificate(apk):
    data = apk.read_bytes()
    end = data.rfind(b'PK\x05\x06')
    assert end >= 0, 'Missing ZIP end record'
    cd = struct.unpack_from('<I', data, end + 16)[0]
    assert data[cd - 16:cd] == b'APK Sig Block 42', 'Missing APK signing block'
    size = struct.unpack_from('<Q', data, cd - 24)[0]
    pos = cd - size

    def lp(value, offset=0):
        length = struct.unpack_from('<I', value, offset)[0]
        assert offset + 4 + length <= len(value)
        return value[offset + 4:offset + 4 + length], offset + 4 + length

    while pos < cd - 24:
        length = struct.unpack_from('<Q', data, pos)[0]
        kind = struct.unpack_from('<I', data, pos + 8)[0]
        assert length >= 4 and pos + 8 + length <= cd - 24
        if kind == 0x7109871a:
            signers, _ = lp(data[pos + 12:pos + 8 + length])
            signer, after = lp(signers)
            assert after == len(signers), 'Expected one internal signer'
            signed, _ = lp(signer)
            _, next_pos = lp(signed)
            certs, _ = lp(signed, next_pos)
            cert, _ = lp(certs)
            return hashlib.sha256(cert).hexdigest()
        pos += 8 + length
    raise AssertionError('Missing APK v2 certificate')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--keystore', type=Path, required=True)
    args = parser.parse_args()
    cert = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(args.keystore),
                                    '-alias', 'AndroidDebugKey', '-storepass', 'android'])
    expected = hashlib.sha256(cert).hexdigest()
    actual = certificate(args.apk)
    assert actual == expected, f'Internal certificate mismatch: expected {expected}, actual {actual}'
    print(f'Internal APK certificate PASS: {actual}')
