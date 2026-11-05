import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/device_discovery.dart';
import 'package:remote_control/services/device_information.dart';
import 'package:remote_control/commands/default_commands.dart';
import 'package:remote_control/utils/command_parameters.dart';

void main() {
  test(
    'own phone identities are filtered without hiding other Android peers',
    () {
      final info = {'deviceName': "Mohamed's A36", 'model': 'SM-A366B'};
      expect(
        isOwnPhonePeer({'name': "Mohamed's A36", 'os': 'android'}, info),
        true,
      );
      expect(
        isOwnPhonePeer({
          'name': 'remote-control-a36-test',
          'os': 'android',
        }, info),
        true,
      );
      expect(
        isOwnPhonePeer({'name': 'Another phone', 'os': 'android'}, info),
        false,
      );
    },
  );
  test('discovery rejects this phone addresses and retains remote hosts', () {
    final discovery = DeviceDiscovery(() {});
    discovery.ownAddresses.addAll(
      localDeviceAddresses({
        'interfaces': [
          {
            'addresses': ['192.168.1.197/24', 'fe80::123/64'],
          },
          {
            'addresses': ['100.64.0.1/32'],
          },
        ],
      }),
    );
    for (final host in [
      '192.168.1.197',
      'fe80::123',
      '100.64.0.1',
      '192.168.1.178',
    ]) {
      discovery.add(DiscoveredDevice(name: host, host: host, source: 'LAN'));
    }
    expect(discovery.devices.map((d) => d.host), ['192.168.1.178']);
  });
  test('LAN scan stays in active Wi-Fi segment, excludes self and caps large subnets', () {
    Map<String, dynamic> network(String address, {bool wifi = true}) => {
      'wifi': wifi,
      'defaultInterface': 'wlan0',
      'interfaces': [
        {
          'name': 'wlan0',
          'addresses': [address],
        },
        {
          'name': 'mobile',
          'addresses': ['10.1.0.2/8'],
        },
      ],
    };
    final hosts = localScanHosts(network('192.168.1.20/16'));
    expect(hosts.length, 253);
    expect(hosts, isNot(contains('192.168.1.20')));
    expect(hosts.every((h) => h.startsWith('192.168.1.')), true);
    expect(localScanHosts(network('192.168.1.1/30')), ['192.168.1.2']);
    expect(localScanHosts(network('10.0.0.2/24', wifi: false)), isEmpty);
    expect(localScanHosts(network('fe80::1/64')), isEmpty);
  });

  test(
    'Linux information retains multiple MAC addresses and absent IP values',
    () {
      final data = parseDeviceInformation(
        'noise\n__RC_INFO__\thostname\tpi\n__RC_INFO__\tos\tLinux\n__RC_NIC__\teth0\taa:bb:cc:dd:ee:ff\tup\t192.168.1.2/24\tyes\n__RC_NIC__\twlan0\t11:22:33:44:55:66\tdown\t\tno\n__RC_BT__\tPhone\n__RC_PERIPHERAL__\tUSB keyboard\n',
      );
      expect(data.system['hostname'], 'pi');
      expect(data.adapters.length, 2);
      expect(data.adapters[0]['mac'], 'aa:bb:cc:dd:ee:ff');
      expect(data.adapters[1]['ips'], '');
      expect(data.adapters.first['internet'], 'true');
      expect(data.bluetoothDevices, ['Phone']);
      expect(data.peripherals, ['USB keyboard']);
    },
  );

  test('Windows JSON information and missing output are handled explicitly', () {
    final data = parseDeviceInformation(
      '__RC_INFORMATION_JSON__${jsonEncode({
        'system': {'hostname': 'PC', 'memory': '16 GiB'},
        'adapters': [
          {'name': 'Ethernet', 'mac': 'AA-BB-CC-DD-EE-FF', 'status': 'Disabled', 'ips': null, 'internet': true},
        ],
        'bluetoothDevices': ['Bluetooth headset'],
        'peripherals': ['USB mouse'],
      })}',
    );
    expect(data.adapters.single['mac'], 'AA-BB-CC-DD-EE-FF');
    expect(data.adapters.single['ips'], '');
    expect(data.adapters.single['internet'], 'true');
    expect(data.bluetoothDevices, ['Bluetooth headset']);
    expect(data.peripherals, ['USB mouse']);
    expect(() => parseDeviceInformation('permission denied'), throwsStateError);
  });

  test(
    'Linux templates have explicit resolved parameters and bounded ping',
    () {
      for (final command in linuxDefaultCommands) {
        expect(unknownCommandParameters(command), isEmpty);
      }
      final ping = linuxDefaultCommands.firstWhere((c) => c.id == 'linux_ping');
      expect(ping.command, contains('ping -c {{param:count}}'));
      expect(
        ping.parameters.firstWhere((p) => p.key == 'count').required,
        true,
      );
      final suspend = linuxDefaultCommands.firstWhere(
        (c) => c.id == 'linux_suspend',
      );
      expect(suspend.requiresSudo && suspend.requiresConfirmation, true);
    },
  );

  test(
    'Windows information script runs read-only and reports adapters',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'node_cockpit_information_',
      );
      try {
        final file = File('${folder.path}/information.ps1');
        await file.writeAsBytes([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(windowsInformationScript),
        ]);
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            file.path,
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(const Duration(seconds: 25));
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final data = parseDeviceInformation(result.stdout as String);
        expect(data.system['hostname'], isNotEmpty);
        expect(data.adapters, isNotEmpty);
        expect(data.adapters.any((a) => a['mac']?.isNotEmpty == true), true);
      } finally {
        await folder.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
