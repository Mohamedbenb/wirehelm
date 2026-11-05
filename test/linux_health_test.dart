import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/commands/default_commands.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/linux_health_screen.dart';
import 'package:remote_control/services/linux_health.dart';
import 'package:remote_control/ssh/ssh_session.dart';

const _report = '''
__RC_LINUX_HEALTH__\tgateway\t192.168.1.1
__RC_LINUX_HEALTH__\tadapter\twlan0
__RC_LINUX_HEALTH__\tlocal_ip\t192.168.1.20
__RC_LINUX_HEALTH__\trouter\treachable
__RC_LINUX_HEALTH__\tdns\treachable
__RC_LINUX_HEALTH__\tinternet\treachable
__RC_LINUX_HEALTH__\tpc_host\t192.168.1.30
__RC_LINUX_HEALTH__\tpc_ip\t192.168.1.30
__RC_LINUX_HEALTH__\tpc_route\twlan0 · 192.168.1.20
__RC_LINUX_HEALTH__\tpc_ping\tno_ping_reply
__RC_LINUX_HEALTH__\tpc_ssh\treachable
__RC_LINUX_HEALTH__\tpc_broadcast\t192.168.1.255
__RC_LINUX_HEALTH__\twol_tool\tinstalled
__RC_LINUX_HEALTH__\tcpu_temp\t52.4
__RC_LINUX_HEALTH__\tthrottled\t0x0
__RC_LINUX_HEALTH__\tmemory_free\t512 MiB
__RC_LINUX_HEALTH__\tdisk\t100000 KiB free · 40% used
__RC_LINUX_HEALTH__\tdisk_used\t40
__RC_LINUX_HEALTH__\tuptime\tup 2 days
__RC_LINUX_HEALTH__\ttool_ffmpeg\tyes
__RC_LINUX_HEALTH__\ttool_scrot\tyes
__RC_LINUX_HEALTH__\ttool_grim\tno
__RC_LINUX_HEALTH__\ttool_gnome-screenshot\tno
__RC_LINUX_HEALTH__\ttool_bluetoothctl\tyes
__RC_LINUX_HEALTH__\ttool_nmcli\tyes
__RC_LINUX_HEALTH__\ttool_lsusb\tyes
__RC_LINUX_HEALTH__\ttool_wakeonlan\tyes
__RC_LINUX_HEALTH__\ttool_etherwake\tno
__RC_LINUX_HEALTH__\tvideo_access\tavailable
__RC_LINUX_HEALTH__\taudio_access\tavailable
''';

class ConnectedPiSession extends SshSession {
  final String response;
  String? lastCommand;

  ConnectedPiSession(this.response);

  @override
  bool get isConnected => true;

  @override
  String? get deviceId => 'pi';

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    lastCommand = command;
    return Uint8List.fromList(utf8.encode(response));
  }
}

void main() {
  test('Linux health parses route results and Pi warning bits', () {
    final report = parseLinuxHealth(_report);
    expect(report.value('gateway'), '192.168.1.1');
    expect(report.value('pc_ssh'), 'reachable');
    expect(report.value('throttled'), '0x0');
    expect(report.hasUndervoltage, isFalse);
    expect(report.hasThrottling, isFalse);
    expect(
      parseLinuxHealth('''$_report
__RC_LINUX_HEALTH__\tthrottled\t0x50001
''').hasUndervoltage,
      isTrue,
    );
    expect(
      parseLinuxHealth('''$_report
__RC_LINUX_HEALTH__\tthrottled\t0x50001
''').hasThrottling,
      isTrue,
    );
  });

  test('Linux health script safely passes selected PC details', () {
    const unsafeHost = "desktop'; touch /tmp/should-not-run; #";
    final script = buildLinuxHealthScript(
      peerHost: unsafeHost,
      peerPort: 65535,
    );
    expect(script, contains(base64Encode(utf8.encode(unsafeHost))));
    expect(script, contains('pc_port=65535'));
    expect(script, isNot(contains(unsafeHost)));
  });

  test('Linux health command is valid shell syntax', () async {
    final bash = Platform.isWindows
        ? r'C:\Program Files\Git\bin\bash.exe'
        : '/bin/bash';
    if (!File(bash).existsSync()) return;
    final process = await Process.start(bash, ['--noprofile', '--norc', '-n']);
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(
      buildLinuxHealthScript(peerHost: '192.168.1.30', peerPort: 22),
    );
    await process.stdin.close();
    expect(await process.exitCode, 0, reason: await errors);
  });

  testWidgets('Pi health view fits a compact phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = ConnectedPiSession(_report);
    await tester.pumpWidget(
      MaterialApp(
        home: LinuxHealthScreen(
          device: Device(
            id: 'pi',
            name: 'Raspberry Pi',
            host: '100.64.0.20',
            localHost: '192.168.1.20',
            port: 22,
            username: 'pi',
            shellStyle: 'linux',
            commands: linuxDefaultCommands,
          ),
          session: session,
          peerDevices: const [
            Device(
              id: 'pc',
              name: 'Desktop',
              host: '100.64.0.30',
              localHost: '192.168.1.30',
              port: 22,
              username: 'Mohamed',
              shellStyle: 'windows',
              commands: windowsDefaultCommands,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Network & Pi health'), findsOneWidget);
    expect(find.text('Router response'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PC access'), 220);
    expect(find.text('PC access'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pi health'), 220);
    expect(find.text('Pi health'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Remote capabilities'), 220);
    expect(find.text('Remote capabilities'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(session.lastCommand, contains('pc_port=22'));
    session.dispose();
  });
}
