import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_merchant/api/client.dart';
import 'package:pawday_merchant/merchant_repository.dart';

void main() {
  test(
    'merchant application uses real identity, scope and ledger analytics HTTP',
    () async {
      final transport = http.Client();
      addTearDown(transport.close);
      final client = MerchantApi(
        base: Uri.parse(Platform.environment['PAWDAY_REAL_API_BASE']!),
        transport: transport,
        vault: MemoryVault(),
        pilot: false,
      );
      final principal = await client.login(
        'local-staff-a',
        Platform.environment['PAWDAY_DEMO_MERCHANT_PASSWORD']!,
      );
      expect(principal.realm, 'MERCHANT');
      expect(principal.merchant_id, isNotNull);
      final repository = MerchantRepository(client);
      final stores = await repository.stores();
      expect(stores, isNotEmpty);
      expect(stores.every((s) => s.merchant_id == principal.merchant_id), true);
      final today = dateText(shanghaiToday()),
          analytics = await repository.analytics(today, today, null);
      expect(analytics.timezone, 'Asia/Shanghai');
      expect(analytics.merchant_id, principal.merchant_id);
      expect(analytics.days.length, 1);
      expect(
        analytics.totals.net_fen,
        analytics.totals.paid_fen - analytics.totals.refund_fen,
      );
      await expectLater(
        repository.analytics(
          today,
          today,
          '00000000-0000-4000-8000-000000000099',
        ),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
      );
      await client.logout();
      expect(client.authenticated, false);
    },
  );
}
