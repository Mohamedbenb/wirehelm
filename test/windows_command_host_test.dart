import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:remote_control/ssh/windows_command_host.dart';
import 'package:remote_control/commands/windows_status_scripts.dart';
import 'package:remote_control/services/windows_text_size.dart';

void main() {
  test(
    'Windows helper binds locally, protects its temp area and bounds tasks',
    () {
      final broker = commandHostBroker(
        true,
        port: 50001,
        secret: '0123456789abcdef0123456789abcdef',
      );
      expect(broker, contains('[Net.IPAddress]::Loopback'));
      expect(broker, contains('icacls.exe'));
      expect(broker, contains('S-1-5-18'));
      expect(windowsTempArtifactCleanup, contains('AddHours(-24)'));
      expect(broker, contains('ExecutionTimeLimit (New-TimeSpan -Minutes 10)'));
      expect(
        broker,
        contains(r'Remove-Item -LiteralPath $root -Recurse -Force'),
      );
      expect(commandHostWorker, contains(r'& ([ScriptBlock]::Create($text))'));
    },
  );

  for (final desktop in [false, true]) {
    test('real ${desktop ? 'desktop' : 'standard'} worker reuses process and compiled types', () async {
      final script = commandHostBroker(desktop);
      const bootstrap =
          r"$s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))))";
      final source = desktop ? bootstrap : script;
      final encoded = base64Encode(
        source.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
      );
      if (!desktop) expect(encoded.length + 100, lessThan(8191));
      final process = await Process.start('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encoded,
      ]);
      final ready = Completer<List<String>>();
      final replies = <int, Completer<Map>>{};
      final errors = StringBuffer();
      final err = process.stderr.transform(utf8.decoder).listen((e) {
        errors.write(e);
      });
      final out = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('__NC_READY__') && !ready.isCompleted) {
              ready.complete(line.substring(12).split(':'));
            }
            if (line.startsWith('__NC_REPLY__')) {
              final row = jsonDecode(
                utf8.decode(base64Decode(line.substring(12))),
              ) as Map;
              replies[row['id']]?.complete(row);
            }
          });
      try {
        if (desktop) {
          process.stdin.add(
            utf8.encode('${base64Encode(utf8.encode(script))}\n'),
          );
        }
        unawaited(process.stdin.close());
        final endpoint = await ready.future.timeout(
          const Duration(seconds: 15),
        );
        final socket = await Socket.connect(
          '127.0.0.1',
          int.parse(endpoint[0]),
        );
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final row = jsonDecode(
                utf8.decode(base64Decode(line.substring(12))),
              ) as Map;
              replies[row['id']]?.complete(row);
            });
        final pids = <String>[];
        for (var id = 1; id <= 3; id++) {
          final result = Completer<Map>();
          replies[id] = result;
          final scopeProbe = id == 1
              ? r"$NodeCockpitRequestScope = 'private-to-request'; "
              : '';
          final code = cacheWindowsTypes(
            "${desktop ? '$windowsDisplayStatus\n$windowsScreenStatus\n$windowsTextSizeStatus\n' : 'Get-NetAdapter -ErrorAction Stop | Out-Null; if (-not \$global:NCNetAdapterLoaded) { throw \'Module was not retained\' }; '}$scopeProbe"
            "Add-Type -TypeDefinition 'public class NodeCockpitTestType { public static int Get() { return 42; } }'; [NodeCockpitTestType]::Get(); \$PID; [Diagnostics.Process]::GetCurrentProcess().SessionId; "
            "if (Get-Variable NodeCockpitRequestScope -ErrorAction SilentlyContinue) { 'scope-leaked' } else { 'scope-isolated' }",
          );
          final request = base64Encode(
            utf8.encode(
              jsonEncode({
                'id': id,
                'token': endpoint[1],
                'script': base64Encode(utf8.encode(code)),
              }),
            ),
          );
          final clock = Stopwatch()..start();
          socket.add(utf8.encode('$request\r\n'));
          final row = await result.future.timeout(const Duration(seconds: 30));
          expect(row['error'], isNull, reason: '$row\n$errors');
          expect(row['executionMs'], isA<num>());
          expect(row['executionMs'], greaterThanOrEqualTo(0));
          expect(
            row['value'],
            contains(id == 1 ? 'scope-leaked' : 'scope-isolated'),
          );
          final lines = const LineSplitter().convert(
            (row['value'] as String).trim(),
          );
          expect(lines[lines.length - 4], '42');
          pids.add(lines[lines.length - 3]);
          if (desktop) {
            expect(int.parse(lines[lines.length - 2]), greaterThan(0));
            expect(
              lines.first,
              isIn(['internal', 'duplicate', 'extend', 'external', 'unknown']),
            );
            expect(lines[1], isIn(['awake', 'sleeping', 'unknown']));
            expect(int.parse(lines[2]), inInclusiveRange(100, 225));
          }
          // Timings are evidence for warm-process execution, not a mobile benchmark.
          debugPrint(
            '${desktop ? 'Desktop' : 'Standard'} request $id: ${clock.elapsedMilliseconds} ms',
          );
        }
        expect(pids.toSet(), hasLength(1));
        await socket.close();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          0,
          reason: '$errors',
        );
      } finally {
        process.kill();
        await out.cancel();
        await err.cancel();
      }
    }, skip: !Platform.isWindows);
  }
}
