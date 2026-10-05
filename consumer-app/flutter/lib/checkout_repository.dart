import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

String checkoutCommandKey() => const Uuid().v4();

class CheckoutRepository {
  final ConsumerApi api;
  CheckoutRepository(this.api);
  Future<CheckoutBenefits> benefits() async =>
      CheckoutBenefitsEnvelope.fromJson(
        await api.request('GET', '/consumer/checkout/benefits'),
      ).data;
  Future<Cart> cart() async =>
      CartEnvelope.fromJson(await api.request('GET', '/consumer/cart')).data;
  Future<CartItem> add(
    String offer,
    int quantity,
    String? pet,
    String key,
  ) async => CartItemEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/cart/items',
      body: CartAddInput(
        offer_id: offer,
        quantity: quantity,
        pet_id: pet,
      ).toJson(),
      idempotencyKey: key,
    ),
  ).data;
  Future<CartItem> quantity(CartItem item, int value, String key) async =>
      CartItemEnvelope.fromJson(
        await api.request(
          'PATCH',
          '/consumer/cart/items/${item.id}',
          body: {'quantity': value},
          version: item.version,
          idempotencyKey: key,
        ),
      ).data;
  Future<void> remove(CartItem item, String key) async {
    await api.request(
      'DELETE',
      '/consumer/cart/items/${item.id}',
      version: item.version,
      idempotencyKey: key,
    );
  }

  Future<Cart> merge(List<CartAddInput> items, String key) async =>
      CartEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/cart/merge-guest-intent',
          body: {'items': items.map((i) => i.toJson()).toList()},
          idempotencyKey: key,
        ),
      ).data;
  Future<List<CheckoutAddress>> addresses() async =>
      CheckoutAddressListEnvelope.fromJson(
        await api.request('GET', '/consumer/addresses'),
      ).data;
  Future<CheckoutAddress> saveAddress(
    CheckoutAddressInput input,
    String key, {
    CheckoutAddress? previous,
  }) async => CheckoutAddressEnvelope.fromJson(
    await api.request(
      previous == null ? 'POST' : 'PATCH',
      previous == null
          ? '/consumer/addresses'
          : '/consumer/addresses/${previous.id}',
      body: input.toJson(),
      version: previous?.version,
      idempotencyKey: key,
    ),
  ).data;
  Future<void> removeAddress(CheckoutAddress address, String key) async {
    await api.request(
      'DELETE',
      '/consumer/addresses/${address.id}',
      version: address.version,
      idempotencyKey: key,
    );
  }

  Future<PricingQuote> quote(
    List<String> items,
    String address,
    String key, {
    List<String> coupons = const [],
    bool membership = false,
  }) async => PricingQuoteEnvelope.fromJson(
    await api.request(
      'POST',
      '/consumer/checkout/quotes',
      body: QuoteInput(
        cart_item_ids: items,
        address_id: address,
        coupon_ids: coupons,
        use_membership: membership,
      ).toJson(),
      idempotencyKey: key,
    ),
  ).data;
  Future<PricingQuote> getQuote(String id) async =>
      PricingQuoteEnvelope.fromJson(
        await api.request('GET', '/consumer/checkout/quotes/$id'),
      ).data;
}

final checkoutRepositoryProvider = Provider(
  (ref) => CheckoutRepository(ref.watch(consumerApiProvider)),
);

class GuestCartIntent {
  final List<CartAddInput> items;
  final String key;
  final String? mergingUser;
  GuestCartIntent(this.items, this.key, [this.mergingUser]);
}

class GuestCartNotifier extends Notifier<GuestCartIntent> {
  @override
  GuestCartIntent build() => GuestCartIntent([], checkoutCommandKey());
  void add(String offer) {
    state = GuestCartIntent([
      ...state.items,
      CartAddInput(offer_id: offer, quantity: 1),
    ], checkoutCommandKey());
  }

  void begin(String user) {
    if (state.mergingUser != null && state.mergingUser != user) {
      clear();
      return;
    }
    state = GuestCartIntent(state.items, state.key, user);
  }

  void clear() {
    state = GuestCartIntent([], checkoutCommandKey());
  }
}

final guestCartProvider = NotifierProvider<GuestCartNotifier, GuestCartIntent>(
  GuestCartNotifier.new,
);

String checkoutError(Object error) => error is ApiFailure
    ? '${const {'PAYMENT_CONFIRMATION_PENDING': '支付结果仍不确定，请先查询；库存和优惠券预占会继续保留', 'PAYMENT_NOT_PAYABLE': '当前支付单不能再次发起，请刷新状态', 'PAYMENT_PROVIDER_UNAVAILABLE': '支付渠道尚未配置', 'PAYMENT_WINDOW_EXPIRED': '付款期限已到，请查询订单关闭结果', 'QUOTE_ALREADY_CONSUMED': '此试算已创建订单，请查看我的订单', 'QUOTE_INVALIDATED': '试算依据已变化，请重新确认', 'QUOTE_EXPIRED': '试算已过期，请重新确认', 'ORDER_NOT_CANCELLABLE': '此订单当前无法取消，请刷新', 'SHIPPING_RULE_REQUIRED': '商家暂未配置配送规则，当前无法试算', 'ADDRESS_OUTSIDE_DELIVERY_AREA': '此地址不在商家配送范围内', 'INSUFFICIENT_STOCK': '库存不足，请调整数量', 'RESOURCE_NOT_FOUND': '商品或资料已失效，请刷新', 'CONCURRENT_MODIFICATION': '资料已变化，请刷新后确认', 'COUPON_STACKING_CONFLICT': '选择的优惠券不能同时使用', 'COUPON_NOT_ELIGIBLE': '优惠券不符合使用条件', 'MEMBERSHIP_NOT_ELIGIBLE': '当前会员资格不可用', 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD': '请求内容已改变，请重新确认'}[error.code] ?? '操作未完成，请重试'}${error.requestId.isEmpty ? '' : ' · 请求编号 ${error.requestId}'}'
    : '暂时无法完成操作，请重试';
