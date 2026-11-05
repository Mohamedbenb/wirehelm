import 'package:flutter/material.dart';

class CommandOptionsMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const CommandOptionsMenu({
    super.key,
    required this.onEdit,
    required this.onDuplicate,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    PopupMenuItem<String> item(
      String value,
      String label,
      IconData icon, {
      bool destructive = false,
    }) {
      final color = destructive ? colors.error : colors.onSurface;
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Command options',
      icon: const Icon(Icons.more_vert),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'duplicate':
            onDuplicate();
          case 'copy':
            onCopy();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        item('edit', 'Edit', Icons.edit_outlined),
        item('duplicate', 'Duplicate', Icons.control_point_duplicate_outlined),
        item('copy', 'Copy', Icons.copy_outlined),
        const PopupMenuDivider(),
        item('delete', 'Delete', Icons.delete_outline, destructive: true),
      ],
    );
  }
}
