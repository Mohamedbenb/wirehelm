import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_desktop.dart';

void main() {
  test(
    'Windows desktop transport recovers from frame-file contention and cleans up',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'node-cockpit-stream-test-',
      );
      final script = File('${root.path}/bootstrap.ps1');
      final token = 'c' * 64;
      const probe = r'''
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NcCursorProbe { [StructLayout(LayoutKind.Sequential)] public struct Point { public int X; public int Y; } [DllImport("user32.dll")] public static extern bool GetPhysicalCursorPos(out Point p); }'
$probeOriginal=[NcCursorProbe+Point]::new();[void][NcCursorProbe]::GetPhysicalCursorPos([ref]$probeOriginal)
''';
      const recordPosition = r'''
$probePosition=[NcCursorProbe+Point]::new();[void][NcCursorProbe]::GetPhysicalCursorPos([ref]$probePosition)
$probeRecord=@{x=$probePosition.X;y=$probePosition.Y;left=$bounds.Left;top=$bounds.Top;width=$bounds.Width;height=$bounds.Height;inputX=$control.x;inputY=$control.y}|ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $root 'pointer-check.json'),$probeRecord)
''';
      final worker = windowsDesktopWorkerScript
          .replaceFirst(
            r'$bounds=[NcDesktopInput]::Bounds()',
            '$probe\n\$bounds=[NcDesktopInput]::Bounds()',
          )
          .replaceFirst(
            '[NcDesktopInput]::Move(\$x,\$y)',
            '[NcDesktopInput]::Move(\$x,\$y)\n$recordPosition',
          )
          .replaceFirst(
            '[NcDesktopInput]::Release();',
            '[NcDesktopInput]::Move(\$probeOriginal.X,\$probeOriginal.Y); [NcDesktopInput]::Release();',
          );
      final bootstrap = windowsDesktopBootstrapScript(controlToken: token)
          .replaceFirst(
            base64Encode(utf8.encode(windowsDesktopWorkerScript)),
            base64Encode(utf8.encode(worker)),
          );
      await script.writeAsString(bootstrap);
      Process? process;
      Socket? socket;
      StreamSubscription<String>? output;
      var frames = 0;
      final fatal = <String>[];
      final ready = Completer<void>();
      final connected = Completer<void>();
      try {
        process = await Process.start(
          'powershell.exe',
          [
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script.path,
          ],
          environment: {'TEMP': root.path, 'TMP': root.path},
        );
        process.stderr.drain<void>();
        output = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) async {
              if (line.startsWith('__NC_DESKTOP_READY__')) {
                try {
                  socket = await Socket.connect(
                    '127.0.0.1',
                    int.parse(line.substring('__NC_DESKTOP_READY__'.length)),
                  );
                  socket!.write('$token\n');
                  await socket!.flush();
                  connected.complete();
                } catch (error, stack) {
                  connected.completeError(error, stack);
                }
              } else if (line.startsWith('__NC_FRAME__')) {
                // Discard pixels immediately; the test records only frame counts.
                frames++;
                if (!ready.isCompleted) ready.complete();
              } else if (line.startsWith('__NC_FATAL__')) {
                fatal.add(
                  utf8.decode(
                    base64Decode(line.substring('__NC_FATAL__'.length)),
                  ),
                );
              }
            });
        await connected.future.timeout(const Duration(seconds: 15));
        await ready.future.timeout(const Duration(seconds: 15));
        final sessionRoot = root.listSync().whereType<Directory>().single;
        // Move without clicking, then restore the original pointer in the
        // worker's finally block. Check physical pixels on the actual desktop.
        final pointerFile = File('${sessionRoot.path}/pointer-check.json');
        for (final point in [(0.25, 0.75), (0.75, 0.25)]) {
          socket!.writeln(
            jsonEncode({
              'x': point.$1,
              'y': point.$2,
              'action': 'move',
              'button': 'left',
              'delta': 0,
            }),
          );
          await socket!.flush();
          Map? position;
          final until = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(until)) {
            try {
              position = jsonDecode(await pointerFile.readAsString()) as Map;
              if (position['inputX'] == point.$1 &&
                  position['inputY'] == point.$2) {
                break;
              }
            } catch (_) {}
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(position?['inputX'], point.$1);
          expect(position?['inputY'], point.$2);
          expect(
            position!['x'],
            closeTo(
              (position['left'] as num) +
                  point.$1 * ((position['width'] as num) - 1),
              1,
            ),
          );
          expect(
            position['y'],
            closeTo(
              (position['top'] as num) +
                  point.$2 * ((position['height'] as num) - 1),
              1,
            ),
          );
        }
        final sequence = '${sessionRoot.path}\\frame.seq'.replaceAll("'", "''");
        // An exclusive lock reproduces the transient read failures that used to
        // abort the whole bootstrap. The capture worker must recover too.
        final locked = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "\$ErrorActionPreference='Stop';\$f=[IO.File]::Open('$sequence',[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{Start-Sleep -Milliseconds 700}finally{\$f.Dispose()}",
        ]);
        expect(locked.exitCode, 0, reason: '${locked.stderr}');
        final afterLock = frames;
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (frames < afterLock + 8 &&
            DateTime.now().isBefore(deadline) &&
            fatal.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(fatal, isEmpty);
        expect(frames, greaterThanOrEqualTo(afterLock + 8));
        socket!.destroy();
        expect(await process.exitCode.timeout(const Duration(seconds: 8)), 0);
        expect(
          sessionRoot.existsSync(),
          isFalse,
          reason: 'Session artifacts should be removed on disconnect',
        );
      } finally {
        socket?.destroy();
        if (process != null) {
          try {
            await process.exitCode.timeout(const Duration(seconds: 3));
          } catch (_) {
            process.kill();
          }
        }
        await output?.cancel();
        // Production bootstrap normally unregisters its task. Clean only this
        // test's exact remaining GUID task if an assertion interrupted it.
        for (final folder in root.listSync().whereType<Directory>()) {
          final name = folder.uri.pathSegments.where((v) => v.isNotEmpty).last;
          if (!RegExp(r'^NodeCockpit_Desktop_[a-f0-9]{32}$').hasMatch(name)) {
            continue;
          }
          await Process.run('powershell.exe', [
            '-NoProfile',
            '-Command',
            "Stop-ScheduledTask -TaskName '$name' -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName '$name' -Confirm:\$false -ErrorAction SilentlyContinue",
          ]);
        }
        await root.delete(recursive: true);
      }
    },
    skip:
        !Platform.isWindows ||
        Platform.environment['NODE_COCKPIT_DESKTOP_SMOKE_TEST'] != '1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
