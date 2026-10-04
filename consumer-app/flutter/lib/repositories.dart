import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api/client.dart';
import 'api/generated/dto.dart';

final consumerApiProvider = Provider<ConsumerApi>((ref) {
  const configured = String.fromEnvironment(
    'PAWDAY_API_BASE',
    defaultValue: 'http://127.0.0.1:8080/api/v1',
  );
  final api = ConsumerApi(
    base: Uri.parse(configured),
    transport: http.Client(),
    vault: kIsWeb ? MemoryVault() : PlatformVault(),
  );
  ref.onDispose(api.dispose);
  return api;
});

class ConsumerRepository {
  final ConsumerApi api;
  ConsumerRepository(this.api);
  Future<Principal?> restore() => api.restore();

  Future<void> requestCode(String phone) => api.requestCode(phone);
  Future<Principal> login(String phone, String code) => api.login(phone, code);
  Future<void> logout() => api.logout();
  Future<List<Session>> sessions() => api.sessions();
}

final consumerRepositoryProvider = Provider(
  (ref) => ConsumerRepository(ref.watch(consumerApiProvider)),
);

class AuthState {
  final Principal? principal;
  final bool restoring;
  final String? error;
  const AuthState({this.principal, this.restoring = false, this.error});
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  int _generation = 0;
  @override
  AuthState build() {
    final api = ref.read(consumerApiProvider);
    void expired() {
      if (api.expired.value) {
        _generation++;
        state = const AuthState();
      }
    }

    api.expired.addListener(expired);
    ref.onDispose(() => api.expired.removeListener(expired));
    return const AuthState(restoring: true);
  }

  Future<void> restore() async {
    final generation = ++_generation;
    try {
      final principal = await ref.read(consumerRepositoryProvider).restore();
      if (generation == _generation) state = AuthState(principal: principal);
    } catch (_) {
      if (generation == _generation) {
        state = const AuthState(error: '会话恢复失败，请重新登录。');
      }
    }
  }

  Future<void> login(String phone, String code) async {
    final generation = ++_generation;
    final principal = await ref
        .read(consumerRepositoryProvider)
        .login(phone, code);
    if (generation != _generation) {
      throw const ApiFailure(401, 'SESSION_CHANGED');
    }
    state = AuthState(principal: principal);
  }

  Future<void> logout() async {
    ++_generation;
    state = const AuthState();
    try {
      await ref.read(consumerRepositoryProvider).logout();
    } finally {
      state = const AuthState();
    }
  }
}

class PetContext {
  final String id, ownerUserId, name;
  const PetContext({
    required this.id,
    required this.ownerUserId,
    required this.name,
  });
}

final currentPetProvider = NotifierProvider<CurrentPetNotifier, PetContext?>(
  CurrentPetNotifier.new,
);

class CurrentPetNotifier extends Notifier<PetContext?> {
  @override
  PetContext? build() {
    ref.listen(authProvider, (previous, next) {
      if (previous?.principal?.user_id != next.principal?.user_id) state = null;
    });
    return null;
  }

  void select(PetContext pet, List<PetContext> serverOwnedPets) {
    final userId = ref.read(authProvider).principal?.user_id;
    if (userId == null ||
        pet.ownerUserId != userId ||
        !serverOwnedPets.any(
          (p) => p.id == pet.id && p.ownerUserId == userId,
        )) {
      throw const ApiFailure(403, 'PET_SCOPE_MISMATCH');
    }
    state = serverOwnedPets.firstWhere(
      (p) => p.id == pet.id && p.ownerUserId == userId,
    );
  }
}
