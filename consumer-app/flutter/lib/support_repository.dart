import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class SupportRepository {
  final ConsumerApi api;
  SupportRepository(this.api);
  Future<ConversationListEnvelope> conversations({String? cursor}) async =>
      ConversationListEnvelope.fromJson(
        await api.request(
          'GET',
          Uri(
            path: '/consumer/conversations',
            queryParameters: {'cursor': ?cursor, 'limit': '50'},
          ).toString(),
        ),
      );
  Future<Conversation> create({String? store}) async =>
      ConversationEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/conversations',
          body: ConversationInput(
            kind: store == null ? 'PLATFORM' : 'MERCHANT',
            store_id: store,
          ).toJson(),
          idempotencyKey: const Uuid().v4(),
        ),
      ).data;
  Future<Conversation> detail(String id) async => ConversationEnvelope.fromJson(
    await api.request('GET', '/consumer/conversations/$id'),
  ).data;
  Future<SupportMessageListEnvelope> messages(String id, int after) async =>
      SupportMessageListEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/conversations/$id/messages?after_sequence=$after&limit=50',
        ),
      );
  Future<SupportMessage> send(
    String id,
    SupportMessageInput body,
    String key,
  ) async => SupportMessageEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/conversations/$id/messages',
      body: body.toJson(),
      idempotencyKey: key,
    ),
  ).data;
  Future<Conversation> read(String id, int through) async =>
      ConversationEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/conversations/$id/read',
          body: ConversationRead(through_sequence: through).toJson(),
          idempotencyKey: const Uuid().v4(),
        ),
      ).data;
  Future<Conversation> status(Conversation c, String status) async =>
      ConversationEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/conversations/${c.id}/status',
          body: ConversationStatusInput(status: status).toJson(),
          version: c.version,
          idempotencyKey: const Uuid().v4(),
        ),
      ).data;
  Future<SupportCard> card(String cid, String mid) async =>
      SupportCardEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/conversations/$cid/messages/$mid/card',
        ),
      ).data;
  Future<MediaAsset> upload(Uint8List bytes, String mime) => api.uploadReview(
    bytes,
    mime,
    sha256.convert(bytes).toString(),
    scope: 'CHAT',
  );
  Future<Uint8List> image(String url) => api.mediaBytes(url);
  Future<NotificationMessageListEnvelope> notifications({
    String? category,
    String? cursor,
  }) async => NotificationMessageListEnvelope.fromJson(
    await api.request(
      'GET',
      Uri(
        path: '/consumer/messages',
        queryParameters: {
          'category': ?category,
          'cursor': ?cursor,
          'limit': '50',
        },
      ).toString(),
    ),
  );
  Future<String> destination(String id) async =>
      NotificationDestinationEnvelope.fromJson(
        await api.request('GET', '/consumer/messages/$id/target'),
      ).data.destination;
  Future<void> notificationRead(String id) async {
    await api.request(
      'POST',
      '/consumer/messages/$id/read',
      idempotencyKey: const Uuid().v4(),
    );
  }

  Future<List<NotificationPreference>> preferences() async =>
      NotificationPreferenceListEnvelope.fromJson(
        await api.request('GET', '/consumer/notification-preferences'),
      ).data;
  Future<void> preference(String category, bool enabled) async {
    await api.request(
      'PUT',
      '/consumer/notification-preferences/$category',
      body: NotificationPreferenceInput(enabled: enabled).toJson(),
      idempotencyKey: const Uuid().v4(),
    );
  }
}

final supportRepositoryProvider = Provider(
  (ref) => SupportRepository(ref.watch(consumerApiProvider)),
);
