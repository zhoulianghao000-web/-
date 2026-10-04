import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/router.dart';

const tokens = Tokens(
  access_token: 'old-access',
  refresh_token: 'refresh',
  expires_in: 900,
  session_id: 'session',
  user_id: 'user',
);
const principal = Principal(
  id: 'user',
  realm: 'CONSUMER',
  user_id: 'user',
  merchant_id: null,
  session_id: 'session',
  permissions: [],
);
const meta = {
  'request_id': 'request-test',
  'correlation_id': 'correlation-test',
};
http.Response ok(Object? data) => http.Response(
  jsonEncode({'data': data, 'meta': meta}),
  200,
  headers: {'Content-Type': 'application/json'},
);
http.Response fail(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': code, 'retryable': false, 'details': {}},
    'meta': meta,
  }),
  status,
);
ConsumerApi apiWith(
  Future<http.Response> Function(http.Request) handler, {
  SessionVault? vault,
}) => ConsumerApi(
  base: Uri.parse('http://localhost/api/v1'),
  transport: MockClient(handler),
  vault: vault ?? MemoryVault(),
);

class SlowVault extends MemoryVault {
  final started = Completer<void>(), resume = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (key == 'consumer.session') {
      started.complete();
      await resume.future;
    }
    await super.write(key, value);
  }
}

class FailingVault extends MemoryVault {
  @override
  Future<void> write(String key, String value) async {
    if (key == 'consumer.session') {
      throw StateError('Secure storage unavailable');
    }
    await super.write(key, value);
  }
}

void main() {
  test('logout is ordered after an in-flight secure storage write', () async {
    final vault = SlowVault();
    final api = apiWith((_) async => ok({}), vault: vault);
    final pending = api.accept(tokens);
    final assertion = expectLater(pending, throwsA(isA<ApiFailure>()));
    await vault.started.future;
    final clearing = api.clear();
    vault.resume.complete();
    await Future.wait([assertion, clearing]);
    expect(api.authenticated, false);
    expect(vault.values['consumer.session'], isNull);
    api.dispose();
  });
  test(
    'secure storage failure cannot leave a partially accepted login',
    () async {
      final api = apiWith((_) async => ok({}), vault: FailingVault());
      await expectLater(api.accept(tokens), throwsA(isA<StateError>()));
      expect(api.authenticated, false);
      api.dispose();
    },
  );
  test('generated required nullable fields survive a JSON round trip', () {
    const value = Tokens(
      access_token: 'a',
      refresh_token: 'r',
      expires_in: 900,
      session_id: 's',
      user_id: null,
    );
    expect(value.toJson().containsKey('user_id'), true);
    expect(Tokens.fromJson(value.toJson()).user_id, isNull);
  });
  test('foreign realm is rejected before any HTTP request', () async {
    var calls = 0;
    final api = apiWith((_) async {
      calls++;
      return ok({});
    });
    await expectLater(
      api.request('GET', '/admin/me'),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'REALM_MISMATCH'),
      ),
    );
    expect(calls, 0);
    api.dispose();
  });
  test(
    'OTP request uses the generated contract and never sends a bearer',
    () async {
      final api = apiWith((request) async {
        expect(request.headers['Authorization'], isNull);
        expect(request.headers['X-Request-ID'], isNotEmpty);
        expect(jsonDecode(request.body), {
          'phone_e164': '+8613800000000',
          'purpose': 'LOGIN',
        });
        return ok({});
      });
      await api.accept(tokens);
      await api.requestCode('+8613800000000');
      api.dispose();
    },
  );
  test(
    'simultaneous GET failures refresh once and rotate authorization',
    () async {
      var refreshes = 0;
      final api = apiWith((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return ok({...tokens.toJson(), 'access_token': 'new-access'});
        }
        return request.headers['Authorization'] == 'Bearer old-access'
            ? fail(401, 'SESSION_EXPIRED')
            : ok(principal.toJson());
      });
      await api.accept(tokens);
      await Future.wait([api.me(), api.me()]);
      expect(refreshes, 1);
      api.dispose();
    },
  );
  test(
    'late refresh cannot revive logout or persist rotated credentials',
    () async {
      final response = Completer<http.Response>();
      final vault = MemoryVault();
      final api = apiWith((_) => response.future, vault: vault);
      await api.accept(tokens);
      final pending = api.refresh();
      final assertion = expectLater(pending, throwsA(isA<ApiFailure>()));
      await api.clear();
      response.complete(ok(tokens.toJson()));
      await assertion;
      expect(api.authenticated, false);
      expect(vault.values['consumer.session'], isNull);
      api.dispose();
    },
  );
  test('late successful me cannot restore a principal after logout', () async {
    final response = Completer<http.Response>();
    final api = apiWith((_) => response.future);
    await api.accept(tokens);
    final pending = api.me();
    final assertion = expectLater(
      pending,
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await api.clear();
    response.complete(ok(principal.toJson()));
    await assertion;
    api.dispose();
  });
  test('non-idempotent POST is never replayed after 401', () async {
    var calls = 0;
    final api = apiWith((_) async {
      calls++;
      return fail(401, 'SESSION_EXPIRED');
    });
    await api.accept(tokens);
    await expectLater(
      api.request('POST', '/consumer/auth/reverify', body: {}),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 1);
    expect(api.authenticated, false);
    api.dispose();
  });
  test(
    'version conflict keeps the request ID and never silently retries',
    () async {
      var calls = 0;
      final api = apiWith((_) async {
        calls++;
        return fail(409, 'VERSION_CONFLICT');
      });
      await expectLater(
        api.request(
          'POST',
          '/consumer/future',
          body: {'version': 4},
          idempotencyKey: 'stable',
        ),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.versionConflict, 'conflict', true)
              .having((e) => e.requestId, 'request', 'request-test'),
        ),
      );
      expect(calls, 1);
      api.dispose();
    },
  );
  test('native session restores only against the same API origin and consumer realm', () async {
    final vault = MemoryVault();
    final first = apiWith((_) async => ok(principal.toJson()), vault: vault);
    await first.accept(tokens);
    first.dispose();
    final second = apiWith((_) async => ok(principal.toJson()), vault: vault);
    await second.restore();
    expect(second.authenticated, true);
    second.dispose();
    vault.values['consumer.session'] = jsonEncode({
      'realm': 'ADMIN',
      'api': 'http://localhost/api/v1',
      'tokens': tokens.toJson(),
    });
    final third = apiWith((_) async => ok(principal.toJson()), vault: vault);
    await expectLater(third.restore(), throwsA(isA<ApiFailure>()));
    expect(vault.values['consumer.session'], isNull);
    third.dispose();
  });
  test('revoked refresh clears native credentials', () async {
    final vault = MemoryVault();
    final api = apiWith(
      (_) async => fail(401, 'REFRESH_REVOKED'),
      vault: vault,
    );
    await api.accept(tokens);
    await expectLater(api.me(), throwsA(isA<ApiFailure>()));
    expect(api.authenticated, false);
    expect(vault.values['consumer.session'], isNull);
    api.dispose();
  });
  test(
    'network and malformed responses produce errors, never fabricated data',
    () async {
      final offline = apiWith(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        offline.me(),
        throwsA(
          isA<ApiFailure>().having((e) => e.retryable, 'retryable', true),
        ),
      );
      offline.dispose();
      final malformed = apiWith((_) async => http.Response('broken', 200));
      await expectLater(
        malformed.me(),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'INVALID_API_RESPONSE',
          ),
        ),
      );
      malformed.dispose();
    },
  );
  for (final value in [
    'https://bad.test',
    '//bad.test',
    '/%2f%2fbad',
    '/auth/login',
    '/unknown',
    '/%ZZ',
    '/\\bad',
  ]) {
    test(
      'unsafe returnTo is rejected: $value',
      () => expect(safeReturnTo(value), '/home'),
    );
  }
  test(
    'internal returnTo retains intent and query',
    () => expect(safeReturnTo('/pets?from=home'), '/pets?from=home'),
  );
}
