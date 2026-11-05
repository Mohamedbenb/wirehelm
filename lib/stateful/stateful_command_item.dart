import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../commands/command_options_menu.dart';
import 'stateful_command_card.dart';
import 'stateful_control_status.dart';

class StatefulCommandItem extends StatelessWidget {
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

  final VoidCallback onEdit;

  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onCopy;

  const StatefulCommandItem({
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
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatefulCommandCard(
            command: command,
            status: status,
            connected: connected,
            busy: busy,
            refreshing: refreshing,
            checkedAt: checkedAt,
            switching: switching,
            onRefresh: onRefresh,
            onStatePressed: onStatePressed,
            onEditTarget: onEditTarget,
          ),
        ),

        const SizedBox(width: 8),

        CommandOptionsMenu(
          onEdit: onEdit,
          onDuplicate: onDuplicate,
          onCopy: onCopy,
          onDelete: onDelete,
        ),
      ],
    );
  }
}
