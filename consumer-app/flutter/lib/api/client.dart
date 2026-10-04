import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'generated/dto.dart';

abstract interface class SessionVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryVault implements SessionVault {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class PlatformVault implements SessionVault {
  final FlutterSecureStorage storage;
  PlatformVault([this.storage = const FlutterSecureStorage()]);
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class ApiFailure implements Exception {
  final int status;
  final String code, requestId;
  final bool retryable;
  const ApiFailure(
    this.status,
    this.code, {
    this.requestId = '',
    this.retryable = false,
  });
  bool get versionConflict => status == 409;
  @override
  String toString() => '$code${requestId.isEmpty ? '' : ' · 请求编号 $requestId'}';
}

class ConsumerApi {
  final Uri base;
  final http.Client transport;
  final SessionVault vault;
  Tokens? _tokens;
  int _epoch = 0;
  Future<void>? _refreshing;
  Future<void> _vaultFlight = Future.value();
  final ValueNotifier<bool> expired = ValueNotifier(false);
  ConsumerApi({
    required this.base,
    required this.transport,
    required this.vault,
  }) {
    if (kReleaseMode && base.scheme != 'https') {
      throw ArgumentError('Release API must use HTTPS');
    }
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid API origin');
    }
  }
  bool get authenticated => _tokens != null;
  Future<void> _persist(Future<void> Function() operation) {
    final future = _vaultFlight.then((_) => operation());
    _vaultFlight = future.catchError((Object _) {});
    return future;
  }

  Future<void> _save() {
    final tokens = _tokens;
    final epoch = _epoch;
    return _persist(() async {
      if (tokens != null && epoch == _epoch) {
        await vault.write(
          'consumer.session',
          jsonEncode({
            'realm': 'CONSUMER',
            'api': base.toString(),
            'tokens': tokens.toJson(),
          }),
        );
      }
    });
  }

  Future<void> clear() async {
    _epoch++;
    _tokens = null;
    expired.value = true;
    await _persist(() => vault.delete('consumer.session'));
  }

  Future<void> restore() async {
    final epoch = _epoch;
    final raw = await vault.read('consumer.session');
    if (epoch != _epoch || raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['realm'] != 'CONSUMER' || data['api'] != base.toString()) {
        throw const ApiFailure(403, 'REALM_MISMATCH');
      }
      _tokens = Tokens.fromJson(
        Map<String, dynamic>.from(data['tokens'] as Map),
      );
      await me();
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      expired.value = false;
    } catch (_) {
      if (epoch == _epoch) await clear();
      rethrow;
    }
  }

  Future<String> deviceId() async {
    var value = await vault.read('consumer.device');
    if (value == null) {
      value = const Uuid().v4();
      await vault.write('consumer.device', value);
    }
    return value;
  }

  Future<void> accept(Tokens tokens) async {
    _epoch++;
    _tokens = tokens;
    expired.value = false;
    await _save();
  }

  Uri _url(String path) {
    if (!path.startsWith('/consumer/') ||
        path.contains('..') ||
        path.contains('\\')) {
      throw const ApiFailure(403, 'REALM_MISMATCH');
    }
    return Uri.parse('${base.toString().replaceFirst(RegExp(r'/$'), '')}$path');
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool anonymous = false,
    String? idempotencyKey,
  }) async {
    final epoch = _epoch, access = _tokens?.access_token;
    Future<http.Response> send() async {
      final request = http.Request(method, _url(path));
      request.headers['X-Request-ID'] = const Uuid().v4();
      if (!anonymous && _tokens != null) {
        request.headers['Authorization'] = 'Bearer ${_tokens!.access_token}';
      }
      if (idempotencyKey != null) {
        request.headers['Idempotency-Key'] = idempotencyKey;
      }
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      try {
        return await http.Response.fromStream(
          await transport.send(request).timeout(const Duration(seconds: 10)),
        ).timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw const ApiFailure(0, 'NETWORK_TIMEOUT', retryable: true);
      } on http.ClientException {
        throw const ApiFailure(0, 'NETWORK_UNAVAILABLE', retryable: true);
      }
    }

    var response = await send();
    if (!anonymous && epoch != _epoch) {
      throw const ApiFailure(401, 'SESSION_CHANGED');
    }
    if (response.statusCode == 401 &&
        !anonymous &&
        _tokens != null &&
        (method == 'GET' || idempotencyKey != null)) {
      if (epoch == _epoch && access == _tokens?.access_token) await refresh();
      if (_tokens != null) response = await send();
      if (epoch != _epoch) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && !anonymous && epoch == _epoch) {
        await clear();
      }
      throw _error(response);
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ApiFailure(502, 'INVALID_API_RESPONSE');
    }
  }

  ApiFailure _error(http.Response response) {
    try {
      final value = ErrorEnvelope.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      return ApiFailure(
        response.statusCode,
        value.error['code'] as String,
        requestId: value.meta.request_id,
        retryable: value.error['retryable'] as bool,
      );
    } catch (_) {
      return ApiFailure(
        response.statusCode,
        'HTTP_ERROR',
        requestId: response.headers['x-request-id'] ?? '',
      );
    }
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final epoch = _epoch, token = _tokens?.refresh_token;
    if (token == null) {
      return Future.error(const ApiFailure(401, 'SESSION_EXPIRED'));
    }
    final future = () async {
      try {
        final value = TokensEnvelope.fromJson(
          await request(
            'POST',
            ApiRoutes.post_consumer_auth_refresh,
            anonymous: true,
            body: Refresh(refresh_token: token).toJson(),
          ),
        );
        if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
        _tokens = value.data;
        await _save();
      } catch (_) {
        if (epoch == _epoch) await clear();
        rethrow;
      } finally {
        _refreshing = null;
      }
    }();
    _refreshing = future;
    return future;
  }

  Future<Principal> me() async {
    final epoch = _epoch;
    final principal = PrincipalEnvelope.fromJson(
      await request('GET', ApiRoutes.get_consumer_me),
    ).data;
    if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    if (principal.realm != 'CONSUMER') {
      await clear();
      throw const ApiFailure(403, 'REALM_MISMATCH');
    }
    return principal;
  }

  Future<void> requestCode(String phone) async {
    await request(
      'POST',
      ApiRoutes.post_consumer_auth_phone_request_code,
      anonymous: true,
      body: CodeRequest(phone_e164: phone, purpose: 'LOGIN').toJson(),
    );
  }

  Future<Principal> login(String phone, String code) async {
    final epoch = _epoch;
    final result = TokensEnvelope.fromJson(
      await request(
        'POST',
        ApiRoutes.post_consumer_auth_phone_verify,
        anonymous: true,
        body: PhoneLogin(
          phone_e164: phone,
          code: code,
          device_id: await deviceId(),
        ).toJson(),
      ),
    );
    if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    await accept(result.data);
    final acceptedEpoch = _epoch;
    try {
      final principal = await me();
      if (acceptedEpoch != _epoch) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
      return principal;
    } catch (_) {
      if (acceptedEpoch == _epoch) await clear();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await request('POST', ApiRoutes.post_consumer_auth_logout);
    } finally {
      await clear();
    }
  }

  Future<List<Session>> sessions() async => SessionList.fromJson(
    await request('GET', ApiRoutes.get_consumer_auth_sessions),
  ).data;
  void dispose() {
    transport.close();
    expired.dispose();
  }
}
