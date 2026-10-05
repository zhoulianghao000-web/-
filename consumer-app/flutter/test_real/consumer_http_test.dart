import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawday_consumer/api/client.dart';
import 'package:pawday_consumer/pet_repository.dart';
import 'package:pawday_consumer/catalog_repository.dart';
import 'package:pawday_consumer/checkout_repository.dart';
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
    await checkout.remove(currentItem, checkoutCommandKey());
    await checkout.removeAddress(address, checkoutCommandKey());
    expect((await checkout.cart()).items.isEmpty, true);
    final latest = (await pets.list()).firstWhere((p) => p.id == pet.id);
    await pets.delete(latest, newPetCommandKey());
    expect((await pets.list()).any((p) => p.id == pet.id), false);
    await restored.logout();
    expect(restored.authenticated, false);
    expect(vault.values['consumer.session'], isNull);
    restored.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
