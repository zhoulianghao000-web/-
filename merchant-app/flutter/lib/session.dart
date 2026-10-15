import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'merchant_repository.dart';

String safeReturnTo(String? value) =>
    const ['/dashboard', '/orders', '/offers', '/account'].contains(value)
    ? value!
    : '/dashboard';

class MerchantSession extends ChangeNotifier {
  final MerchantRepository repository;
  Principal? principal;
  List<Store> stores = [];
  String? store;
  bool ready = false;
  String error = '';
  int revision = 0;
  Timer? _timer;
  bool _checking = false;
  bool _disposed = false;
  MerchantSession(this.repository) {
    repository.api.expired.addListener(_expired);
  }
  bool can(String permission) =>
      principal?.permissions.contains(permission) ?? false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _expired() {
    if (repository.api.expired.value) {
      principal = null;
      stores = [];
      store = null;
      revision++;
      _notify();
    }
  }

  Future<void> init() async {
    try {
      principal = await repository.api.restore();
      if (principal != null) await refreshIdentity();
    } catch (e) {
      error = explain(e);
    } finally {
      ready = true;
      _notify();
    }
    _timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (principal == null || _checking) return;
      _checking = true;
      try {
        await refreshIdentity();
      } catch (_) {
        stores = [];
        store = null;
        revision++;
        _notify();
      } finally {
        _checking = false;
      }
    });
  }

  Future<void> login(String name, String password) async {
    principal = await repository.api.login(name, password);
    try {
      await refreshIdentity();
      error = '';
      _notify();
    } catch (_) {
      await repository.api.clear();
      rethrow;
    }
  }

  Future<void> refreshIdentity() async {
    final epoch = repository.api.generation, p = await repository.api.me();
    final next = p.permissions.contains('store.read')
        ? await repository.stores()
        : <Store>[];
    if (epoch != repository.api.generation) {
      throw const ApiFailure(401, 'SESSION_CHANGED');
    }
    if (next.any((s) => s.merchant_id != p.merchant_id)) {
      await repository.api.clear();
      throw const ApiFailure(403, 'STORE_SCOPE_MISMATCH');
    }
    final changed =
        principal?.session_id != p.session_id ||
        principal?.permissions.join(',') != p.permissions.join(',') ||
        stores.map((s) => s.id).join(',') != next.map((s) => s.id).join(',');
    principal = p;
    stores = next;
    if (store != null && !next.any((s) => s.id == store)) store = null;
    if (changed) {
      revision++;
      _notify();
    }
  }

  void selectStore(String? id) {
    if (id != null && !stores.any((s) => s.id == id)) {
      throw const ApiFailure(403, 'STORE_SCOPE_MISMATCH');
    }
    if (store != id) {
      store = id;
      revision++;
      _notify();
    }
  }

  Future<void> logout() async {
    final revoke = repository.api.logout();
    await repository.api.clear();
    principal = null;
    stores = [];
    store = null;
    revision++;
    _notify();
    try {
      await revoke;
    } catch (_) {
      /* Local session stays cleared if offline. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    repository.api.expired.removeListener(_expired);
    super.dispose();
  }
}

String explain(Object e) {
  if (e is ApiFailure) {
    final text = e.status == 409
        ? '资料版本已变更或环境不匹配，请刷新后重新确认。'
        : e.status == 403
        ? '当前账号无此权限，请联系商家管理员。'
        : e.status == 404
        ? '资料已不可访问，请刷新授权范围。'
        : e.status == 401
        ? '登录状态失效或验证未通过，请重新登录。'
        : e.status == 0
        ? '无法连接本地服务，请检查USB连接和服务状态。'
        : '请求失败（${e.code}）';
    return '$text${e.requestId.isEmpty ? '' : ' 请求编号：${e.requestId}'}';
  }
  return '操作未完成，请重试。';
}
