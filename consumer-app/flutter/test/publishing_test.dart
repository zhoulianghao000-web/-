import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/publishing_repository.dart';
import 'package:pawday_consumer/publishing_screen.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/router.dart';

import 'checkout_test.dart' show envelope;
import 'navigation_test.dart' show GuestRepository;

const id = '00000000-0000-4000-8000-000000000001';
final article = {
  'id': id,
  'revision_id': id,
  'title': '有来源的文章',
  'category': 'PET_CARE',
  'body': '<script>plain text</script>',
  'source_refs': ['TEST ONLY source'],
  'sponsored': true,
  'version': 2,
  'media': [],
  'published_at': '2026-10-08T00:00:00Z',
  'products': [],
};
final review = {
  'id': id,
  'revision_id': id,
  'spu_id': id,
  'sku_id': id,
  'rating': 4,
  'service_rating': 5,
  'body': '真实购买体验',
  'verified_purchase': true,
  'version': 1,
  'created_at': '2026-10-08T00:00:00Z',
  'media': [],
  'pet_label': null,
  'order_id': id,
  'suborder_id': id,
  'order_item_id': id,
  'user_id': id,
  'merchant_id': id,
  'store_id': null,
  'visibility': 'PUBLIC',
  'draft_status': 'APPROVED',
  'share_pet_label': false,
  'published_revision_id': id,
  'pet_id': null,
  'revision_no': 1,
  'moderation': [],
};
ConsumerApi api(Future<http.Response> Function(http.Request) handler) =>
    ConsumerApi(
      base: Uri.parse('http://localhost/api/v1'),
      transport: MockClient(handler),
      vault: MemoryVault(),
    );
void main() {
  test(
    'review save sends expected version and a persistent command key',
    () async {
      late http.Request request;
      final a = api((r) async {
        request = r;
        return envelope(review);
      });
      final repo = PublishingRepository(a);
      final old = ReviewDetail.fromJson(review);
      await repo.save(
        id,
        const ReviewInput(
          rating: 3,
          service_rating: 4,
          body: 'updated',
          asset_ids: [],
          pet_id: null,
          share_pet_label: false,
        ),
        'TEST-persistent-key',
        existing: old,
      );
      expect(request.method, 'PATCH');
      expect(request.headers['If-Match'], '"1"');
      expect(request.headers['Idempotency-Key'], 'TEST-persistent-key');
      expect((jsonDecode(request.body) as Map)['share_pet_label'], false);
    },
  );
  test(
    'guest article request never sends a consumer authorization header',
    () async {
      late http.Request request;
      final a = api((r) async {
        request = r;
        return envelope(article);
      });
      await a.accept(
        const Tokens(
          access_token: 'TEST-access',
          refresh_token: 'TEST-refresh',
          expires_in: 900,
          session_id: id,
          user_id: id,
        ),
      );
      await PublishingRepository(a).article(id);
      expect(request.url.path, '/api/v1/public/content/$id');
      expect(request.headers.containsKey('Authorization'), false);
    },
  );
  test('publication resource paths reject external and admin destinations before network', () async {
    var calls = 0;
    final a = api((r) async {
      calls++;
      return http.Response('', 200);
    });
    await expectLater(
      a.mediaBytes('https://example.com/video'),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => a.mediaSource('/api/v1/admin/content/$id/media/$id'),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => a.publicMediaUri('/api/v1/consumer/reviews/$id/media/$id'),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 0);
  });
  test(
    'oversized review upload is rejected without issuing credentials',
    () async {
      var calls = 0;
      final a = api((r) async {
        calls++;
        return envelope({});
      });
      await expectLater(
        PublishingRepository(a).upload(Uint8List(5242881), 'video/mp4'),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 0);
    },
  );
  test('review navigation preserves login returnTo but refuses foreign destinations', () {
    expect(
      safeReturnTo('/review-edit?item_id=$id'),
      '/review-edit?item_id=$id',
    );
    expect(safeReturnTo('//example.com/review-edit'), '/home');
    expect(safeReturnTo('/admin/reviews'), '/home');
    expect(safeReturnTo('/content?id=$id'), '/content?id=$id');
  });
  testWidgets('knowledge article displays source sponsorship and plain text', (
    tester,
  ) async {
    final a = api((r) async => envelope(article));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          consumerApiProvider.overrideWithValue(a),
          consumerRepositoryProvider.overrideWithValue(GuestRepository(a)),
        ],
        child: const MaterialApp(home: ContentScreen(id: id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('有来源的文章'), findsOneWidget);
    expect(find.text('商业推广'), findsOneWidget);
    expect(find.text('<script>plain text</script>'), findsOneWidget);
    expect(find.text('TEST ONLY source'), findsOneWidget);
  });
}
