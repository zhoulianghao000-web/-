import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'api/generated/dto.dart';
import 'repositories.dart';

class ServiceBookingRepository {
  final ConsumerApi api;
  ServiceBookingRepository(this.api);
  String page(String path, String? cursor) => Uri(
    path: path,
    queryParameters: {'limit': '20', 'cursor': ?cursor},
  ).toString();
  Future<BookingServiceListEnvelope> services(
    String store, {
    String? cursor,
  }) async => BookingServiceListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/stores/$store/booking-services', cursor),
    ),
  );
  Future<BookingSlotListEnvelope> slots(
    String service, {
    String? cursor,
  }) async => BookingSlotListEnvelope.fromJson(
    await api.request(
      'GET',
      page('/consumer/booking-services/$service/slots', cursor),
    ),
  );
  Future<ServiceBookingListEnvelope> mine({String? cursor}) async =>
      ServiceBookingListEnvelope.fromJson(
        await api.request('GET', page('/consumer/service-bookings', cursor)),
      );
  Future<ServiceBooking> reserve(String slot, String key) async =>
      ServiceBookingEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/service-bookings',
          body: ServiceBookingInput(slot_id: slot).toJson(),
          idempotencyKey: key,
        ),
      ).data;
  Future<ServiceBooking> cancel(ServiceBooking booking, String key) async =>
      ServiceBookingEnvelope.fromJson(
        await api.request(
          'POST',
          '/consumer/service-bookings/${booking.id}/cancel',
          body: const BookingEmpty().toJson(),
          idempotencyKey: key,
          version: booking.version,
        ),
      ).data;
}

final serviceBookingRepositoryProvider = Provider(
  (ref) => ServiceBookingRepository(ref.watch(consumerApiProvider)),
);
