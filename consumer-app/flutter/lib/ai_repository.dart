import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class AiRepository {
  final ConsumerApi api;
  AiRepository(this.api);
  Future<AiPreferences> preferences() async => AiPreferencesEnvelope.fromJson(
    await api.request('GET', '/consumer/ai/preferences'),
  ).data;
  Future<AiQuota> quota() async =>
      AiQuotaEnvelope.fromJson(await api.request('GET', '/consumer/ai/quota'))
          .data;
  Future<AiPreferences> consent(bool enabled, int version) async =>
      AiPreferencesEnvelope.fromJson(
        await api.request(
          'PUT',
          '/consumer/ai/preferences',
          body: AiPreferenceInput(personalization_enabled: enabled).toJson(),
          version: version,
          idempotencyKey: const Uuid().v4(),
        ),
      ).data;
  Future<AiConversationListEnvelope> conversations({String? cursor}) async =>
      AiConversationListEnvelope.fromJson(
        await api.request(
          'GET',
          Uri(
            path: '/consumer/ai/conversations',
            queryParameters: {'cursor': ?cursor, 'limit': '50'},
          ).toString(),
        ),
      );
  Future<AiConversationDetail> create(String? pet, String key) async =>
      AiConversationDetailEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/ai/conversations',
          body: AiConversationInput(current_pet_id: pet).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<AiConversationDetail> detail(String id) async =>
      AiConversationDetailEnvelope.fromJson(
        await api.request('GET', '/consumer/ai/conversations/$id'),
      ).data;
  Future<AiMessage> send(String id, AiMessageInput body, String key) async =>
      AiMessageEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/ai/conversations/$id/messages',
          body: body.toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<void> clear(String id) async => api.request(
    'DELETE',
    '/consumer/ai/conversations/$id',
    idempotencyKey: const Uuid().v4(),
  );
  Future<AiProposal> proposal(String id) async => AiProposalEnvelope.fromJson(
    await api.request('GET', '/consumer/ai/profile-proposals/$id'),
  ).data;
  Future<AiProposal> decide(
    AiProposal proposal,
    bool accept,
  ) async => AiProposalEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/ai/profile-proposals/${proposal.id}/${accept ? 'accept' : 'reject'}',
      body: {},
      version: proposal.pet_version,
      idempotencyKey: const Uuid().v4(),
    ),
  ).data;
}

final aiRepositoryProvider = Provider(
  (ref) => AiRepository(ref.watch(consumerApiProvider)),
);
