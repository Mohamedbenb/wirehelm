import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
