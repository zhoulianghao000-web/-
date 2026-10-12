import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class CatalogRepository {
  final ConsumerApi api;
  CatalogRepository(this.api);
  Future<ConsumerProductListEnvelope> browse({
    String? category,
    String? cursor,
    String? query,
    Map<String, String> filters = const {},
  }) async {
    final params = <String, String>{
      ...filters,
      'pet_category': ?category,
      'cursor': ?cursor,
      if (query != null && query.isNotEmpty) 'q': query,
    };
    return ConsumerProductListEnvelope.fromJson(
      await api.request(
        'GET',
        Uri(
          path: '/public/products',
          queryParameters: params.isEmpty ? null : params,
        ).toString(),
        anonymous: true,
      ),
    );
  }

  Future<ProductSearchFacets> facets() async =>
      ProductSearchFacetsEnvelope.fromJson(
        await api.request('GET', '/public/products/facets', anonymous: true),
      ).data;
  Future<ConsumerSpu> product(String id) async => ConsumerSpuEnvelope.fromJson(
    await api.request('GET', '/public/spus/$id', anonymous: true),
  ).data;
  Future<ConsumerStandard> standard(String sku) async =>
      ConsumerStandardEnvelope.fromJson(
        await api.request('GET', '/public/skus/$sku', anonymous: true),
      ).data;
  Future<List<ConsumerOffer>> offers(String sku) async =>
      ConsumerOfferListEnvelope.fromJson(
        await api.request('GET', '/public/skus/$sku/offers', anonymous: true),
      ).data;
  Future<ProductFit> fit(String sku, String pet) async =>
      ProductFitEnvelope.fromJson(
        await api.request(
          'GET',
          '/consumer/skus/$sku/fit?pet_id=${Uri.encodeQueryComponent(pet)}',
        ),
      ).data;
  Future<ProductComparison> compare(List<String> ids, String? pet) async =>
      ProductComparisonEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/products/compare',
          body: {'sku_ids': ids, 'pet_id': ?pet},
        ),
      ).data;
}

final catalogRepositoryProvider = Provider(
  (ref) => CatalogRepository(ref.watch(consumerApiProvider)),
);
