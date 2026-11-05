import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/bluetooth_devices.dart';

void main() {
  test(
    'Windows discovery timestamps survive parsing without inventing proximity',
    () {
      final found = BluetoothDeviceInfo.fromMap({
        'id': 'x',
        'seenAt': '2026-10-09T01:00:00Z',
      });
      expect(found.seenAt, DateTime.utc(2026, 10, 9, 1));
      expect(BluetoothDeviceInfo.fromMap({'id': 'old'}).seenAt, isNull);
    },
  );

  test('parses Linux Bluetooth, signal, battery, and audio values', () {
    String encoded(String value) => base64Encode(utf8.encode(value));
    final snapshot = parseLinuxBluetoothSnapshot(
      [
        '__RC_BT_STATE__\t${encoded('hci0')}\tyes',
        '__RC_BT_VOLUME__\t42\t${encoded('Pi audio output')}',
        '__RC_BT_DEVICE__\tAA:BB:CC:DD:EE:FF\t${encoded('Headphones')}\t${encoded('audio-headset')}\tyes\tyes\tyes\t-48\t87',
      ].join('\n'),
    );

    expect(snapshot.available, isTrue);
    expect(snapshot.powered, isTrue);
    expect(snapshot.adapter, 'hci0');
    expect(snapshot.outputVolume, 42);
    expect(snapshot.outputName, 'Pi audio output');
    expect(snapshot.devices.single.name, 'Headphones');
    expect(snapshot.devices.single.kind, 'audio-headset');
    expect(snapshot.devices.single.paired, isTrue);
    expect(snapshot.devices.single.trusted, isTrue);
    expect(snapshot.devices.single.connected, isTrue);
    expect(snapshot.devices.single.signal, -48);
    expect(snapshot.devices.single.battery, 87);
  });

  test('parses Windows Bluetooth JSON and absent optional fields', () {
    final snapshot = parseWindowsBluetoothSnapshot(
      '__RC_BT_JSON__${jsonEncode({
        'available': true,
        'adapter': 'Bluetooth Radio',
        'powered': true,
        'outputVolume': 61,
        'outputName': 'Windows default audio output',
        'devices': [
          {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'Wireless mouse', 'kind': 'Peripheral', 'paired': true, 'trusted': true, 'connected': false, 'signal': null, 'battery': null},
        ],
      })}',
    );

    expect(snapshot.available, isTrue);
    expect(snapshot.devices.single.name, 'Wireless mouse');
    expect(snapshot.devices.single.paired, isTrue);
    expect(snapshot.devices.single.signal, isNull);
    expect(snapshot.devices.single.battery, isNull);
    expect(snapshot.outputVolume, 61);
  });

  test('available, paired disconnected, and connected devices expose valid actions', () {
    BluetoothDeviceInfo device({bool paired = false, bool connected = false}) =>
        BluetoothDeviceInfo.fromMap({
          'id': 'AA:BB:CC:DD:EE:FF',
          'paired': paired,
          'connected': connected,
        });
    expect(device().canPair, isTrue);
    expect(device().canDisconnect, isFalse);
    expect(device().canConnect, isFalse);
    expect(device(paired: true).canPair, isFalse);
    expect(device(paired: true).canConnect, isTrue);
    expect(device(paired: true).canDisconnect, isFalse);
    expect(device(paired: true, connected: true).canPair, isFalse);
    expect(device(paired: true, connected: true).canConnect, isFalse);
    expect(device(paired: true, connected: true).canDisconnect, isTrue);
    expect(device(connected: true).canPair, isFalse);
    expect(BluetoothDeviceInfo.fromMap({'remembered': true}).paired, isTrue);
  });

  test('Bluetooth backends expose the requested platform operations', () {
    expect(linuxBluetoothScript, isNot(contains('scan off')));
    expect(
      linuxBluetoothPairCommand,
      contains('--agent NoInputNoOutput --timeout 25 pair'),
    );
    expect(linuxBluetoothScript, contains('Battery Percentage'));
    expect(windowsBluetoothScript, contains('BluetoothFindFirstDevice'));
    expect(windowsBluetoothScript, contains('BluetoothAuthenticateDevice'));
    expect(windowsBluetoothScript, contains('BluetoothRemoveDevice'));
    expect(windowsBluetoothScript, contains(r'$level -ge 1'));
    expect(windowsBluetoothScript, contains(r"$property.Type -ne 'Empty'"));
    expect(windowsBluetoothScript, contains('NcIAudioEndpointVolume'));
    expect(windowsBluetoothScript, contains('SetMasterVolumeLevelScalar'));
    expect(windowsBluetoothScript, isNot(contains('waveOutGetVolume')));
    expect(windowsBluetoothScript, contains('ms-settings:bluetooth'));
  });

  test(
    'Windows Bluetooth native backend compiles and returns a snapshot',
    () async {
      final script =
          windowsBluetoothScript
              .replaceAll('__OPERATION__', 'list')
              .replaceAll('__ADDRESS__', '')
              .replaceAll('__PASSKEY__', '') +
          windowsAudioPairingScript
              .replaceAll('__ADDRESS__', '00:00:00:00:00:00')
              .replaceAll(
                r"[NcModernAudioPairV42]::Start($address,('__OPERATION__' -eq 'repair'))",
                "if ([NcModernAudioPairV42]::Status() -ne 'done|0||0') { throw 'Unexpected initial pairing state' }",
              ) +
          r'''
$type=[NcBluetoothApiV46]
[NcBluetoothApiV46]::AudioFilters() | Out-Null
$ks=$type.GetNestedType('KsProperty',[Reflection.BindingFlags]::NonPublic)
if([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($ks)) -ne 24){throw 'Invalid KS property ABI'}
$response=$type.GetNestedType('AuthResponse',[Reflection.BindingFlags]::NonPublic)
if([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($response)) -ne 48){throw 'Invalid authentication response ABI'}
if([Runtime.InteropServices.Marshal]::OffsetOf($response,'negative').ToInt32() -ne 44){throw 'Invalid authentication response offset'}
$params=$type.GetNestedType('AuthParams',[Reflection.BindingFlags]::NonPublic)
if([Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($params)) -ne 576){throw 'Invalid authentication callback ABI'}
''';
      final directory = await Directory.systemTemp.createTemp(
        'node-cockpit-bluetooth-test-',
      );
      try {
        final file = File('${directory.path}\\bluetooth.ps1');
        await file.writeAsString(script);
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            file.path,
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(const Duration(seconds: 20));
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        final snapshot = parseWindowsBluetoothSnapshot(result.stdout as String);
        expect(snapshot.adapter, isNotEmpty);
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
