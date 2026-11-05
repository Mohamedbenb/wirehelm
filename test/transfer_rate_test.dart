import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/transfer_rate.dart';

void main() {
  test('rate reflects recent throughput and reaches zero during a stall', () {
    final rate = TransferRate();
    rate.sample(0, Duration.zero);
    expect(rate.sample(1000, const Duration(seconds: 1)), 1000);
    expect(rate.sample(2000, const Duration(seconds: 2)), 1000);
    rate.sample(2000, const Duration(seconds: 3));
    rate.sample(2000, const Duration(seconds: 4));
    expect(rate.sample(2000, const Duration(seconds: 5)), 0);
    expect(
      rate.idleFor(const Duration(seconds: 5)),
      const Duration(seconds: 3),
    );
    expect(rate.sample(5000, const Duration(seconds: 6)), 1000);
    rate.reset();
    rate.sample(0, Duration.zero);
    expect(rate.sample(4000, const Duration(seconds: 1)), 4000);
  });
}
