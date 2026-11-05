import '../models/remote_command.dart';

RemoteCommand buildActionCommand({
  required RemoteCommand? existingCommand,
  required RemoteCommand? template,
  required String name,
  required String category,
  required String command,
  required String icon,
  required bool requiresConfirmation,
  required bool requiresSudo,
  required String executionMode,
  required String verificationCommand,
  required String expectedOutput,
  required List<CommandParameter> parameters,
}) {
  final verification =
      verificationCommand.trim();

  final expected =
      expectedOutput.trim();

  return RemoteCommand(
    id:
        existingCommand?.id ??
        'preview',

    templateId:
        existingCommand?.templateId ??
        template?.templateId ??
        template?.id,

    name:
        name.trim(),

    category:
        category.trim(),

    command:
        command.trim(),

    icon:
        icon,

    requiresConfirmation:
        requiresConfirmation,

    requiresSudo:
        requiresSudo,

    executionMode:
        executionMode,

    verificationCommand:
        verification.isEmpty
            ? null
            : verification,

    expectedOutput:
        expected.isEmpty
            ? null
            : expected,

    parameters:
        List.unmodifiable(
      parameters,
    ),

    stateful:
        null,
  );
}

RemoteCommand buildStatefulCommand({
  required RemoteCommand? existingCommand,
  required RemoteCommand? template,
  required String name,
  required String category,
  required String icon,
  required bool requiresConfirmation,
  required bool requiresSudo,

  //
  // Legacy/root mode is retained for
  // compatibility, but stateful execution
  // now uses the dedicated modes below.
  //
  required String executionMode,

  required bool targetEnabled,
  required String targetKey,
  required String targetLabel,
  required String targetValue,

  required String statusCommand,
  required String statusExecutionMode,

  required List<StatefulCommandState> states,
}) {
  StatefulCommandTarget? target;

  if (targetEnabled) {
    target =
        StatefulCommandTarget(
      key:
          targetKey.trim(),

      label:
          targetLabel.trim(),

      value:
          targetValue.trim(),
    );
  }

  final normalizedStatus =
      statusCommand.trim();

  return RemoteCommand(
    id:
        existingCommand?.id ??
        'preview',

    templateId:
        existingCommand?.templateId ??
        template?.templateId ??
        template?.id,

    name:
        name.trim(),

    category:
        category.trim(),

    //
    // Stateful controls execute commands
    // stored inside their individual states.
    //
    command:
        '',

    icon:
        icon,

    requiresConfirmation:
        requiresConfirmation,

    requiresSudo:
        requiresSudo,

    //
    // Keep the root execution mode for
    // backward compatibility / serialization.
    //
    executionMode:
        executionMode,

    verificationCommand:
        null,

    expectedOutput:
        null,

    parameters:
        const [],

    stateful:
        StatefulCommandConfig(
      target:
          target,

      statusCommand:
          normalizedStatus.isEmpty
              ? null
              : normalizedStatus,

      statusExecutionMode:
          statusExecutionMode,

      states:
          List.unmodifiable(
        states,
      ),
    ),
  );
}

RemoteCommand commandWithPersistentId({
  required RemoteCommand command,
  required RemoteCommand? existingCommand,
}) {
  return RemoteCommand(
    id:
        existingCommand?.id ??
        DateTime.now()
            .microsecondsSinceEpoch
            .toString(),

    templateId:
        command.templateId,

    name:
        command.name,

    command:
        command.command,

    category:
        command.category,

    icon:
        command.icon,

    requiresConfirmation:
        command.requiresConfirmation,

    requiresSudo:
        command.requiresSudo,

    executionMode:
        command.executionMode,

    verificationCommand:
        command.verificationCommand,

    expectedOutput:
        command.expectedOutput,

    parameters:
        command.parameters,

    stateful:
        command.stateful,
  );
}