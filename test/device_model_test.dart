import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';

void main() {
  test('legacy devices preserve their host, and new settings survive copying and storage', () {
    final legacy = Device.fromJson({
      'id': 'pc',
      'name': 'PC',
      'host': '100.64.0.1',
      'port': 22,
      'username': 'test',
      'commands': [],
    });
    expect(legacy.localHost, '');
    expect(legacy.refreshSeconds, 20);
    final updated = legacy.copyWith(
      localHost: '192.168.1.2',
      refreshSeconds: 60,
    );
    final restored = Device.fromJson(
      updated.copyWith(name: 'Renamed').toJson(),
    );
    expect(restored.localHost, '192.168.1.2');
    expect(restored.host, legacy.host);
    expect(restored.refreshSeconds, 60);
  });
}
