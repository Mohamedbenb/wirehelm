import 'package:flutter/material.dart';

import '../../models/remote_command.dart';

class StatefulStatesSection extends StatelessWidget {
  final List<StatefulCommandState> states;
  final VoidCallback onAdd;

  final void Function(
    StatefulCommandState state,
    int index,
  ) onEdit;

  final ValueChanged<int> onDelete;
  final ValueChanged<int> onDuplicate;

  final void Function(
    int index,
    int offset,
  ) onMove;

  const StatefulStatesSection({
    super.key,
    required this.states,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Switch states',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Each state has a command and the '
                    'status value that identifies it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (states.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No states yet. Add at least two switch states.',
              ),
            ),
          )
        else
          for (var i = 0; i < states.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => onEdit(states[i], i),
                leading: CircleAvatar(
                  child: Text('${i + 1}'),
                ),
                title: Text(states[i].label),
                subtitle: Text(
                  '${states[i].id} • '
                  'status: ${states[i].expectedStatus}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: i == 0 ? null : () => onMove(i, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: i == states.length - 1
                          ? null
                          : () => onMove(i, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'State options',
                      onSelected: (value) {
                        switch (value) {
                          case 'duplicate':
                            onDuplicate(i);
                          case 'delete':
                            onDelete(i);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Row(
                            children: [
                              Icon(Icons.copy_outlined),
                              SizedBox(width: 12),
                              Text('Duplicate state'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 12),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
