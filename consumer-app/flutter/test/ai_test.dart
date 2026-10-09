import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_consumer/ai_repository.dart';
import 'package:pawday_consumer/ai_screen.dart';
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/api/generated/dto.dart';
import 'package:pawday_consumer/repositories.dart';
import 'package:pawday_consumer/router.dart';

import 'api_test.dart' as fixtures;

const initialQuota = AiQuota(
  ordinary_remaining: 3,
  membership_remaining: 20,
  remaining: 23,
  policy_id: 'policy',
  ordinary_period: 'SHANGHAI_DAY',
  membership_period: 'PURCHASED_TERM',
  enabled: true,
);
const conversation = AiConversationDetail(
  id: 'conversation',
  pet_id: null,
  status: 'ACTIVE',
  expires_at: '2026-11-01T00:00:00Z',
  created_at: '2026-10-09T00:00:00Z',
  messages: [],
);

class LoggedIn extends AuthNotifier {
  void clearIdentity() => state = const AuthState();
  @override
  AuthState build() => const AuthState(principal: fixtures.principal);
}

class FakeAi extends AiRepository {
  FakeAi() : super(fixtures.apiWith((_) async => fixtures.ok({})));
  bool available = true;
  int failures = 0;
  final sentKeys = <String>[];
  final contexts = <String?>[];
  @override
  Future<AiPreferences> preferences() async => AiPreferences(
    personalization_enabled: false,
    version: 0,
    data_usage: '模型不接收个人身份与原始问题',
    provider_available: available,
  );
  @override
  Future<AiQuota> quota() async => quotaValue;
  AiQuota get quotaValue => initialQuota;
  @override
  Future<AiConversationListEnvelope> conversations({String? cursor}) async =>
      const AiConversationListEnvelope(
        data: [],
        page: Page(next_cursor: null, has_more: false),
        meta: Meta(request_id: 'test', correlation_id: 'test'),
      );
  @override
  Future<AiConversationDetail> create(String? pet, String key) async {
    contexts.add(pet);
    return conversation;
  }

  @override
  Future<AiMessage> send(String id, AiMessageInput body, String key) async {
    sentKeys.add(key);
    if (failures-- > 0) throw const ApiFailure(0, 'NETWORK_UNAVAILABLE');
    return AiMessage(
      message_id: 'message',
      conversation_id: id,
      text: '资料不足，不能确定适合',
      user_text: body.text,
      pet_context: null,
      product_cards: [],
      prompt_id: 'prompt',
      policy_id: 'policy',
      fit_rule_version: 'pawday-fit-1',
      mode: 'DEEPSEEK_GROUNDED',
      proposal_id: null,
      created_at: '2026-10-09T00:00:00Z',
      quota: quotaValue,
    );
  }
}

Future<void> show(WidgetTester tester, FakeAi repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(LoggedIn.new),
        aiRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AiScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('identity change clears an already displayed private AI answer', (
    tester,
  ) async {
    final repo = FakeAi();
    await show(tester, repo);
    await tester.enterText(find.byType(TextField), 'PRIVATE QUESTION');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('你：PRIVATE QUESTION'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiScreen)),
    );
    (container.read(authProvider.notifier) as LoggedIn).clearIdentity();
    await tester.pumpAndSettle();
    expect(find.text('你：PRIVATE QUESTION'), findsNothing);
    expect(find.text('资料不足，不能确定适合'), findsNothing);
  });
  test('AI login return path rejects external navigation', () {
    expect(safeReturnTo('/ai?sku_id=test'), '/ai?sku_id=test');
    expect(safeReturnTo('//evil/ai'), '/home');
    expect(safeReturnTo('/ai%5Cevil'), '/home');
  });
  testWidgets(
    'missing provider disables send without removing privacy controls',
    (tester) async {
      final repo = FakeAi()..available = false;
      await show(tester, repo);
      expect(find.text('解释服务尚未配置，暂时不能发送问题。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
    },
  );
  testWidgets(
    'unknown network outcome retries with the same key after conversation creation',
    (tester) async {
      final repo = FakeAi()..failures = 1;
      await show(tester, repo);
      await tester.enterText(find.byType(TextField), 'Explain ingredients');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(repo.sentKeys.length, 2);
      expect(repo.sentKeys[0], repo.sentKeys[1]);
      expect(repo.contexts, [null]);
      expect(find.text('资料不足，不能确定适合'), findsOneWidget);
    },
  );
}
