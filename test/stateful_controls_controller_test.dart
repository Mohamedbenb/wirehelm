import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/remote_command.dart';
import 'package:remote_control/ssh/ssh_session.dart';
import 'package:remote_control/stateful/stateful_control_status.dart';
import 'package:remote_control/stateful/stateful_controls_controller.dart';

class ConnectedSession extends SshSession {
  @override
  bool get isConnected => true;
}

const command = RemoteCommand(
  id: 'toggle',
  name: 'Toggle',
  category: 'Test',
  stateful: StatefulCommandConfig(
    statusCommand: 'status',
    states: [
      StatefulCommandState(
        id: 'on',
        label: 'On',
        command: 'on',
        expectedStatus: 'on',
      ),
      StatefulCommandState(
        id: 'off',
        label: 'Off',
        command: 'off',
        expectedStatus: 'off',
      ),
    ],
  ),
);
const onStatus = StatefulControlStatus.available(stateId: 'on', rawValue: 'on');
const offStatus = StatefulControlStatus.available(
  stateId: 'off',
  rawValue: 'off',
);

Future<BuildContext> mountContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets(
    'automatic refresh waits 20 seconds; manual refresh stays immediate',
    (tester) async {
      final context = await mountContext(tester);
      var now = DateTime(2026);
      var calls = 0;
      final controller = StatefulControlsController(
        session: ConnectedSession(),
        now: () => now,
        checkStatus:
            ({
              required context,
              required command,
              required session,
              bool allowPrompt = true,
            }) async {
              calls++;
              return onStatus;
            },
      );
      controller.startPolling(
        context: context,
        commands: () => [command],
        canPoll: () => true,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 19));
      await tester.pump(const Duration(seconds: 19));
      await tester.pump();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 2);
      await controller.refreshCommand(context: context, command: command);
      expect(calls, 3);
      controller.dispose();
    },
  );

  testWidgets(
    'hung status reads leave checking, do not overlap and cannot overwrite the timeout later',
    (tester) async {
      final context = await mountContext(tester);
      var calls = 0;
      final remoteRead = Completer<StatefulControlStatus>();
      final controller = StatefulControlsController(
        session: ConnectedSession(),
        checkStatus:
            ({
              required context,
              required command,
              required session,
              bool allowPrompt = true,
            }) {
              calls++;
              return remoteRead.future;
            },
      );
      final read = controller.refreshCommand(
        context: context,
        command: command,
      );
      await tester.pump();
      expect(controller.statusFor(command).isChecking, isTrue);
      await tester.pump(const Duration(seconds: 45));
      expect((await read).isUnavailable, isTrue);
      expect(controller.isRefreshing(command), isFalse);
      expect(controller.statusFor(command).error, contains('timed out'));
      await controller.refreshCommand(context: context, command: command);
      expect(calls, 1);
      remoteRead.complete(onStatus);
      await tester.pump();
      expect(controller.statusFor(command).isUnavailable, isTrue);
      controller.dispose();
    },
  );

  testWidgets(
    'deduplicates reads, retains confirmed status during refresh and marks failed reads stale',
    (tester) async {
      final context = await mountContext(tester);
      var calls = 0;
      var result = Completer<StatefulControlStatus>();
      final controller = StatefulControlsController(
        session: ConnectedSession(),
        checkStatus:
            ({
              required context,
              required command,
              required session,
              bool allowPrompt = true,
            }) {
              calls++;
              return result.future;
            },
      );
      final first = controller.refreshCommand(
        context: context,
        command: command,
      );
      final joined = controller.refreshCommand(
        context: context,
        command: command,
      );
      expect(identical(first, joined), isTrue);
      await tester.pump();
      expect(calls, 1);
      result.complete(onStatus);
      await tester.pump();
      result = Completer<StatefulControlStatus>();
      controller.refreshCommand(context: context, command: command);
      expect(controller.statusFor(command).stateId, 'on');
      expect(controller.isRefreshing(command), isTrue);
      await tester.pump();
      result.complete(
        const StatefulControlStatus.unavailable(error: 'Read failed'),
      );
      await tester.pump();
      expect(controller.statusFor(command).stateId, 'on');
      expect(controller.statusFor(command).isUnavailable, isTrue);
      controller.dispose();
    },
  );

  testWidgets(
    'late responses cannot restore a removed command or notify after disposal',
    (tester) async {
      final context = await mountContext(tester);
      final result = Completer<StatefulControlStatus>();
      final controller = StatefulControlsController(
        session: ConnectedSession(),
        checkStatus: ({
          required context,
          required command,
          required session,
          bool allowPrompt = true,
        }) => result.future,
      );
      controller.refreshCommand(context: context, command: command);
      await tester.pump();
      controller.removeCommand(command.id);
      result.complete(onStatus);
      await tester.pump();
      expect(controller.statusFor(command).isUnchecked, isTrue);
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'polling pauses when hidden and automatic reads never request authentication',
    (tester) async {
      final context = await mountContext(tester);
      var visible = false;
      var calls = 0;
      final controller = StatefulControlsController(
        session: ConnectedSession(),
        checkStatus:
            ({
              required context,
              required command,
              required session,
              bool allowPrompt = true,
            }) async {
              calls++;
              expectSync(allowPrompt, isFalse);
              return onStatus;
            },
      );
      controller.startPolling(
        context: context,
        commands: () => [command],
        canPoll: () => visible,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 0);
      visible = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 1);
      visible = false;
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
      controller.dispose();
    },
  );

  testWidgets('switch remains busy until the requested state is confirmed', (
    tester,
  ) async {
    final context = await mountContext(tester);
    var checks = 0;
    final controller = StatefulControlsController(
      session: ConnectedSession(),
      runCommand: ({
        required context,
        required command,
        required state,
        required session,
      }) async => 'sent',
      checkStatus:
          ({
            required context,
            required command,
            required session,
            bool allowPrompt = true,
          }) async {
            expectSync(allowPrompt, isFalse);
            return ++checks == 1 ? offStatus : onStatus;
          },
    );
    final result = controller.runState(
      context: context,
      command: command,
      state: command.stateful!.states.first,
    );
    await tester.pump();
    await tester.pump();
    if (!controller.isRunning(command)) {
      final early = await result;
      fail(
        'Switch finished early: ${early.outcome}, ${early.message}, checks: $checks, status: ${controller.statusFor(command).error}',
      );
    }
    expect(controller.statusFor(command).stateId, 'off');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect((await result).succeeded, isTrue);
    expect(controller.statusFor(command).stateId, 'on');
    expect(controller.isRunning(command), isFalse);
    controller.dispose();
  });

  testWidgets('timed out switch warns that the action may have completed', (
    tester,
  ) async {
    final context = await mountContext(tester);
    final controller = StatefulControlsController(
      session: ConnectedSession(),
      runCommand: ({
        required context,
        required command,
        required state,
        required session,
      }) => Future<String?>.error(TimeoutException('late response')),
      checkStatus: ({
        required context,
        required command,
        required session,
        bool allowPrompt = true,
      }) async => offStatus,
    );

    final result = await controller.runState(
      context: context,
      command: command,
      state: command.stateful!.states.first,
    );

    expect(result.outcome, StatefulStateRunOutcome.failed);
    expect(result.message, contains('may still have completed'));
    expect(result.message, contains('before retrying'));
    controller.dispose();
  });
}
