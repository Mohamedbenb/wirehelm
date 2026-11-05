import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:remote_control/screens/tailscale_screen.dart';
import 'package:remote_control/transport/tsnet_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Android tsnet starts and exposes state without a VPN service',
    (tester) async {
      expect(TsnetClient.supported, isTrue);
      await tester.pumpWidget(const MaterialApp(home: TailscaleScreen()));
      final client = TsnetClient.instance;
      await client.start().timeout(const Duration(seconds: 30));
      TsnetStatus status = await client.status();
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (status.state == 'NoState' ||
          status.state == 'Starting' ||
          status.state == 'NeedsLogin' && status.authUrl.isEmpty ||
          status.state == 'Stopped' && status.authUrl.isEmpty) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(seconds: 1));
        status = await client.status();
      }
      expect(status.state, anyOf('Running', 'NeedsLogin', 'NeedsMachineAuth'));
      if (status.state == 'NeedsLogin') {
        expect(Uri.parse(status.authUrl).host, 'login.tailscale.com');
      }
      // Do not log authentication URLs or credentials.
      debugPrint(
        'TSNET_NATIVE_SMOKE state=${status.state} addressCount=${status.ips.length}',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('native peer listing and LAN discovery return structured results', (
    tester,
  ) async {
    final peers = await TsnetClient.instance.peers();
    expect(peers, isA<List<Map<String, dynamic>>>());
    final network = jsonDecode(
      (await TsnetClient.channel.invokeMethod<String>('lanInfo'))!,
    ) as Map;
    expect(network['interfaces'], isA<List>());
    expect(network['wifi'], isA<bool>());
    final services = jsonDecode(
      (await TsnetClient.channel
          .invokeMethod<String>('discoverLan')
          .timeout(const Duration(seconds: 12)))!,
    ) as List;
    for (final service in services) {
      expect(service['host'], isA<String>());
      expect(service['port'], isA<int>());
    }
    debugPrint(
      'DISCOVERY_NATIVE_SMOKE peerCount=${peers.length} serviceCount=${services.length}',
    );
  });
}
