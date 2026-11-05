import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/remote_command.dart';
import 'package:remote_control/utils/command_transfer.dart';

void main() {
  test('user-authored commands require confirmation by default', () {
    const userAction = RemoteCommand(
      id: 'custom-action',
      name: 'Custom action',
      category: 'Custom',
    );
    const userStateful = RemoteCommand(
      id: 'custom-switch',
      name: 'Custom switch',
      category: 'Custom',
      stateful: StatefulCommandConfig(states: []),
    );
    const builtIn = RemoteCommand(
      id: 'built-in',
      templateId: 'windows_builtin',
      name: 'Built in',
      category: 'System',
    );

    expect(userAction.requiresUserConfirmation, isTrue);
    expect(userStateful.requiresUserConfirmation, isTrue);
    expect(builtIn.requiresUserConfirmation, isFalse);
    expect(
      builtIn.copyWith(requiresConfirmation: true).requiresUserConfirmation,
      isTrue,
    );
  });

  const action = RemoteCommand(
    id: 'action',
    templateId: 'template',
    name: 'Run',
    category: 'Tools',
    command: 'echo {{param:message}}',
    verificationCommand: 'echo done',
    expectedOutput: 'done',
    requiresConfirmation: true,
    requiresSudo: true,
    parameters: [
      CommandParameter(key: 'message', label: 'Message', defaultValue: 'hello'),
    ],
  );
  const stateful = RemoteCommand(
    id: 'switch',
    name: 'Switch',
    category: 'Tools',
    stateful: StatefulCommandConfig(
      target: StatefulCommandTarget(
        key: 'target',
        label: 'Target',
        value: 'service',
      ),
      statusCommand: 'status {{target:target}}',
      statusExecutionMode: 'interactive',
      states: [
        StatefulCommandState(
          id: 'on',
          label: 'On',
          command: 'start',
          expectedStatus: 'running',
          executionMode: 'interactive',
        ),
        StatefulCommandState(
          id: 'off',
          label: 'Off',
          command: 'stop',
          expectedStatus: 'stopped',
        ),
      ],
    ),
  );

  for (final source in [action, stateful]) {
    test('${source.id} clipboard transfer preserves all fields', () {
      final restored = decodeCommandTransfer(encodeCommandTransfer(source));
      expect(restored.toJson(), source.toJson());
    });

    test(
      '${source.id} duplicate has independent data and a unique name and ID',
      () {
        final first = cloneCommand(source, [source], rename: true);
        final second = cloneCommand(source, [source, first], rename: true);
        expect(first.id, isNot(source.id));
        expect(second.id, isNot(first.id));
        expect(second.name, '${source.name} (copy 2)');
        expect(
          first.toJson()
            ..remove('id')
            ..remove('name'),
          source.toJson()
            ..remove('id')
            ..remove('name'),
        );
        if (source.isStateful) {
          first.stateful!.states.clear();
          expect(source.stateful!.states, hasLength(2));
        } else {
          first.parameters.clear();
          expect(source.parameters, hasLength(1));
        }
      },
    );
  }

  test('rejects plain shell text, unrelated JSON and unsupported versions', () {
    for (final text in [
      'echo hello',
      '{}',
      '{"format":"remote_control.command","version":2,"command":{}}',
    ]) {
      expect(() => decodeCommandTransfer(text), throwsFormatException);
    }
  });
}
