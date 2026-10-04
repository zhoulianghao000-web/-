import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';

// Explicit CI entry point. Missing infrastructure fails; this test never uses a mock transport.
void main() {
  test('real OTP Outbox delivery, login, refresh, restore, session list and logout', () async {
    final env = Platform.environment;
    final base = env['PAWDAY_REAL_API_BASE'];
    final directory = env['PAWDAY_REAL_SMS_DIRECTORY'];
    if (base == null || directory == null) {
      throw StateError(
        'Real API and local SMS delivery directory are required',
      );
    }
    final vault = MemoryVault();
    final api = ConsumerApi(
      base: Uri.parse(base),
      transport: http.Client(),
      vault: vault,
    );
    const phone = '+8613900000024';
    await api.requestCode(phone);
    String? code;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (code == null && DateTime.now().isBefore(deadline)) {
      final inbox = Directory(directory);
      if (await inbox.exists()) {
        for (final entity in inbox.listSync().whereType<File>()) {
          final lines = await entity.readAsLines();
          if (lines.length >= 2 && lines[0] == phone) {
            code = lines[1];
            break;
          }
        }
      }
      if (code == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    expect(
      code,
      isNotNull,
      reason: 'Real RabbitMQ consumer must deliver the OTP',
    );
    final principal = await api.login(phone, code!);
    expect(principal.realm, 'CONSUMER');
    expect(principal.user_id, isNotNull);
    await api.refresh();
    expect(
      (await api.sessions()).any((s) => s.id == principal.session_id),
      true,
    );
    api.dispose();
    final restored = ConsumerApi(
      base: Uri.parse(base),
      transport: http.Client(),
      vault: vault,
    );
    await restored.restore();
    expect((await restored.me()).user_id, principal.user_id);
    await restored.logout();
    expect(restored.authenticated, false);
    expect(vault.values['consumer.session'], isNull);
    restored.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
