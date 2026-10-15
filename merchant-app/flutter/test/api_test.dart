import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_merchant/api/client.dart';
import 'package:pawday_merchant/merchant_repository.dart';
import 'package:pawday_merchant/session.dart';

const root = 'http://127.0.0.1:8086/api/v1';
Map<String, dynamic> tokens([String token = 'TEST_ACCESS']) => {
  'access_token': token,
  'refresh_token': 'TEST_REFRESH',
  'expires_in': 900,
  'session_id': 'TEST_SESSION',
  'user_id': null,
};
Map<String, dynamic> principal({
  String realm = 'MERCHANT',
  List<String> permissions = const [
    'store.read',
    'offer.read',
    'order.read',
    'ledger.read',
  ],
}) => {
  'id': 'TEST_PRINCIPAL',
  'realm': realm,
  'merchant_id': 'TEST_MERCHANT',
  'user_id': null,
  'session_id': 'TEST_SESSION',
  'permissions': permissions,
};
http.Response ok(Object data) => http.Response(
  jsonEncode({
    'data': data,
    'page': {'has_more': false, 'next_cursor': null},
  }),
  200,
  headers: {
    'content-type': 'application/json',
    'x-pawday-environment': 'SIMULATED_PILOT',
  },
);
http.Response failure(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code},
    'meta': {'request_id': 'TEST_REQUEST'},
  }),
  status,
  headers: {'x-pawday-environment': 'SIMULATED_PILOT'},
);
MerchantApi api(
  Future<http.Response> Function(http.Request) responder, {
  MemoryVault? vault,
  bool pilot = false,
}) => MerchantApi(
  base: Uri.parse(root),
  transport: MockClient(responder),
  vault: vault ?? MemoryVault(),
  pilot: pilot,
);
Future<http.Response> loginFixture(http.Request r) async {
  if (r.url.path.endsWith('/login')) return ok(tokens());
  if (r.url.path.endsWith('/me')) return ok(principal());
  return ok([]);
}

void main() {
  test('merchant session and device storage do not read or overwrite consumer keys', () async {
    final vault = MemoryVault();
    vault.values['consumer.session'] = 'TEST_CONSUMER_PRIVATE';
    vault.values['consumer.device'] = 'TEST_CONSUMER_DEVICE';
    final client = api(loginFixture, vault: vault);
    expect(await client.restore(), isNull);
    await client.login('TEST_STAFF', 'TEST_PASSWORD');
    expect(vault.values['consumer.session'], 'TEST_CONSUMER_PRIVATE');
    expect(vault.values['consumer.device'], 'TEST_CONSUMER_DEVICE');
    expect(vault.values['merchant.device'], isNot('TEST_CONSUMER_DEVICE'));
    await client.clear();
    expect(vault.values.containsKey('merchant.session'), false);
    expect(vault.values['consumer.session'], 'TEST_CONSUMER_PRIVATE');
  });
  test(
    'consumer principal or stored origin cannot become merchant session',
    () async {
      final vault = MemoryVault();
      final client = api(
        (r) async => r.url.path.endsWith('/login')
            ? ok(tokens())
            : ok(principal(realm: 'CONSUMER')),
        vault: vault,
      );
      await expectLater(
        client.login('TEST', 'TEST'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'REALM_MISMATCH'),
        ),
      );
      expect(client.authenticated, false);
      vault.values['merchant.session'] = jsonEncode({
        'realm': 'CONSUMER',
        'api': root,
        'tokens': tokens(),
      });
      await expectLater(client.restore(), throwsA(isA<ApiFailure>()));
      expect(vault.values.containsKey('merchant.session'), false);
    },
  );
  test(
    'only configured merchant paths are sent and redirects are not followed',
    () async {
      int requests = 0;
      final client = api((r) async {
        requests++;
        expect(r.followRedirects, false);
        expect(r.headers.containsKey('X-Request-ID'), true);
        return loginFixture(r);
      });
      await client.login('TEST', 'TEST');
      final before = requests;
      for (final path in [
        '/consumer/me',
        '/admin/me',
        '//evil.example/merchant/me',
        '/merchant/../admin/me',
        '/merchant/%2e%2e/admin/me',
        '/merchant/me?to=https://evil.example',
      ]) {
        await expectLater(
          client.request('GET', path),
          throwsA(isA<ApiFailure>()),
        );
      }
      expect(requests, before);
    },
  );
  test('concurrent 401 responses perform one refresh and replay with rotated token', () async {
    int refreshes = 0;
    final delayed = Completer<http.Response>();
    final client = api((r) async {
      if (r.url.path.endsWith('/login')) return ok(tokens('OLD'));
      if (r.url.path.endsWith('/me')) return ok(principal());
      if (r.url.path.endsWith('/refresh')) {
        refreshes++;
        return delayed.future;
      }
      return r.headers['Authorization'] == 'Bearer OLD'
          ? failure(401, 'AUTH_REQUIRED')
          : ok([]);
    });
    await client.login('TEST', 'TEST');
    final a = client.request('GET', '/merchant/offers'),
        b = client.request('GET', '/merchant/suborders');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshes, 1);
    delayed.complete(ok(tokens('NEW')));
    await Future.wait([a, b]);
    expect(refreshes, 1);
    expect(client.authenticated, true);
  });
  test('logout fences a delayed refresh from restoring a session', () async {
    final delayed = Completer<http.Response>();
    final client = api((r) async {
      if (r.url.path.endsWith('/refresh')) return delayed.future;
      return loginFixture(r);
    });
    await client.login('TEST', 'TEST');
    final pending = client.refresh();
    final checked = expectLater(
      pending,
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await client.clear();
    delayed.complete(ok(tokens('STALE')));
    await checked;
    expect(client.authenticated, false);
  });
  test('ambiguous command retry retains idempotency key but account change does not', () async {
    final keys = <String>[];
    bool fail = true;
    final client = api((r) async {
      if (r.url.path.endsWith('/inventory-adjustments')) {
        keys.add(r.headers['Idempotency-Key']!);
        if (fail) throw http.ClientException('TEST_ONLY connection lost');
        return ok({});
      }
      return loginFixture(r);
    });
    await client.login('TEST', 'TEST');
    final repo = MerchantRepository(client),
        body = {
          'delta_qty': 1,
          'reason_code': 'COUNT_CORRECTION',
          'expected_version': 0,
        };
    await expectLater(
      repo.command('/merchant/offers/TEST/inventory-adjustments', body),
      throwsA(isA<ApiFailure>()),
    );
    fail = false;
    await repo.command('/merchant/offers/TEST/inventory-adjustments', body);
    expect(keys[0], keys[1]);
    await client.login('OTHER_TEST', 'TEST');
    await repo.command('/merchant/offers/TEST/inventory-adjustments', body);
    expect(keys[2], isNot(keys[1]));
  });
  test(
    'wrong reverify password does not refresh or silently log out',
    () async {
      int refreshes = 0;
      final client = api((r) async {
        if (r.url.path.endsWith('/reverify')) {
          return failure(401, 'INVALID_CREDENTIALS');
        }
        if (r.url.path.endsWith('/refresh')) refreshes++;
        return loginFixture(r);
      });
      await client.login('TEST', 'TEST');
      await expectLater(
        MerchantRepository(client).revokeOthers('WRONG_TEST'),
        throwsA(isA<ApiFailure>()),
      );
      expect(refreshes, 0);
      expect(client.authenticated, true);
    },
  );
  test(
    'password reverify proof is used only for revoke others and never stored',
    () async {
      final vault = MemoryVault();
      String? proof;
      final client = api((r) async {
        if (r.url.path.endsWith('/reverify')) {
          expect(jsonDecode(r.body)['action'], 'session.revoke-others');
          return ok({'reverify_token': 'TEST_PROOF'});
        }
        if (r.url.path.endsWith('/revoke-others')) {
          proof = r.headers['X-Reverify-Token'];
        }
        return loginFixture(r);
      }, vault: vault);
      await client.login('TEST', 'TEST');
      await MerchantRepository(client).revokeOthers('TEST_PASSWORD');
      expect(proof, 'TEST_PROOF');
      expect(vault.values.toString().contains('TEST_PROOF'), false);
      expect(vault.values.toString().contains('TEST_PASSWORD'), false);
    },
  );
  test('removed store and permission cannot remain selected after identity refresh', () async {
    bool revoked = false;
    final client = api((r) async {
      if (r.url.path.endsWith('/me')) {
        return ok(
          principal(
            permissions: revoked
                ? ['store.read']
                : ['store.read', 'ledger.read', 'order.read'],
          ),
        );
      }
      if (r.url.path.endsWith('/stores')) {
        return ok(
          revoked
              ? []
              : [
                  {
                    'id': 'TEST_STORE',
                    'name': 'TEST store',
                    'merchant_id': 'TEST_MERCHANT',
                  },
                ],
        );
      }
      return loginFixture(r);
    });
    final session = MerchantSession(MerchantRepository(client));
    await session.login('TEST', 'TEST');
    session.selectStore('TEST_STORE');
    expect(session.can('ledger.read'), true);
    revoked = true;
    await session.refreshIdentity();
    expect(session.store, isNull);
    expect(session.stores, isEmpty);
    expect(session.can('ledger.read'), false);
    session.dispose();
  });
  test(
    'simulated client rejects unmarked server and non-loopback origin',
    () async {
      expect(
        () => MerchantApi(
          base: Uri.parse('https://external.example/api/v1'),
          transport: MockClient(loginFixture),
          vault: MemoryVault(),
          pilot: true,
        ),
        throwsArgumentError,
      );
      final client = api((r) async => http.Response('{}', 200), pilot: true);
      await expectLater(
        client.login('TEST', 'TEST'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'PILOT_ENVIRONMENT_MISMATCH',
          ),
        ),
      );
    },
  );
  test('Shanghai day and signed fen formatting do not depend on device timezone or floats', () {
    expect(
      dateText(shanghaiToday(DateTime.utc(2026, 10, 14, 16))),
      '2026-10-15',
    );
    expect(
      dateText(shanghaiToday(DateTime.utc(2026, 10, 14, 15, 59, 59))),
      '2026-10-14',
    );
    expect(money(-1), '¥-0.01');
    expect(money(9007199254740991), '¥90071992547409.91');
  });
}
