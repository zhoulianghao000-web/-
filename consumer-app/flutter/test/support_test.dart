import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pawday_consumer/support_screen.dart';
import 'package:pawday_consumer/repositories.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/support_repository.dart';
import 'package:pawday_consumer/router.dart';

import 'checkout_test.dart' show envelope;

const id = '00000000-0000-4000-8000-000000000001';
final message = {
  'id': id,
  'conversation_id': id,
  'sequence': 1,
  'sender_realm': 'CONSUMER',
  'type': 'TEXT',
  'body': 'TEST private',
  'target_id': null,
  'created_at': '2026-10-08T00:00:00Z',
  'outgoing': true,
  'media': [],
};
ConsumerApi api(Future<http.Response> Function(http.Request) handler) =>
    ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      transport: MockClient(handler),
      vault: MemoryVault(),
    );
void main() {
  test('support navigation preserves login returnTo and rejects foreign destinations', () {
    expect(safeReturnTo('/conversation?id=$id'), '/conversation?id=$id');
    expect(safeReturnTo('/support?store_id=$id'), '/support?store_id=$id');
    expect(safeReturnTo('/messages'), '/messages');
    expect(safeReturnTo('//foreign/conversation'), '/home');
    expect(safeReturnTo('/admin/conversations'), '/home');
  });
  test(
    'message retry retains caller key and does not invent a server sequence',
    () async {
      late http.Request request;
      final a = api((r) async {
        request = r;
        return envelope(message);
      });
      final body = SupportMessageInput(
        type: 'TEXT',
        body: 'TEST private',
        asset_ids: const [],
        target_id: null,
      );
      await SupportRepository(a).send(id, body, 'TEST-persistent-message-key');
      expect(request.headers['Idempotency-Key'], 'TEST-persistent-message-key');
      expect((jsonDecode(request.body) as Map).containsKey('sequence'), false);
      expect(request.url.path, '/api/v1/consumer/conversations/$id/messages');
    },
  );
  test('private chat image paths are realm constrained', () async {
    var calls = 0;
    final a = api((r) async {
      calls++;
      return http.Response('', 200);
    });
    await expectLater(
      a.mediaBytes('/api/v1/admin/conversations/$id/messages/$id/media/$id'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      a.mediaBytes('/api/v1/public/conversations/$id/messages/$id/media/$id'),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 0);
  });
  test('chat video and oversized image fail before upload grant', () async {
    var calls = 0;
    final a = api((r) async {
      calls++;
      return envelope({});
    });
    await expectLater(
      SupportRepository(a).upload(Uint8List(10), 'video/mp4'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      SupportRepository(a).upload(Uint8List(5242881), 'image/png'),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 0);
  });
  test('independent reminder change writes only its own category', () async {
    late http.Request request;
    final a = api((r) async {
      request = r;
      return envelope({'category': 'FOOD_REMINDER', 'enabled': false});
    });
    await SupportRepository(a).preference('FOOD_REMINDER', false);
    expect(request.method, 'PUT');
    expect(
      request.url.path,
      '/api/v1/consumer/notification-preferences/FOOD_REMINDER',
    );
    expect(jsonDecode(request.body), {'enabled': false});
  });
  testWidgets(
    'private support text is rendered as text and image paths are not public',
    (tester) async {
      final c = {
        'id': id,
        'kind': 'PLATFORM',
        'store_id': null,
        'status': 'OPEN',
        'last_sequence': 1,
        'delivered_sequence': 1,
        'version': 1,
        'created_at': '2026-10-08T00:00:00Z',
        'updated_at': '2026-10-08T00:00:00Z',
        'assigned_to_me': false,
        'assigned': true,
        'read_sequence': 1,
        'unread_count': 0,
      };
      final a = api(
        (r) async => envelope(
          r.url.path.endsWith('/messages')
              ? [
                  {
                    ...message,
                    'body': '<script>plain support text</script>',
                    'outgoing': false,
                  },
                ]
              : c,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [consumerApiProvider.overrideWithValue(a)],
          child: const MaterialApp(home: ConversationScreen(id: id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('<script>plain support text</script>'), findsOneWidget);
      expect(find.text('客服正在接待'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      a.dispose();
    },
  );
  testWidgets('messages show seven separate reminder switches', (tester) async {
    final a = api(
      (r) async => envelope(
        r.url.path.endsWith('/notification-preferences')
            ? [
                'ORDER',
                'AFTERSALE',
                'PRICE_DROP',
                'RESTOCK',
                'FOOD_REMINDER',
                'ACTIVITY',
                'SUPPORT',
              ].map((c) => {'category': c, 'enabled': true}).toList()
            : [
                {
                  'id': id,
                  'category': 'ORDER',
                  'event_type': 'OrderPaid',
                  'target_type': 'ORDER',
                  'target_id': id,
                  'notify_enabled': true,
                  'read_at': null,
                  'created_at': '2026-10-08T00:00:00Z',
                },
              ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerApiProvider.overrideWithValue(a)],
        child: const MaterialApp(home: MessagesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(7));
    expect(find.textContaining('系统推送'), findsOneWidget);
    expect(find.text('付款成功，等待商家发货'), findsOneWidget);
    expect(find.text('OrderPaid'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    a.dispose();
  });
}
