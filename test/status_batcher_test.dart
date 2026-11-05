import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/devices/device_host_connector.dart';
import 'package:remote_control/models/remote_command.dart';
import 'package:remote_control/ssh/ssh_session.dart';
import 'package:remote_control/stateful/status_batcher.dart';
import 'package:remote_control/stateful/stateful_controls_controller.dart';

class BatchSession extends SshSession {
  int calls = 0;
  @override
  bool get isConnected => true;
  @override
  Future<Uint8List> runCommand(
    String command, {
    String executionMode = 'standard',
    Duration? timeout,
  }) async {
    calls++;
    expectSync(executionMode, 'interactive');
    return Uint8List.fromList(
      utf8.encode(
        '__RC_STATUS_JSON__{"one":{"value":"on"},"two":{"error":"test failure"}}',
      ),
    );
  }
}

class ParallelBatchSession extends BatchSession {
  final desktop = Completer<Uint8List>();
  bool standardStarted = false;
  @override
  Future<Uint8List> runCommand(
    String command, {
    String executionMode = 'standard',
    Duration? timeout,
  }) => desktop.future;
  @override
  Future<Uint8List> runPowerShell(
    String command, {
    bool desktop = false,
    String label = 'Command',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    standardStarted = true;
    return Uint8List.fromList(
      utf8.encode('__RC_STATUS_JSON__{"standard":{"value":"on"}}'),
    );
  }
}

RemoteCommand toggle(String id) => RemoteCommand(
  id: id,
  name: id,
  category: 'test',
  stateful: const StatefulCommandConfig(
    statusCommand: "'on'",
    statusExecutionMode: 'interactive',
    states: [
      StatefulCommandState(
        id: 'on',
        label: 'On',
        command: 'on',
        expectedStatus: 'on',
      ),
    ],
  ),
);

void main() {
  testWidgets(
    'standard status completes while desktop batch is still waiting',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final session = ParallelBatchSession();
      final batcher = StatusBatcher();
      final desktop = batcher.check(
        context: context,
        command: toggle('one'),
        session: session,
      );
      final standardCommand = toggle('standard').copyWith(
        stateful: toggle('standard').stateful!.copyWith(
          statusExecutionMode: 'standard',
          statusCommand: 'powershell.exe -NoProfile -Command "\'on\'"',
        ),
      );
      final standard = batcher.check(
        context: context,
        command: standardCommand,
        session: session,
      );
      await tester.pump();
      expect(session.standardStarted, true);
      expect((await standard).stateId, 'on');
      session.desktop.complete(
        Uint8List.fromList(
          utf8.encode('__RC_STATUS_JSON__{"one":{"value":"on"}}'),
        ),
      );
      expect((await desktop).stateId, 'on');
    },
  );
  test('local takes priority; unavailable local falls back; legacy uses internet directly', () async {
    const device = Device(
      id: 'pc',
      name: 'PC',
      host: 'remote',
      localHost: 'local',
      port: 22,
      username: 'user',
      commands: [],
    );
    var remoteCalls = 0;
    Future<String> remote(String host) async {
      remoteCalls++;
      return host;
    }

    expect(
      await connectDeviceHosts(
        device: device,
        local: (host, timeout) async {
          expect(timeout, const Duration(seconds: 3));
          return host;
        },
        internet: remote,
      ),
      'local',
    );
    expect(remoteCalls, 0);
    expect(
      await connectDeviceHosts(
        device: device,
        local: (host, timeout) async => throw StateError('unreachable'),
        internet: remote,
      ),
      'remote',
    );
    expect(remoteCalls, 1);
    expect(
      await connectDeviceHosts(
        device: device.copyWith(localHost: ''),
        local: (host, timeout) async => throw StateError('must not call local'),
        internet: remote,
      ),
      'remote',
    );
    expect(remoteCalls, 2);
  });
  testWidgets(
    'one desktop call refreshes two commands and isolates per-command errors',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final session = BatchSession();
      final controller = StatefulControlsController(session: session);
      final one = toggle('one'), two = toggle('two');
      final refresh = controller.refreshCommands(
        context: context,
        commands: [one, two],
      );
      await tester.pump();
      await refresh;
      expect(session.calls, 1);
      expect(
        controller.statusFor(one).stateId,
        'on',
        reason: controller.statusFor(one).error,
      );
      expect(controller.statusFor(two).error, 'test failure');
      controller.dispose();
    },
  );

  test('real PowerShell batch deduplicates reads and returns JSON for Unicode IDs and failures', () async {
    final script = buildStatusBatchScript({
      r'$global:count++; $global:count': ['first', "second's Ω"],
      "throw 'isolated failure'": ['bad'],
      powerShellStatusBody(
        r'''powershell.exe -NoProfile -NonInteractive -Command "$a='disabled'; if($a -eq 'disabled'){'disabled'}else{'enabled'}"''',
      )!: [
        'adapter',
      ],
    });
    final directory = await Directory.systemTemp.createTemp(
      'remote_control_batch_',
    );
    try {
      final file = File('${directory.path}/batch.ps1');
      await file.writeAsString(script);
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
      ).timeout(const Duration(seconds: 10));
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final values = decodeStatusBatch(result.stdout as String);
      expect(
        values.keys,
        containsAll(['first', "second's Ω", 'bad']),
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(values['first']['value'], '1');
      expect(values["second's Ω"]['value'], '1');
      expect(values['bad']['error'], 'isolated failure');
      expect(values['adapter']['value'], 'disabled');
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  test('legacy devices preserve their host, and new settings survive copying and storage', () {
    final legacy = Device.fromJson({
      'id': 'pc',
      'name': 'PC',
      'host': '100.64.0.1',
      'port': 22,
      'username': 'test',
      'commands': [],
    });
    expect(legacy.localHost, '');
    expect(legacy.refreshSeconds, 20);
    final updated = legacy.copyWith(
      localHost: '192.168.1.2',
      refreshSeconds: 60,
    );
    final restored = Device.fromJson(
      updated.copyWith(name: 'Renamed').toJson(),
    );
    expect(restored.localHost, '192.168.1.2');
    expect(restored.host, legacy.host);
    expect(restored.refreshSeconds, 60);
  });
}
