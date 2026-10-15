import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';

DateTime shanghaiToday([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime.utc(utc.year, utc.month, utc.day);
}

String dateText(DateTime date) => date.toIso8601String().substring(0, 10);
String money(int fen) =>
    '¥${fen < 0 ? '-' : ''}${fen.abs() ~/ 100}.${(fen.abs() % 100).toString().padLeft(2, '0')}';

class MerchantRepository {
  final MerchantApi api;
  final _keys = <String, String>{};
  MerchantRepository(this.api);
  Future<List<Store>> stores() async =>
      ((await api.request('GET', '/merchant/stores'))['data'] as List)
          .map((x) => Store.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
  Future<BusinessAnalytics> analytics(
    String from,
    String to,
    String? store,
  ) async => BusinessAnalytics.fromJson(
    Map<String, dynamic>.from(
      (await api.request(
            'GET',
            '/merchant/business-analytics',
            query: {'from': from, 'to': to, 'store_id': ?store},
          ))['data']
          as Map,
    ),
  );
  Future<Map<String, dynamic>> list(
    String path, {
    String? store,
    String? cursor,
  }) => api.request(
    'GET',
    path,
    query: {'limit': '20', 'store_id': ?store, 'cursor': ?cursor},
  );
  Future<Map<String, dynamic>> get(String path) async =>
      Map<String, dynamic>.from(
        (await api.request('GET', path))['data'] as Map,
      );
  Future<void> command(
    String path,
    Map<String, dynamic> body, {
    int? version,
    String? proof,
  }) async {
    final identity = '${api.generation}:$path:${jsonEncode(body)}:$version',
        key = _keys.putIfAbsent(
          '${api.generation}:$path:${jsonEncode(body)}:$version',
          () => const Uuid().v4(),
        );
    await api.request(
      'POST',
      path,
      body: body,
      headers: {
        'Idempotency-Key': key,
        if (version != null) 'If-Match': '"$version"',
        'X-Reverify-Token': ?proof,
      },
    );
    _keys.remove(identity);
  }

  Future<void> revokeOthers(String password) async {
    final epoch = api.generation;
    final data = await api.request(
      'POST',
      '/merchant/auth/reverify',
      body: {'action': 'session.revoke-others', 'password': password},
    );
    if (epoch != api.generation) throw const ApiFailure(401, 'SESSION_CHANGED');
    await command(
      '/merchant/auth/sessions/revoke-others',
      {},
      proof: (data['data'] as Map)['reverify_token'] as String,
    );
  }
}
