import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/lan_address_recovery.dart';

void main() {
  test(
    'LAN recovery scans only the active Wi-Fi subnet and returns SSH hosts',
    () async {
      final probes = <String>[];
      final recovery = LanAddressRecovery(
        invoke: (_) async => '''
        {"wifi":true,"defaultInterface":"wlan0","interfaces":[
          {"name":"wlan0","addresses":["192.168.1.20/24"]}
        ]}
      ''',
        probeSsh: (host, port) async {
          expect(port, 22);
          probes.add(host);
          return host == '192.168.1.6';
        },
      );

      final hosts = await recovery.sshCandidates(limit: 1);

      expect(hosts, ['192.168.1.6']);
      expect(probes, isNotEmpty);
      expect(probes, everyElement(startsWith('192.168.1.')));
      expect(probes, isNot(contains('192.168.1.20')));
    },
  );

  test(
    'LAN recovery asks for Wi-Fi instead of scanning other transports',
    () async {
      final recovery = LanAddressRecovery(
        invoke: (_) async =>
            '{"wifi":false,"defaultInterface":"rmnet_data0","interfaces":[]}',
        probeSsh: (_, _) async => fail('Must not probe on mobile data'),
      );

      await expectLater(
        recovery.sshCandidates(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Wi-Fi'),
          ),
        ),
      );
    },
  );
}
