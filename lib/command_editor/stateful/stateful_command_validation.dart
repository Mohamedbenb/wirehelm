import '../../models/remote_command.dart';
import '../../utils/command_parameters.dart';
import '../../utils/stateful_command_templates.dart';

String? validateStatefulCommand({
  required List<StatefulCommandState>
      states,
  required bool targetEnabled,
  required String targetKey,
  required String targetLabel,
  required String targetValue,
  required String statusCommand,
}) {
  if (states.length < 2) {
    return 'A stateful control needs at least two states.';
  }

  if (targetEnabled) {
    if (targetKey.trim().isEmpty) {
      return 'Enter a target key.';
    }

    if (!RegExp(
      r'^[A-Za-z_][A-Za-z0-9_-]*$',
    ).hasMatch(
      targetKey.trim(),
    )) {
      return 'Target key must start with a letter or underscore '
          'and contain only letters, numbers, _ or -.';
    }

    if (targetLabel.trim().isEmpty) {
      return 'Enter a target label.';
    }

    if (targetValue.trim().isEmpty) {
      return 'Enter a target value.';
    }
  }

  final runtimeParameters =
      <String>{};

  runtimeParameters.addAll(
    commandPlaceholders(
      statusCommand,
    ),
  );

  for (final state
      in states) {
    runtimeParameters.addAll(
      commandPlaceholders(
        state.command,
      ),
    );
  }

  if (runtimeParameters.isNotEmpty) {
    return 'Runtime parameters are not supported inside '
        'stateful controls yet.\n\n'
        'Found: '
        '${runtimeParameters.map(
      (key) =>
          '{{param:$key}}',
    ).join(', ')}';
  }

  final targetPlaceholders =
      <String>{};

  targetPlaceholders.addAll(
    statefulTargetPlaceholders(
      statusCommand,
    ),
  );

  for (final state
      in states) {
    targetPlaceholders.addAll(
      statefulTargetPlaceholders(
        state.command,
      ),
    );
  }

  if (targetPlaceholders.isEmpty) {
    return null;
  }

  if (!targetEnabled) {
    return 'A target placeholder is used, but this control '
        'has no target configured.';
  }

  final configuredKey =
      targetKey.trim();

  final invalidKeys =
      targetPlaceholders
          .where(
            (key) =>
                key !=
                configuredKey,
          )
          .toList();

  if (invalidKeys.isNotEmpty) {
    return 'Unknown target placeholder(s): '
        '${invalidKeys.map(
      (key) =>
          '{{target:$key}}',
    ).join(', ')}\n\n'
        'Configured target: '
        '{{target:$configuredKey}}';
  }

  return null;
}