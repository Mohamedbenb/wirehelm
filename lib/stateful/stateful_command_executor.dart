import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../ssh/ssh_session.dart';
import '../utils/stateful_command_templates.dart';
import '../utils/sudo_command.dart';
import 'stateful_control_status.dart';

String renderStatefulCommand({
  required RemoteCommand command,
  required String template,
}) {
  final config =
      command.stateful;

  if (config == null) {
    return template.trim();
  }

  final target =
      config.target;

  return renderStatefulTemplate(
    template,
    targetKey:
        target?.key,
    targetValue:
        target?.value,
  );
}

RemoteCommand _withExecutionMode({
  required RemoteCommand command,
  required String executionMode,
}) {
  return command.copyWith(
    executionMode:
        executionMode,
  );
}

Future<String?> runStatefulStateCommand({
  required BuildContext context,
  required RemoteCommand command,
  required StatefulCommandState state,
  required SshSession session,
}) async {
  final config =
      command.stateful;

  if (config == null) {
    throw StateError(
      'Command is not stateful.',
    );
  }

  if (!session.isConnected) {
    throw StateError(
      'SSH session is disconnected.',
    );
  }

  final commandText =
      renderStatefulCommand(
    command:
        command,
    template:
        state.command,
  );

  if (commandText.isEmpty) {
    throw StateError(
      'State command is empty.',
    );
  }

  final unresolvedTargets =
      statefulTargetPlaceholders(
    commandText,
  );

  if (unresolvedTargets.isNotEmpty) {
    throw StateError(
      'Unresolved target placeholder(s): '
      '${unresolvedTargets.map(
        (key) => '{{target:$key}}',
      ).join(', ')}',
    );
  }

  final executionCommand =
      _withExecutionMode(
    command:
        command,
    executionMode:
        state.executionMode,
  );

    final result =
        await runCommandWithPrivileges(
    context:
        context,
    command:
        executionCommand,
    commandText:
        commandText,
    session:
        session,
  );

  //
  // null means the sudo/password flow
  // was cancelled by the user.
  //
  if (result == null) {
    return null;
  }

  return utf8
      .decode(
        result,
        allowMalformed:
            true,
      )
      .trim();
}

Future<StatefulControlStatus>
    checkStatefulCommandStatus({
  required BuildContext context,
  required RemoteCommand command,
  required SshSession session,
  bool allowPrompt = true,
}) async {
  final config =
      command.stateful;

  if (config == null) {
    return const StatefulControlStatus
        .unavailable(
      error:
          'Command is not stateful.',
    );
  }

  //
  // No status command is a valid configuration.
  //
  // The UI should keep the state buttons usable,
  // but must not claim that a current state is known.
  //
  final statusTemplate =
      config.statusCommand
          ?.trim();

  if (statusTemplate == null ||
      statusTemplate.isEmpty) {
    return const StatefulControlStatus
        .unchecked();
  }

  if (!session.isConnected) {
    return const StatefulControlStatus
        .unavailable(
      error:
          'Disconnected.',
    );
  }

  final commandText =
      renderStatefulCommand(
    command:
        command,
    template:
        statusTemplate,
  );

  final unresolvedTargets =
      statefulTargetPlaceholders(
    commandText,
  );

  if (unresolvedTargets.isNotEmpty) {
    return StatefulControlStatus
        .unavailable(
      error:
          'Unresolved target placeholder(s): '
          '${unresolvedTargets.map(
        (key) => '{{target:$key}}',
      ).join(', ')}',
    );
  }

  final executionCommand =
      _withExecutionMode(
    command:
        command,
    executionMode:
        config.statusExecutionMode,
  );

  try {
      final result =
        await runCommandWithPrivileges(
      context:
          context,
      command:
          executionCommand,
      commandText:
          commandText,
      session:
          session,
      allowPrompt: allowPrompt,
      timeout: const Duration(seconds: 20),
    );

    if (result == null) {
      return const StatefulControlStatus
          .unavailable(
        error:
            'Status check cancelled.',
      );
    }

    final output =
        utf8
            .decode(
              result,
              allowMalformed:
                  true,
            )
            .trim();

    return resolveStatefulStatus(
      command:
          command,
      rawOutput:
          output,
    );
  } catch (e) {
    return StatefulControlStatus
        .unavailable(
      error:
          e.toString(),
    );
  }
}
