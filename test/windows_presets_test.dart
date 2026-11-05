import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/commands/default_commands.dart';
import 'package:remote_control/devices/identity_installer.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class CapturingSession extends SshSession {
  String script = '';
  @override
  bool get isConnected => true;
  @override
  String get deviceId => 'pc';
  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    expect(command.length, lessThan(2000));
    script = utf8.decode(base64Decode(utf8.decode(input!).trim()));
    return Uint8List.fromList(
      utf8.encode(
        '__REMOTE_CONTROL_IDENTITY_INSTALLED__\n__REMOTE_CONTROL_IDENTITY_TARGET__test',
      ),
    );
  }
}

Future<void> parsePowerShell(String script) async {
  final directory = await Directory.systemTemp.createTemp(
    'remote_control_parser_',
  );
  try {
    final file = File('${directory.path}/script.ps1');
    await file.writeAsString(script);
    final command =
        "\$t=\$null; \$e=\$null; [void][Management.Automation.Language.Parser]::ParseFile('${file.path.replaceAll("'", "''")}',[ref]\$t,[ref]\$e); if(\$e.Count){\$e | ForEach-Object { [Console]::Error.WriteLine(\$_.Message) }; exit 1}";
    final encoded = base64Encode(
      command.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
    );
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]).timeout(const Duration(seconds: 10));
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  } finally {
    await directory.delete(recursive: true);
  }
}

void main() {
  test(
    'Windows Sleep requests suspend with confirmation and desktop execution',
    () async {
      final sleep = windowsDefaultCommands.singleWhere(
        (c) => c.id == 'windows_sleep',
      );
      expect(sleep.requiresConfirmation, true);
      expect(sleep.executionMode, 'interactive');
      expect(sleep.command, contains('PowerState]::Suspend, \$false, \$false'));
      if (Platform.isWindows) await parsePowerShell(sleep.command);
    },
  );
  test('Windows presets keep switches, targets and status when added', () {
    for (final template in windowsDefaultCommands.where((c) => c.isStateful)) {
      final added = commandFromTemplate(template);
      expect(added.stateful?.toJson(), template.stateful?.toJson());
      expect(added.hasStateCheck, true);
    }
    expect(
      windowsDefaultCommands
          .firstWhere((c) => c.id == 'windows_network_adapter')
          .stateful!
          .target!
          .value,
      'Ethernet',
    );
  });
  test(
    'generated identity and Windows status scripts parse in Windows PowerShell',
    () async {
      final session = CapturingSession();
      final result = await IdentityInstaller().install(
        device: const Device(
          id: 'pc',
          name: 'PC',
          host: 'localhost',
          port: 22,
          username: 'test',
          shellStyle: 'windows',
          commands: [],
        ),
        publicKey: "ssh-ed25519 AAAATEST user's phone",
        session: session,
      );
      expect(result.target, 'test');
      await parsePowerShell(session.script);
      for (final template in windowsDefaultCommands.where(
        (c) => c.isStateful,
      )) {
        await parsePowerShell(template.stateful!.statusCommand!);
        for (final state in template.stateful!.states) {
          await parsePowerShell(state.command);
        }
      }
    },
    skip: !Platform.isWindows,
  );
}
