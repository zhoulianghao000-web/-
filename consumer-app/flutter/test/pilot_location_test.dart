import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/nearby_repository.dart';

void main() {
  test(
    'pilot allowed location is fixed Chongqing without platform access',
    () async {
      final p = await LocationProvider(PilotGeolocation()).locate();
      expect(p.longitude, 106.551556);
      expect(p.latitude, 29.563009);
    },
  );
  test(
    'pilot denial does not request device settings or real coordinates',
    () async {
      final device = PilotGeolocation('DENIED');
      await expectLater(
        LocationProvider(device).locate(),
        throwsA(
          isA<LocationFailure>().having(
            (e) => e.issue,
            'issue',
            LocationIssue.denied,
          ),
        ),
      );
      expect(await device.settings(), false);
    },
  );
  test('pilot disabled service keeps a distinct failure', () async {
    await expectLater(
      LocationProvider(PilotGeolocation('DISABLED')).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (e) => e.issue,
          'issue',
          LocationIssue.disabled,
        ),
      ),
    );
  });
}
