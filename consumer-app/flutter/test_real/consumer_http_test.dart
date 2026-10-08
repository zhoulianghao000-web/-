import 'package:pawday_consumer/payment_repository.dart';
import 'package:pawday_consumer/publishing_repository.dart';
import 'package:pawday_consumer/support_repository.dart';
import 'package:pawday_consumer/nearby_repository.dart';

import 'dart:typed_data';

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/pet_repository.dart';
import 'package:pawday_consumer/catalog_repository.dart';
import 'package:pawday_consumer/checkout_repository.dart';
import 'package:pawday_consumer/order_repository.dart';
import 'package:pawday_consumer/aftersale_repository.dart';
import 'package:pawday_consumer/api/generated/dto.dart';

// Explicit CI entry point. Missing infrastructure fails; this test never uses a mock transport.
void main() {
  test('real OTP Outbox delivery, login, refresh, restore, session list and logout', () async {
    final env = Platform.environment;
    final base = env['PAWDAY_REAL_API_BASE'];
    final directory = env['PAWDAY_REAL_SMS_DIRECTORY'];
    if (base == null || directory == null) {
      throw StateError(
        'Real API and local SMS delivery directory are required',
      );
    }
    final vault = MemoryVault();
    final api = ConsumerApi(
      base: Uri.parse(base),
      transport: http.Client(),
      vault: vault,
    );
    const phone = '+8613900000024';
    await api.requestCode(phone);
    String? code;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (code == null && DateTime.now().isBefore(deadline)) {
      final inbox = Directory(directory);
      if (await inbox.exists()) {
        for (final entity in inbox.listSync().whereType<File>()) {
          final lines = await entity.readAsLines();
          if (lines.length >= 2 && lines[0] == phone) {
            code = lines[1];
            break;
          }
        }
      }
      if (code == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    expect(
      code,
      isNotNull,
      reason: 'Real RabbitMQ consumer must deliver the OTP',
    );
    final principal = await api.login(phone, code!);
    expect(principal.realm, 'CONSUMER');
    expect(principal.user_id, isNotNull);
    await api.refresh();
    expect(
      (await api.sessions()).any((s) => s.id == principal.session_id),
      true,
    );
    api.dispose();
    final restored = ConsumerApi(
      base: Uri.parse(base),
      transport: http.Client(),
      vault: vault,
    );
    await restored.restore();
    expect((await restored.me()).user_id, principal.user_id);
    final pets = PetRepository(restored);
    final taxonomy = await pets.taxonomy();
    expect(taxonomy.map((s) => s.category).toSet().length, 5);
    final command = newPetCommandKey();
    final body = <String, dynamic>{
      'name': 'CI REAL 小爪',
      'species_id': taxonomy
          .firstWhere((s) => s.category == 'CAT' && s.parent_id == null)
          .id,
      'sex': 'UNKNOWN',
      'neutered_status': 'UNKNOWN',
      'allergens': [],
      'avoidance_notes': [],
    };
    final pet = await pets.save(body, key: command);
    expect(pet.life_stage_unknown, true);
    expect((await pets.save(body, key: command)).id, pet.id);
    expect((await pets.list()).any((p) => p.id == pet.id), true);
    final updated = await pets.save(
      {'name': 'CI REAL 更新'},
      existing: pet,
      key: newPetCommandKey(),
    );
    expect(updated.version, pet.version + 1);
    await expectLater(
      pets.save({'name': '过期写入'}, existing: pet, key: newPetCommandKey()),
      throwsA(
        isA<ApiFailure>().having((e) => e.versionConflict, 'conflict', true),
      ),
    );
    await pets.recordWeight(
      updated,
      4000,
      DateTime.now().toIso8601String().substring(0, 10),
      newPetCommandKey(),
    );
    expect((await pets.weights(updated)).first.weight_g, 4000);
    final catalog = CatalogRepository(restored);
    final page = await catalog.browse(category: 'CAT');
    expect(
      page.data,
      isNotEmpty,
      reason: 'Real admin/merchant browser flow must publish an active stocked offer first',
    );
    final sku = page.data.first.id;
    expect((await catalog.standard(sku)).source_refs, isNotEmpty);
    expect((await catalog.offers(sku)).any((o) => o.in_stock), true);
    final fit = await catalog.fit(sku, pet.id);
    expect(fit.result, 'INSUFFICIENT_DATA');
    expect(fit.uncertainties, isNotEmpty);
    expect(fit.fit_rule_version, 'pawday-fit-1');
    final checkout = CheckoutRepository(restored);
    final offer = (await catalog.offers(sku)).firstWhere((o) => o.in_stock);
    final cartItem = await checkout.add(
      offer.offer_id,
      1,
      pet.id,
      checkoutCommandKey(),
    );
    final address = await checkout.saveAddress(
      const CheckoutAddressInput(
        recipient: 'TEST-only recipient',
        phone: '13800000000',
        province_code: '310000',
        detail: 'TEST-only Shanghai address',
      ),
      checkoutCommandKey(),
    );
    final quoteKey = checkoutCommandKey();
    final quote = await checkout.quote([cartItem.id], address.id, quoteKey);
    expect(quote.status, 'ACTIVE');
    expect(quote.goods_amount_fen, offer.sale_price_fen);
    expect(quote.shipping_amount_fen, 400);
    expect(quote.payable_amount_fen, offer.sale_price_fen + 400);
    expect(quote.items.single.offer_id, offer.offer_id);
    expect(
      (await checkout.quote([cartItem.id], address.id, quoteKey)).quote_id,
      quote.quote_id,
    );
    expect((await checkout.getQuote(quote.quote_id)).status, 'ACTIVE');
    await checkout.quantity(cartItem, 2, checkoutCommandKey());
    expect((await checkout.getQuote(quote.quote_id)).status, 'INVALIDATED');
    final currentItem = (await checkout.cart()).items.firstWhere(
      (i) => i.id == cartItem.id,
    );
    final nextQuote = await checkout.quote(
      [currentItem.id],
      address.id,
      checkoutCommandKey(),
    );
    final ordering = OrderRepository(restored), orderKey = checkoutCommandKey();
    final order = await ordering.create(nextQuote.quote_id, orderKey);
    expect(order.status, 'PENDING_PAYMENT');
    expect(order.payable_amount_fen, nextQuote.payable_amount_fen);
    expect(order.suborders.single.items.single.quantity, 2);
    expect(order.reservations.single.quantity, 2);
    expect((await ordering.create(nextQuote.quote_id, orderKey)).id, order.id);
    expect((await ordering.get(order.id)).payment.status, 'PENDING');
    expect((await ordering.list()).data.any((o) => o.id == order.id), true);
    expect((await checkout.getQuote(nextQuote.quote_id)).status, 'CONSUMED');
    final cancelled = await ordering.cancel(order, checkoutCommandKey());
    expect(cancelled.status, 'CANCELLED');
    expect(cancelled.payment.status, 'CLOSED');
    expect(cancelled.reservations.single.status, 'RELEASED');
    expect(cancelled.suborders.single.items.single.cancelled_qty, 2);

    final paidItem = await checkout.add(
      offer.offer_id,
      1,
      pet.id,
      checkoutCommandKey(),
    );
    final paidQuote = await checkout.quote(
      [paidItem.id],
      address.id,
      checkoutCommandKey(),
    );
    final paidOrder = await ordering.create(
      paidQuote.quote_id,
      checkoutCommandKey(),
    );
    final payments = PaymentRepository(restored),
        attemptKey = checkoutCommandKey();
    final pending = await payments.attempt(
      paidOrder.payment.id,
      'WECHAT',
      attemptKey,
    );
    expect(pending.status, 'PROCESSING');
    expect(
      (await payments.attempt(
        paidOrder.payment.id,
        'WECHAT',
        attemptKey,
      )).attempts.single.id,
      pending.attempts.single.id,
    );
    final confirmed = await payments.simulate(
      paidOrder.payment.id,
      pending.attempts.single.id,
      'SUCCEEDED',
    );
    expect(confirmed.status, 'SUCCEEDED');
    expect(confirmed.final_channel, 'WECHAT');
    expect(
      (await payments.requery(paidOrder.payment.id)).successful_attempt_id,
      pending.attempts.single.id,
    );
    final fulfilling = await ordering.get(paidOrder.id);
    expect(fulfilling.status, 'FULFILLING');
    expect(
      fulfilling.suborders.single.fulfillment_status,
      'PAID_WAITING_FULFILLMENT',
    );
    expect(fulfilling.reservations.single.status, 'CONSUMED');
    final staffLogin = await http.post(
      Uri.parse('$base/merchant/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'login_name': 'local-staff-a',
        'password': env['PAWDAY_DEMO_MERCHANT_PASSWORD'],
        'device_id': 'ci-fulfillment-dart',
      }),
    );
    expect(staffLogin.statusCode, 200);
    final staffToken =
        (jsonDecode(staffLogin.body)
                as Map<String, dynamic>)['data']['access_token']
            as String;
    final sub = fulfilling.suborders.single;
    final shipment = await http.post(
      Uri.parse('$base/merchant/suborders/${sub.id}/shipments'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $staffToken',
        'Idempotency-Key': checkoutCommandKey(),
        'If-Match': '"${sub.version}"',
      },
      body: jsonEncode({
        'carrier_code': 'SF',
        'tracking_no': 'DART${DateTime.now().microsecondsSinceEpoch}',
        'items': [
          {'order_item_id': sub.items.single.id, 'quantity': 1},
        ],
      }),
    );
    expect(shipment.statusCode, 200, reason: shipment.body);
    final shipped = await ordering.fulfillment(sub.id);
    expect(shipped.fulfillment_status, 'SHIPPED_WAITING_RECEIPT');
    final tracking = await ordering.tracking(shipped.shipments.single.id);
    expect(tracking.status, 'UNKNOWN');
    expect(tracking.stale, true);
    final receiptKey = checkoutCommandKey();
    expect(
      (await ordering.receive(shipped, [
        shipped.shipments.single.id,
      ], receiptKey)).fulfillment_status,
      'COMPLETED',
    );
    expect(
      (await ordering.receive(shipped, [
        shipped.shipments.single.id,
      ], receiptKey)).fulfillment_status,
      'COMPLETED',
    );
    expect((await ordering.get(paidOrder.id)).status, 'COMPLETED');

    final publishing = PublishingRepository(restored);
    final eligibility = await publishing.eligibility(sub.items.single.id);
    expect(eligibility.eligible, true);
    final video = base64Decode(
      (await File(
        '../../backend/src/test/resources/review-video.base64',
      ).readAsString()).trim(),
    );
    final videoAsset = await publishing.upload(video, 'video/mp4');
    expect(videoAsset.status, 'READY');
    final reviewInput = ReviewInput(
      rating: 4,
      service_rating: 5,
      body: 'CI REAL Dart purchased video review',
      asset_ids: [videoAsset.asset_id],
      pet_id: pet.id,
      share_pet_label: true,
    );
    final reviewKey = checkoutCommandKey(),
        review = await publishing.save(
          sub.items.single.id,
          reviewInput,
          reviewKey,
        );
    expect(review.draft_status, 'PENDING');
    expect(
      (await publishing.save(sub.items.single.id, reviewInput, reviewKey)).id,
      review.id,
    );
    final revoked = await publishing.save(
      sub.items.single.id,
      ReviewInput(
        rating: 4,
        service_rating: 5,
        body: review.body,
        asset_ids: reviewInput.asset_ids,
        pet_id: null,
        share_pet_label: false,
      ),
      checkoutCommandKey(),
      existing: review,
    );
    expect(revoked.share_pet_label, false);
    expect(revoked.pet_label, isNull);
    expect((await publishing.own()).data.any((r) => r.id == review.id), true);
    final articles = await publishing.articles();
    expect(
      articles.data.any((a) => a.title == 'CI REAL M52 sourced content'),
      true,
    );
    final article = articles.data.firstWhere(
      (a) => a.title == 'CI REAL M52 sourced content',
    );
    expect(
      (await publishing.article(article.id, pet: pet.id)).products.first.fit,
      isNotNull,
    );
    expect(article.sponsored, true);

    // M4.5 real chain: paid cancellation refunds one frozen unit, then a
    // refund-only after-sale is approved by the merchant and settled.
    final aftersales = AfterSaleRepository(restored);
    final cancelItem = await checkout.add(
      offer.offer_id,
      2,
      pet.id,
      checkoutCommandKey(),
    );
    final cancelQuote = await checkout.quote(
      [cancelItem.id],
      address.id,
      checkoutCommandKey(),
    );
    final cancelOrder = await ordering.create(
      cancelQuote.quote_id,
      checkoutCommandKey(),
    );
    final cancelPending = await payments.attempt(
      cancelOrder.payment.id,
      'WECHAT',
      checkoutCommandKey(),
    );
    await payments.simulate(
      cancelOrder.payment.id,
      cancelPending.attempts.single.id,
      'SUCCEEDED',
    );
    final cancelSub = (await ordering.get(cancelOrder.id)).suborders.single;
    final cancelKey = checkoutCommandKey();
    final cancellation = await aftersales.cancelPaid(cancelSub.id, [
      CancellationItemInput(
        order_item_id: cancelSub.items.single.id,
        quantity: 1,
      ),
    ], cancelKey);
    expect(
      (await aftersales.cancelPaid(cancelSub.id, [
        CancellationItemInput(
          order_item_id: cancelSub.items.single.id,
          quantity: 1,
        ),
      ], cancelKey)).id,
      cancellation.id,
      reason: 'Idempotent replay must return the same cancellation',
    );
    var settledCancellation = await aftersales.getCancellation(cancellation.id);
    final cancelDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (settledCancellation.status != 'COMPLETED' &&
        DateTime.now().isBefore(cancelDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      settledCancellation = await aftersales.getCancellation(cancellation.id);
    }
    expect(settledCancellation.status, 'COMPLETED');
    expect(settledCancellation.refund_amount_fen, offer.sale_price_fen);
    expect(settledCancellation.refund, isNotNull);
    expect(settledCancellation.refund!.status, 'SUCCEEDED');
    final afterCancel = await ordering.fulfillment(cancelSub.id);
    expect(afterCancel.items.single.cancelled_qty, 1);
    expect(
      (await aftersales.cancellations(cancelSub.id)).data
          .any((c) => c.id == cancellation.id),
      true,
    );

    final applyInput = AfterSaleInput(
      type: 'REFUND_ONLY',
      reason_code: 'QUALITY_ISSUE',
      reason_text: 'CI REAL 仅退款',
      items: [
        AfterSaleItemInput(order_item_id: sub.items.single.id, quantity: 1),
      ],
      evidence: const [AfterSaleEvidenceInput(content: 'CI REAL 凭证')],
    );
    final applyKey = checkoutCommandKey();
    final applied = await aftersales.apply(sub.id, applyInput, applyKey);
    expect(applied.status, 'PENDING_MERCHANT');
    expect(applied.refund_amount_fen, offer.sale_price_fen);
    expect(
      (await aftersales.apply(sub.id, applyInput, applyKey)).id,
      applied.id,
      reason: 'Idempotent replay must return the same after-sale',
    );
    final decide = await http.post(
      Uri.parse('$base/merchant/aftersales/${applied.id}/decide'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $staffToken',
        'Idempotency-Key': checkoutCommandKey(),
        'If-Match': '"${applied.version}"',
      },
      body: jsonEncode({'action': 'APPROVE_REFUND', 'reason': 'CI REAL 同意退款'}),
    );
    expect(decide.statusCode, 200, reason: decide.body);
    var settled = await aftersales.getAftersale(applied.id);
    final settleDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (settled.status != 'COMPLETED' &&
        DateTime.now().isBefore(settleDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      settled = await aftersales.getAftersale(applied.id);
    }
    expect(
      settled.status,
      'COMPLETED',
      reason: 'Simulated channel refund must settle',
    );
    expect(settled.refund, isNotNull);
    expect(settled.refund!.status, 'SUCCEEDED');
    expect(settled.refund!.amount_fen, offer.sale_price_fen);
    expect(
      (await aftersales.aftersales(sub.id)).data.any((a) => a.id == applied.id),
      true,
    );
    await expectLater(
      aftersales.apply(
        sub.id,
        AfterSaleInput(
          type: 'REFUND_ONLY',
          reason_code: 'DAMAGED',
          reason_text: 'CI REAL 超量申请',
          items: [
            AfterSaleItemInput(order_item_id: sub.items.single.id, quantity: 1),
          ],
          evidence: const [],
        ),
        checkoutCommandKey(),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.code,
          'code',
          'AFTERSALE_QUANTITY_EXCEEDED',
        ),
      ),
      reason: 'Shipped units already claimed by the approved after-sale',
    );
    await checkout.removeAddress(address, checkoutCommandKey());
    expect((await checkout.cart()).items.isEmpty, true);
    final latest = (await pets.list()).firstWhere((p) => p.id == pet.id);
    await pets.delete(latest, newPetCommandKey());
    expect((await pets.list()).any((p) => p.id == pet.id), false);
    final support = SupportRepository(restored);
    final conversation = await support.create();
    final messageKey = checkoutCommandKey();
    final textMessage = SupportMessageInput(
      type: 'TEXT',
      body: 'CI REAL Dart private support',
      asset_ids: const [],
      target_id: null,
    );
    final sent = await support.send(conversation.id, textMessage, messageKey);
    expect(
      (await support.send(conversation.id, textMessage, messageKey)).id,
      sent.id,
    );
    final chatImage = await support.upload(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
        ),
      ),
      'image/png',
    );
    final imageMessage = await support.send(
      conversation.id,
      SupportMessageInput(
        type: 'IMAGE',
        body: null,
        asset_ids: [chatImage.asset_id],
        target_id: null,
      ),
      checkoutCommandKey(),
    );
    expect(
      (await support.image(imageMessage.media.single.content_url)).length,
      greaterThan(0),
    );
    final history = await support.messages(conversation.id, 0);
    expect(history.data.map((m) => m.sequence).toList(), [1, 2]);
    expect((await support.read(conversation.id, 2)).unread_count, 0);
    await support.preference('FOOD_REMINDER', false);
    expect(
      (await support.preferences())
          .firstWhere((p) => p.category == 'FOOD_REMINDER')
          .enabled,
      false,
    );
    expect(
      (await support.preferences())
          .firstWhere((p) => p.category == 'ORDER')
          .enabled,
      true,
    );
    final closed = await support.status(
      await support.detail(conversation.id),
      'CLOSED',
    );
    expect(closed.status, 'CLOSED');
    expect((await support.status(closed, 'OPEN')).status, 'OPEN');
    await restored.logout();
    expect(restored.authenticated, false);
    expect(vault.values['consumer.session'], isNull);
    restored.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
  test(
    'real guest nearby facts, GPS distance and AMap handoff contract',
    () async {
      final base = Platform.environment['PAWDAY_REAL_API_BASE'];
      if (base == null) throw StateError('Real backend is mandatory');
      final api = ConsumerApi(
        base: Uri.parse(base),
        transport: http.Client(),
        vault: MemoryVault(),
      );
      final nearby = NearbyRepository(api);
      final places = await nearby.places(city: 'CI-M54-CITY', category: 'VET');
      expect(places.data, isNotEmpty);
      final place = await nearby.place(places.data.first.id);
      expect(place.claim_status, 'VERIFIED');
      expect(place.pawday_certified, true);
      expect(place.services, contains('CONSULTATION'));
      final distances = await nearby.places(
        position: const Coordinates(121.5, 31.2),
        category: 'VET',
      );
      expect(distances.data.first.distance_m, 0);
      final intent = await nearby.navigation(place.id);
      expect(intent.coordinate_system, 'WGS84');
      expect(NavigationLauncher.safe(Uri.parse(intent.launch_url), '1'), true);
      expect(
        NavigationLauncher.safe(Uri.parse(intent.fallback_url), '0'),
        true,
      );
      expect(api.authenticated, false);
      api.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
