import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../utils/command_icons.dart';
import 'stateful_control_status.dart';

class StatefulCommandCard extends StatelessWidget {
  final RemoteCommand command;

  final StatefulControlStatus status;
  final DateTime? checkedAt;

  final bool connected;

  final bool busy;
  final bool refreshing;
  final bool switching;
  final VoidCallback onRefresh;

  final Future<void> Function(StatefulCommandState state) onStatePressed;

  final VoidCallback? onEditTarget;

  const StatefulCommandCard({
    super.key,
    required this.command,
    required this.status,
    this.checkedAt,
    required this.connected,
    required this.busy,
    required this.refreshing,
    required this.switching,
    required this.onRefresh,
    required this.onStatePressed,
    this.onEditTarget,
  });

  bool get _hasStatusCommand {
    final statusCommand = command.stateful?.statusCommand?.trim();

    return statusCommand != null && statusCommand.isNotEmpty;
  }

  bool get _statesEnabled {
    if (!connected || busy) {
      return false;
    }

    if (!_hasStatusCommand) {
      return true;
    }

    return status.isAvailable;
  }

  String get _statusLabel {
    if (switching) return 'Switching...';
    if (status.stateId != null && (!connected || status.isUnavailable)) {
      return 'Last known state (stale)';
    }
    if (!_hasStatusCommand) {
      return 'Status not configured';
    }

    switch (status.phase) {
      case StatefulStatusPhase.unchecked:
        return 'Status not checked';

      case StatefulStatusPhase.checking:
        return 'Checking...';

      case StatefulStatusPhase.available:
        return 'Current state';

      case StatefulStatusPhase.unavailable:
        return 'Status unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = command.stateful;

    if (config == null) {
      return const SizedBox.shrink();
    }

    final target = config.target;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(commandIcon(command.icon)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    command.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (command.requiresSudo)
                  Icon(
                    Icons.admin_panel_settings,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),

            if (target != null) ...[
              const SizedBox(height: 6),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${target.label}: ${target.value}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  if (onEditTarget != null)
                    IconButton(
                      tooltip: 'Edit ${target.label}',
                      onPressed: connected && !busy ? onEditTarget : null,
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            Row(
              children: [
                if (status.isChecking || refreshing || switching)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(_statusIcon(), size: 16, color: _statusColor(context)),

                const SizedBox(width: 7),

                Expanded(
                  child: Text(
                    _buildStatusText(),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: _statusColor(context)),
                  ),
                ),
                if (_hasStatusCommand)
                  IconButton(
                    tooltip: 'Refresh status',
                    icon: const Icon(Icons.refresh, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: connected && !busy && !refreshing
                        ? onRefresh
                        : null,
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final state in config.states)
                  _buildStateChip(context, state),
              ],
            ),

            if (status.isUnavailable &&
                status.error != null &&
                status.error!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              if (checkedAt != null)
                Text(
                  'Last checked ${checkedAt!.hour.toString().padLeft(2, '0')}:${checkedAt!.minute.toString().padLeft(2, '0')}:${checkedAt!.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(
                status.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Status details'),
                    content: SingleChildScrollView(
                      child: SelectableText(status.error!),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Details'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStateChip(BuildContext context, StatefulCommandState state) {
    final isCurrent = status.stateId != null && status.stateId == state.id;

    return ChoiceChip(
      label: Text(state.label),
      selected: isCurrent,
      showCheckmark: false,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: isCurrent
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : null,
      ),
      onSelected: _statesEnabled
          ? (_) {
              onStatePressed(state);
            }
          : null,
    );
  }

  String _buildStatusText() {
    if (!_hasStatusCommand) {
      return _statusLabel;
    }

    if (status.stateId != null && !switching) {
      final config = command.stateful!;

      StatefulCommandState? currentState;

      for (final state in config.states) {
        if (state.id == status.stateId) {
          currentState = state;
          break;
        }
      }

      if (currentState != null) {
        return '$_statusLabel: '
            '${currentState.label}';
      }
    }

    return _statusLabel;
  }

  IconData _statusIcon() {
    if (!_hasStatusCommand) {
      return Icons.help_outline;
    }

    switch (status.phase) {
      case StatefulStatusPhase.unchecked:
        return Icons.help_outline;

      case StatefulStatusPhase.checking:
        return Icons.sync;

      case StatefulStatusPhase.available:
        return Icons.check_circle_outline;

      case StatefulStatusPhase.unavailable:
        return Icons.error_outline;
    }
  }

  Color _statusColor(BuildContext context) {
    if (!_hasStatusCommand) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }

    switch (status.phase) {
      case StatefulStatusPhase.unchecked:
        return Theme.of(context).colorScheme.onSurfaceVariant;

      case StatefulStatusPhase.checking:
        return Theme.of(context).colorScheme.primary;

      case StatefulStatusPhase.available:
        return Theme.of(context).colorScheme.primary;

      case StatefulStatusPhase.unavailable:
        return Theme.of(context).colorScheme.error;
    }
  }
}
