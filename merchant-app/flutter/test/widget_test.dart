import 'package:flutter_test/flutter_test.dart';
import 'package:pawday_merchant/session.dart';

void main() {
  test('returnTo only accepts merchant pages', () {
    expect(safeReturnTo('/orders'), '/orders');
    expect(safeReturnTo('//evil.example'), '/dashboard');
    expect(safeReturnTo('/consumer/pets'), '/dashboard');
  });
}
