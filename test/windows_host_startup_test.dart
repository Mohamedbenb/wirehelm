import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/ssh/windows_command_host.dart';

class _SilentExec extends Fake implements SSHSession {
  final Process process;
  final input = StreamController<Uint8List>();
  final output = StreamController<Uint8List>();
  _SilentExec(this.process) {
    input.stream.listen(
      process.stdin.add,
      onDone: () {
        unawaited(process.stdin.close());
      },
    );
    // Model the actual Windows OpenSSH failure: no live stdout is delivered.
    unawaited(process.stdout.drain<void>());
    unawaited(process.exitCode.then((_) => output.close()));
  }
  @override
  StreamSink<Uint8List> get stdin => input.sink;
  @override
  Stream<Uint8List> get stdout => output.stream;
  @override
  Stream<Uint8List> get stderr => process.stderr.map(Uint8List.fromList);
  @override
  Future<void> get done => process.exitCode.then((_) {});
  @override
  int? get exitCode => null;
  @override
  void write(Uint8List bytes) => input.add(bytes);
  @override
  void close() => process.kill();
}

class _Forward extends Fake implements SSHForwardChannel {
  final SSHSocket socket;
  _Forward(this.socket);
  @override
  Stream<Uint8List> get stream => socket.stream;
  @override
  StreamSink<List<int>> get sink => socket.sink;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> close() => socket.close();
  @override
  void destroy() => socket.destroy();
}

class _Client extends Fake implements SSHClient {
  _SilentExec? exec;
  @override
  bool get isClosed => false;
  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    final encoded = command.split(' ').last;
    expect(command.length, lessThan(8191));
    final process = await Process.start('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]);
    return exec = _SilentExec(process);
  }

  @override
  Future<SSHForwardChannel> forwardLocal(
    String host,
    int port, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    // Windows can confirm a successful tunnel slightly after two seconds.
    // A short per-attempt timeout would discard the broker's first connection.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    try {
      return _Forward(await SSHSocket.connect(host, port));
    } on SocketException {
      throw SSHChannelOpenError(2, 'Connection refused');
    }
  }
}

void main() {
  for (final desktop in [false, true]) {
    test('real ${desktop ? 'desktop' : 'standard'} helper starts with no SSH stdout', () async {
      final client = _Client();
      final host = WindowsCommandHost(client, desktop: desktop);
      Directory? staleDirectory;
      File? staleFile;
      try {
        if (desktop) {
          final token = DateTime.now().microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(32, '0');
          final directory = Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}NodeCockpit_$token',
          );
          staleDirectory = directory;
          await directory.create();
          for (final name in [
            'worker.ps1',
            'start.js',
            'request.json',
            'request.tmp',
            'response.json',
            'response.tmp',
            'RemoteControl_1234567890123456.out',
            'RemoteControl_1234567890123456.done',
          ]) {
            await File('${directory.path}${Platform.pathSeparator}$name')
                .writeAsString('stale');
          }
          final file = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}RemoteControl_${DateTime.now().microsecondsSinceEpoch}.out',
          );
          staleFile = file;
          await file.writeAsString('stale');
          final staleTime = DateTime.now().subtract(const Duration(hours: 48));
          final escapedPath = directory.path.replaceAll("'", "''");
          final timestamp = await Process.run('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            "(Get-Item -LiteralPath '$escapedPath').LastWriteTime = [DateTime]::Now.AddHours(-48)",
          ]);
          expect(timestamp.exitCode, 0, reason: '${timestamp.stderr}');
          await file.setLastModified(staleTime);
        }
        final first = utf8
            .decode(await host.run('42; \$PID', const Duration(seconds: 10)))
            .trim();
        if (desktop) {
          expect(await staleDirectory?.exists(), isFalse);
          expect(await staleFile?.exists(), isFalse);
        }
        expect(client.exec!.input.isClosed, isFalse);
        final second = utf8
            .decode(await host.run('42; \$PID', const Duration(seconds: 10)))
            .trim();
        expect(first.split(RegExp(r'\s+')).first, '42');
        expect(second, first);
        host.close();
        expect(
          await client.exec!.process.exitCode.timeout(
            const Duration(seconds: 10),
          ),
          0,
        );
      } finally {
        host.close();
        client.exec?.process.kill();
        final directory = staleDirectory;
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
        final file = staleFile;
        if (file != null && await file.exists()) {
          await file.delete();
        }
      }
    }, skip: !Platform.isWindows);
  }
}
