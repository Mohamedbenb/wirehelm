import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/command_editor/action/action_command_tester.dart';
import 'package:remote_control/models/remote_command.dart';
import 'package:remote_control/ssh/ssh_session.dart';
import 'package:remote_control/utils/command_parameters.dart';

class TestSession extends SshSession {
  final commands = <String>[];
  @override
  bool get isConnected => true;
  @override
  Future<Uint8List> runCommand(
    String command, {
    String executionMode = 'standard',
    Duration? timeout,
  }) async {
    commands.add(command);
    return Uint8List.fromList(utf8.encode('ok'));
  }
}

void main() {
  testWidgets('action and verification use the supplied device session', (
    tester,
  ) async {
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
    final session = TestSession();
    late String result;
    await tester.runAsync(() async {
      result = await testActionCommand(
        context: context,
        session: session,
        command: const RemoteCommand(
          id: 'test',
          name: 'Test',
          category: 'Test',
          command: 'action',
          verificationCommand: 'verify',
          expectedOutput: 'ok',
        ),
      );
    });
    expect(session.commands, ['action', 'verify']);
    expect(result, contains('Verified successfully'));
    session.dispose();
  });

  test('saved wakeonlan commands accept Windows MAC formatting', () {
    const command = RemoteCommand(
      id: 'wake',
      name: 'Wake',
      category: 'Power',
      command: 'wakeonlan -i {{param:broadcast}} {{param:mac}}',
      parameters: [
        CommandParameter(key: 'mac', label: 'MAC'),
        CommandParameter(
          key: 'broadcast',
          label: 'Broadcast',
          defaultValue: '192.168.1.255',
        ),
      ],
    );
    expect(
      renderCommandTemplate(command.command, command, {
        'mac': '34-4B-50-00-00-00',
      }),
      'wakeonlan -i 192.168.1.255 34:4B:50:00:00:00',
    );
    expect(
      renderCommandTemplate('echo {{param:mac}}', command, {
        'mac': '34-4B-50-00-00-00',
      }),
      'echo 34-4B-50-00-00-00',
    );
  });
}
