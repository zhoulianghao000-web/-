import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'generated/dto.dart';

const pilotMode = bool.fromEnvironment('PAWDAY_PILOT');

abstract interface class SessionVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryVault implements SessionVault {
  final values = <String, String>{};
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
  final storage = const FlutterSecureStorage();
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
  const ApiFailure(this.status, this.code, {this.requestId = ''});
  @override
  String toString() => '$code${requestId.isEmpty ? '' : ' · 请求编号 $requestId'}';
}

class MerchantApi {
  final Uri base;
  final http.Client transport;
  final SessionVault vault;
  final bool pilot;
  Tokens? _tokens;
  int _epoch = 0;
  Future<void>? _refreshing;
  Future<void> _vaultFlight = Future.value();
  final expired = ValueNotifier(false);
  MerchantApi({
    required this.base,
    required this.transport,
    required this.vault,
    this.pilot = pilotMode,
  }) {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.path != '/api/v1' ||
        base.hasQuery ||
        base.hasFragment ||
        (kReleaseMode && base.scheme != 'https') ||
        (pilot && (base.scheme != 'http' || base.host != '127.0.0.1'))) {
      throw ArgumentError('Invalid API origin');
    }
  }
  bool get authenticated => _tokens != null;
  int get generation => _epoch;
  Future<void> _persist(Future<void> Function() op) {
    final f = _vaultFlight.then((_) => op());
    _vaultFlight = f.catchError((Object _) {});
    return f;
  }

  Future<void> _save() {
    final value = _tokens, epoch = _epoch;
    return _persist(() async {
      if (epoch == _epoch && value != null) {
        await vault.write(
          'merchant.session',
          jsonEncode({
            'realm': 'MERCHANT',
            'api': base.toString(),
            'tokens': value.toJson(),
          }),
        );
      }
    });
  }

  Future<void> clear() async {
    _epoch++;
    _tokens = null;
    expired.value = true;
    await _persist(() => vault.delete('merchant.session'));
  }

  Uri _url(String path, Map<String, String>? query) {
    if (!RegExp(r'^/merchant/[a-zA-Z0-9_/-]+$').hasMatch(path) ||
        path.contains('..') ||
        path.contains('//')) {
      throw const ApiFailure(403, 'INVALID_API_DESTINATION');
    }
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    bool auth = true,
    bool retry = true,
  }) async {
    final url = _url(path, query),
        epoch = _epoch,
        access = _tokens?.access_token;
    if (auth && _tokens == null) throw const ApiFailure(401, 'AUTH_REQUIRED');
    http.Response response;
    try {
      final req = http.Request(method, url)
        ..followRedirects = false
        ..headers.addAll({
          'X-Request-ID': const Uuid().v4(),
          if (pilot) 'X-Pawday-Pilot': 'simulated-v1',
          if (auth) 'Authorization': 'Bearer ${_tokens?.access_token}',
          if (body != null) 'Content-Type': 'application/json',
          ...headers,
        })
        ..body = body == null ? '' : jsonEncode(body);
      response = await transport
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      throw const ApiFailure(0, 'NETWORK_UNAVAILABLE');
    }
    if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    if (pilot &&
        response.headers['x-pawday-environment'] != 'SIMULATED_PILOT') {
      throw const ApiFailure(409, 'PILOT_ENVIRONMENT_MISMATCH');
    }
    if (response.statusCode == 401 &&
        auth &&
        retry &&
        !path.endsWith('/auth/reverify')) {
      if (access == _tokens?.access_token) await refresh();
      if (epoch != _epoch || _tokens == null) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
      return request(
        method,
        path,
        body: body,
        query: query,
        headers: headers,
        auth: auth,
        retry: false,
      );
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw ApiFailure(response.statusCode, 'INVALID_RESPONSE');
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 &&
          auth &&
          !path.endsWith('/auth/reverify')) {
        await clear();
      }
      throw ApiFailure(
        response.statusCode,
        (data['error'] as Map?)?['code']?.toString() ?? 'HTTP_ERROR',
        requestId: (data['meta'] as Map?)?['request_id']?.toString() ?? '',
      );
    }
    return data;
  }

  Future<Principal> me() async {
    final p = Principal.fromJson(
      Map<String, dynamic>.from(
        (await request('GET', '/merchant/me'))['data'] as Map,
      ),
    );
    if (p.realm != 'MERCHANT' || p.merchant_id == null) {
      await clear();
      throw const ApiFailure(403, 'REALM_MISMATCH');
    }
    return p;
  }

  Future<Principal> login(String name, String password) async {
    await clear();
    final epoch = _epoch;
    String? device = await vault.read('merchant.device');
    device ??= const Uuid().v4();
    await vault.write('merchant.device', device);
    final data = await request(
      'POST',
      '/merchant/auth/login',
      auth: false,
      body: {'login_name': name, 'password': password, 'device_id': device},
    );
    if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    _tokens = Tokens.fromJson(Map<String, dynamic>.from(data['data'] as Map));
    try {
      final p = await me();
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      await _save();
      expired.value = false;
      return p;
    } catch (_) {
      if (epoch == _epoch) await clear();
      rethrow;
    }
  }

  Future<Principal?> restore() async {
    final epoch = _epoch, raw = await vault.read('merchant.session');
    if (epoch != _epoch || raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map;
      if (data['realm'] != 'MERCHANT' || data['api'] != base.toString()) {
        throw const ApiFailure(403, 'REALM_MISMATCH');
      }
      _tokens = Tokens.fromJson(
        Map<String, dynamic>.from(data['tokens'] as Map),
      );
      final p = await me();
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      expired.value = false;
      return p;
    } catch (_) {
      if (epoch == _epoch) await clear();
      rethrow;
    }
  }

  Future<void> refresh() =>
      _refreshing ??= _rotate().whenComplete(() => _refreshing = null);
  Future<void> _rotate() async {
    final epoch = _epoch, token = _tokens?.refresh_token;
    if (token == null) throw const ApiFailure(401, 'AUTH_REQUIRED');
    try {
      final data = await request(
        'POST',
        '/merchant/auth/refresh',
        auth: false,
        body: {'refresh_token': token},
      );
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      _tokens = Tokens.fromJson(Map<String, dynamic>.from(data['data'] as Map));
      await _save();
    } catch (e) {
      if (epoch == _epoch && (e is ApiFailure && e.status == 401)) {
        await clear();
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final epoch = _epoch;
    try {
      if (authenticated) {
        await request(
          'POST',
          '/merchant/auth/logout',
          body: <String, dynamic>{},
        );
      }
    } finally {
      if (epoch == _epoch) await clear();
    }
  }
}
