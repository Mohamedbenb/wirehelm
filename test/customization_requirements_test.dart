import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/feature_registry.dart';

void main() {
  test(
    'combined feature stays unavailable when recovery backend is absent',
    () {
      final available = {
        'xposed.systemuiHook',
        'xposed.remoteConfiguration',
        'device.validatedSystemUi',
      };
      expect(networkSpeedFeature.requirement.satisfied(available), false);
      available.add('root.recoveryWatchdog');
      expect(networkSpeedFeature.requirement.satisfied(available), true);
    },
  );
  test('alternative providers do not bypass other mandatory requirements', () {
    const r = AllOf([
      AnyOf([Capability('provider.a'), Capability('provider.b')]),
      Capability('safe.config'),
    ]);
    expect(r.satisfied({'provider.b'}), false);
    expect(r.satisfied({'provider.b', 'safe.config'}), true);
  });
  test('carrier profile requires both the root backend and a supported SIM', () {
    expect(
      tunisia5gFeature.requirement.satisfied({'root.carrierProfileOverride'}),
      false,
    );
    expect(
      tunisia5gFeature.requirement.satisfied({
        'root.carrierProfileOverride',
        'carrier.tunisia5gSupported',
      }),
      true,
    );
  });
}
