import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  ({Uri uri, Map<String, String> headers}) mediaSource(
    String path, {
    bool anonymous = false,
  }) {
    if (!RegExp(
      r'^/api/v1/(public|consumer)/(reviews|content)/[0-9a-f-]{36}/media/[0-9a-f-]{36}$',
    ).hasMatch(path)) {
      throw const ApiFailure(403, 'INVALID_API_DESTINATION');
    }
    return (
      uri: _url(path.substring('/api/v1'.length)),
      headers: {
        if (!anonymous && _tokens != null)
          'Authorization': 'Bearer ${_tokens!.access_token}',
      },
    );
  }

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

  Future<Principal?> restore() async {
    final epoch = _epoch;
    final raw = await vault.read('consumer.session');
    if (epoch != _epoch || raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['realm'] != 'CONSUMER' || data['api'] != base.toString()) {
        throw const ApiFailure(403, 'REALM_MISMATCH');
      }
      _tokens = Tokens.fromJson(
        Map<String, dynamic>.from(data['tokens'] as Map),
      );
      final principal = await me();
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      expired.value = false;
      return principal;
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
    final epoch = _epoch;
    _tokens = tokens;
    expired.value = false;
    try {
      await _save();
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    } catch (_) {
      if (epoch == _epoch) await clear();
      rethrow;
    }
  }

  Uri _url(String path) {
    final route = Uri.parse(path).path;
    final publicTaxonomy =
        path == '/public/pet-taxonomy' ||
        path == '/public/allergens' ||
        RegExp(r'^/public/pet-species/[0-9a-f-]{36}/breeds$').hasMatch(path) ||
        route == '/public/products' ||
        route == '/public/content' ||
        RegExp(r'^/public/content/[0-9a-f-]{36}(/media/[0-9a-f-]{36})?$')
            .hasMatch(route) ||
        RegExp(r'^/public/reviews/[0-9a-f-]{36}(/media/[0-9a-f-]{36})?$')
            .hasMatch(route) ||
        RegExp(r'^/public/spus/[0-9a-f-]{36}/reviews$').hasMatch(route) ||
        RegExp(r'^/public/(skus|spus)/[0-9a-f-]{36}(/offers)?$')
            .hasMatch(route);
    if ((!path.startsWith('/consumer/') &&
            !publicTaxonomy &&
            route != '/media/upload-grants' &&
            !RegExp(r'^/media/[0-9a-f-]{36}/content$').hasMatch(route)) ||
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
    int? version,
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
      if (version != null) request.headers['If-Match'] = '"$version"';
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

  Uri publicMediaUri(String path) {
    if (!RegExp(
      r'^/api/v1/public/(reviews|content)/[0-9a-f-]{36}/media/[0-9a-f-]{36}$',
    ).hasMatch(path)) {
      throw const ApiFailure(403, 'INVALID_API_DESTINATION');
    }
    return _url(path.substring('/api/v1'.length));
  }

  Future<MediaAsset> uploadReview(
    Uint8List bytes,
    String mime,
    String sha256,
  ) async {
    final epoch = _epoch;
    if (bytes.isEmpty || bytes.length > 5242880) {
      throw const ApiFailure(413, 'UPLOAD_TOO_LARGE');
    }
    if (!['image/png', 'image/jpeg', 'video/mp4'].contains(mime)) {
      throw const ApiFailure(400, 'UPLOAD_MIME_NOT_ALLOWED');
    }
    final grant = MediaGrantEnvelope.fromJson(
      await request(
        'POST',
        '/media/upload-grants',
        body: MediaGrantRequest(
          scope: 'REVIEW',
          mime: mime,
          size_bytes: bytes.length,
          sha256: sha256,
        ).toJson(),
      ),
    ).data;
    if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
    final upload = http.Request(
      'PUT',
      _url('/media/${grant.asset_id}/content'),
    );
    upload.headers.addAll({
      'Authorization': 'Bearer ${_tokens?.access_token ?? ''}',
      'Content-Type': mime,
      'X-Upload-Token': grant.upload_token,
      'X-Request-ID': const Uuid().v4(),
    });
    upload.bodyBytes = bytes;
    try {
      final response = await http.Response.fromStream(
        await transport.send(upload).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      if (epoch != _epoch) throw const ApiFailure(401, 'SESSION_CHANGED');
      if (response.statusCode != 200) throw _error(response);
      return MediaAssetEnvelope.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ).data;
    } on TimeoutException {
      throw const ApiFailure(0, 'NETWORK_TIMEOUT', retryable: true);
    } on http.ClientException {
      throw const ApiFailure(0, 'NETWORK_UNAVAILABLE', retryable: true);
    }
  }

  Future<Uint8List> mediaBytes(String path, {bool anonymous = false}) async {
    if (!RegExp(
      r'^/api/v1/(public|consumer)/(reviews|content)/[0-9a-f-]{36}/media/[0-9a-f-]{36}$',
    ).hasMatch(path)) {
      throw const ApiFailure(403, 'INVALID_API_DESTINATION');
    }
    final epoch = _epoch;
    Future<http.StreamedResponse> send() {
      final req = http.Request('GET', _url(path.substring('/api/v1'.length)));
      req.headers['X-Request-ID'] = const Uuid().v4();
      if (!anonymous && _tokens != null) {
        req.headers['Authorization'] = 'Bearer ${_tokens!.access_token}';
      }
      return transport.send(req).timeout(const Duration(seconds: 10));
    }

    try {
      var response = await send();
      if (!anonymous && epoch != _epoch) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
      if (response.statusCode == 401 && !anonymous && _tokens != null) {
        await response.stream.drain<void>();
        await refresh();
        response = await send();
      }
      if (response.statusCode != 200) {
        throw _error(await http.Response.fromStream(response));
      }
      if (![
        'image/png',
        'image/jpeg',
        'video/mp4',
      ].contains(response.headers['content-type']?.split(';').first)) {
        await response.stream.drain<void>();
        throw const ApiFailure(502, 'INVALID_MEDIA_RESPONSE');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        if (builder.length + chunk.length > 5242880) {
          throw const ApiFailure(413, 'UPLOAD_TOO_LARGE');
        }
        builder.add(chunk);
      }
      if (!anonymous && epoch != _epoch) {
        throw const ApiFailure(401, 'SESSION_CHANGED');
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw const ApiFailure(0, 'NETWORK_TIMEOUT', retryable: true);
    } on http.ClientException {
      throw const ApiFailure(0, 'NETWORK_UNAVAILABLE', retryable: true);
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
    final acceptedEpoch = epoch + 1;
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
