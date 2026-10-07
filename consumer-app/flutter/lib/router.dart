import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'repositories.dart';
import 'screens.dart';
import 'checkout_screen.dart';
import 'membership_screen.dart';
import 'order_screen.dart';
import 'payment_screen.dart';
import 'points_screen.dart';

String safeReturnTo(String? value) {
  const allowed = [
    '/home',
    '/categories',
    '/pets',
    '/nearby',
    '/me',
    '/sessions',
    '/cart',
    '/orders',
    '/payments',
    '/membership',
    '/points',
  ];
  if (value == null ||
      !value.startsWith('/') ||
      value.startsWith('//') ||
      value.contains('\\')) {
    return '/home';
  }
  try {
    final uri = Uri.parse(value);
    final decoded = Uri.decodeComponent(value);
    if (uri.hasScheme ||
        uri.hasAuthority ||
        decoded.startsWith('//') ||
        decoded.contains('\\') ||
        RegExp(r'[\x00-\x1f]').hasMatch(decoded) ||
        !allowed.contains(uri.path)) {
      return '/home';
    }
    return value;
  } catch (_) {
    return '/home';
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  String pendingLocation = '/home';
  ref.listen(authProvider, (_, next) {
    refresh.value++;
  });
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.restoring) {
        if (state.uri.path == '/launch') return null;
        pendingLocation = state.uri.path == '/auth/login'
            ? Uri(
                path: '/auth/login',
                queryParameters: {
                  'returnTo': safeReturnTo(
                    state.uri.queryParameters['returnTo'],
                  ),
                },
              ).toString()
            : safeReturnTo(state.uri.toString());
        return '/launch';
      }
      if (state.uri.path == '/launch') return pendingLocation;
      if (auth.principal == null &&
          [
            '/pets',
            '/sessions',
            '/cart',
            '/orders',
            '/payments',
            '/membership',
            '/points',
          ].contains(state.uri.path)) {
        return Uri(
          path: '/auth/login',
          queryParameters: {'returnTo': state.uri.toString()},
        ).toString();
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/payments',
        builder: (_, state) =>
            PaymentScreen(id: state.uri.queryParameters['id'] ?? ''),
      ),
      GoRoute(path: '/membership', builder: (_, _) => const MembershipScreen()),
      GoRoute(path: '/points', builder: (_, _) => const PointsScreen()),
      GoRoute(
        path: '/launch',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, state) => LoginScreen(
          returnTo: safeReturnTo(state.uri.queryParameters['returnTo']),
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, state) =>
            OrdersScreen(initialId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/sessions', builder: (_, _) => const SessionsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => TabShell(shell: shell),
        branches: [
          for (final path in [
            '/home',
            '/categories',
            '/pets',
            '/nearby',
            '/me',
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (_, _) => TabScreen(path: path),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
