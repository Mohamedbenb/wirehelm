import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/services/remote_downloads.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _PowerShellSession extends SshSession {
  final String home;
  final bool aliasFirst;
  int privateRuns = 0;
  _PowerShellSession(this.home, {this.aliasFirst = false})
    : super(manageBackgroundKeepAlive: false);

  @override
  bool get isConnected => true;
  @override
  String get deviceId => 'test-host';

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    if (command == 'uname -s') {
      return Uint8List.fromList(utf8.encode('uname is not recognized'));
    }
    expect(
      command,
      startsWith('powershell.exe -NoProfile -NonInteractive -EncodedCommand '),
    );
    privateRuns++;
    expect(input, isNotNull);
    final process = await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        command.split(' ').last,
      ],
      environment: {'USERPROFILE': home, 'HOME': home},
    );
    final output = process.stdout.fold<List<int>>(
      [],
      (data, chunk) => data..addAll(chunk),
    );
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(input!);
    await process.stdin.close();
    expect(await process.exitCode, 0, reason: await errors);
    return Uint8List.fromList(await output);
  }

  @override
  Future<Uint8List> runPowerShell(
    String script, {
    bool desktop = false,
    String label = 'Command',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final file = await File('$home/request.ps1')
        .writeAsString("\$ErrorActionPreference='Stop'\n$script");
    final process = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        file.path,
      ],
      environment: {
        'USERPROFILE': home,
        'HOME': home,
        if (aliasFirst)
          'PATH':
              '$home/aliases;${Platform.environment['SystemRoot']}\\System32',
      },
    ).timeout(timeout);
    if (process.exitCode != 0) throw StateError('${process.stderr}');
    return Uint8List.fromList(utf8.encode('${process.stdout}'));
  }
}

class _UnixSession extends _PowerShellSession {
  _UnixSession(super.home);

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    if (command == 'uname -s') {
      return Uint8List.fromList(utf8.encode('Linux\n'));
    }
    expect(command, 'python3 -');
    expect(input, isNotNull);
    final process = await Process.start(
      'python',
      ['-'],
      environment: {'USERPROFILE': home, 'HOME': home},
    );
    final stdout = process.stdout.fold<List<int>>(
      [],
      (data, chunk) => data..addAll(chunk),
    );
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(input!);
    await process.stdin.close();
    expect(await process.exitCode, 0, reason: await stderr);
    return Uint8List.fromList(await stdout);
  }
}

void main() {
  test('download URLs reject alternate protocols and embedded credentials', () {
    expect(
      RemoteDownloads.validateUrl('https://example.test/file.zip?token=abc'),
      isNull,
    );
    expect(RemoteDownloads.validateUrl('file:///private/file'), isNotNull);
    expect(
      RemoteDownloads.validateUrl('https://user:pass@example.test/file'),
      isNotNull,
    );
    expect(
      RemoteDownloads.validateUrl('https://example.test/\nfile'),
      isNotNull,
    );
  });

  test('Auto Unix hosts receive the worker through stdin', () async {
    final temp = await Directory.systemTemp.createTemp(
      'wirehelm-unix-bootstrap-',
    );
    final session = _UnixSession(temp.path);
    const device = Device(
      id: 'test-host',
      name: 'Test Linux',
      host: 'localhost',
      port: 22,
      username: 'test',
      commands: [],
    );
    try {
      final api = RemoteDownloads(device, session);
      final data = await api.list();
      expect(data['jobs'], isEmpty);
      expect(
        File('${temp.path}/.wirehelm/remote-downloads/worker-1.py')
            .existsSync(),
        isTrue,
      );
      final preparation = await api.ota('list');
      expect(preparation['jobs'], isEmpty);
      expect(
        File('${temp.path}/.wirehelm/remote-downloads/ota-worker-1.py')
            .existsSync(),
        isTrue,
      );
    } finally {
      session.dispose();
      await temp.delete(recursive: true);
    }
  });

  test(
    'Windows bootstrap survives broken aliases, restricted PATH and shell characters',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'wirehelm-bootstrap-test-',
      );
      final folder = await Directory("${temp.path}/Downloads ' test").create();
      final aliases = await Directory('${temp.path}/aliases').create();
      await File('${aliases.path}/python3.cmd').writeAsString(
        '@echo off\r\necho Python was not found 1>&2\r\nexit /b 9009\r\n',
      );
      final session = _PowerShellSession(temp.path, aliasFirst: true);
      const device = Device(
        id: 'test-host',
        name: 'Test PC',
        host: 'localhost',
        port: 22,
        username: 'test',
        shellStyle: 'auto',
        commands: [],
      );
      final api = RemoteDownloads(device, session);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final data = utf8.encode('downloaded file data');
      final serving = server.listen((request) async {
        request.response.contentLength = data.length;
        request.response.add(data);
        await request.response.close();
      });
      final id = RemoteDownloads.newId();
      try {
        final empty = await api.list();
        expect(empty['jobs'], isEmpty);
        final priorRequest = await File('${temp.path}/request.ps1')
            .readAsString();
        final ota = await api.ota('list', {
          'avbPassphrase': 'private-stdin-test',
        });
        expect(ota['jobs'], isEmpty);
        expect(session.privateRuns, 1);
        expect(
          await File('${temp.path}/request.ps1').readAsString(),
          priorRequest,
        );
        await api.start(
          id: id,
          url: 'http://127.0.0.1:${server.port}/file',
          name: r"file '; $ignored.zip",
          folder: folder.path,
          sha256: '',
        );
        Map<String, dynamic>? downloaded;
        final timeout = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(timeout)) {
          final jobs = (await api.list())['jobs'] as List;
          downloaded = Map<String, dynamic>.from(jobs.single as Map);
          if (downloaded['phase'] == 'complete') break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(downloaded?['phase'], 'complete', reason: downloaded.toString());
        expect(
          await File('${folder.path}/${downloaded!['name']}').readAsBytes(),
          data,
        );
        await File('${folder.path}/notes.txt').writeAsString('not an OTA');
        await Directory('${folder.path}/Firmware').create();
        final otaFolder = await api.ota('browse', {
          'path': '/${folder.path.replaceAll('\\', '/')}',
          'fallbackToHome': false,
        });
        expect(
          otaFolder['entries'],
          unorderedEquals([
            {
              'name': downloaded['name'],
              'directory': false,
              'bytes': data.length,
            },
            {'name': 'Firmware', 'directory': true},
          ]),
        );
      } finally {
        final jobs = (await api.list())['jobs'] as List;
        for (final job in jobs) {
          await api.action(
            RemoteDownload.fromJson(Map<String, dynamic>.from(job as Map)),
            'cancel',
          );
        }
        await serving.cancel();
        await server.close(force: true);
        session.dispose();
        await temp.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
