import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class PublishingRepository {
  final ConsumerApi api;
  PublishingRepository(this.api);
  Future<ReviewEligibility> eligibility(String item) async =>
      ReviewEligibilityEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/order-items/$item/review-eligibility',
        ),
      ).data;
  Future<ReviewDetail> review(String id) async => ReviewDetailEnvelope.fromJson(
    await api.request('GET', '/consumer/reviews/$id'),
  ).data;
  Future<ReviewDetailListEnvelope> own({String? cursor}) async =>
      ReviewDetailListEnvelope.fromJson(
        await api.request(
          'GET',
          Uri(
            path: '/consumer/reviews',
            queryParameters: {'limit': '20', 'cursor': ?cursor},
          ).toString(),
        ),
      );
  Future<PublicReviewListEnvelope> reviews(
    String spu, {
    String? cursor,
  }) async => PublicReviewListEnvelope.fromJson(
    await api.request(
      'GET',
      Uri(
        path: '/public/spus/$spu/reviews',
        queryParameters: {'limit': '20', 'cursor': ?cursor},
      ).toString(),
      anonymous: true,
    ),
  );
  Future<ReviewDetail> save(
    String item,
    ReviewInput body,
    String key, {
    ReviewDetail? existing,
  }) async => ReviewDetailEnvelope.fromJson(
    await api.request(
      existing == null ? 'POST' : 'PATCH',
      existing == null
          ? '/consumer/order-items/$item/reviews'
          : '/consumer/reviews/${existing.id}',
      body: body.toJson(),
      idempotencyKey: key,
      version: existing?.version,
    ),
  ).data;
  Future<MediaAsset> upload(Uint8List bytes, String mime) =>
      api.uploadReview(bytes, mime, sha256.convert(bytes).toString());
  Future<PublicArticleListEnvelope> articles({
    String? cursor,
    String? category,
  }) async => PublicArticleListEnvelope.fromJson(
    await api.request(
      'GET',
      Uri(
        path: '/public/content',
        queryParameters: {
          'limit': '20',
          'cursor': ?cursor,
          'category': ?category,
        },
      ).toString(),
      anonymous: true,
    ),
  );
  Future<PublicArticle> article(String id, {String? pet}) async =>
      PublicArticleEnvelope.fromJson(
        await api.request(
          'GET',
          Uri(
            path: pet == null ? '/public/content/$id' : '/consumer/content/$id',
            queryParameters: {'pet_id': ?pet},
          ).toString(),
          anonymous: pet == null,
        ),
      ).data;
}

final publishingRepositoryProvider = Provider(
  (ref) => PublishingRepository(ref.watch(consumerApiProvider)),
);
