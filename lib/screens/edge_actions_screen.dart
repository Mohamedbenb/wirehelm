import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/local_customization.dart';

const edgeActionLabels = <String, String>{
  'edit': 'Edit shortcuts',
  'windows': 'Windows',
  'capture': 'Take screenshot',
  'clipboard': 'Clipboard shelf',
  'settings': 'Wirehelm settings',
};

class EdgeActionsScreen extends StatefulWidget {
  final String? initialRaw;
  const EdgeActionsScreen({super.key, this.initialRaw});
  @override
  State<EdgeActionsScreen> createState() => _EdgeActionsScreenState();
}

class _EdgeActionsScreenState extends State<EdgeActionsScreen> {
  List<String> order = edgeActionLabels.keys.toList();
  Set<String> hidden = {'clipboard'};
  bool labels = true, busy = false;
  int iconSize = 24, columns = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.initialRaw != null) {
      try {
        read(widget.initialRaw!);
      } catch (_) {
        error = 'Saved toolbar options could not be read. Reset defaults to repair them.';
      }
    } else {
      unawaited(load());
    }
  }

  void read(String raw) {
    final j = jsonDecode(raw) as Map;
    final supplied = (j['order'] as List?)?.cast<String>();
    if (supplied != null &&
        supplied.length == 5 &&
        supplied.toSet().containsAll(edgeActionLabels.keys)) {
      order = List.of(supplied);
    }
    hidden = Set<String>.from(j['hidden'] as List? ?? ['clipboard']);
    labels = j['labels'] != false;
    iconSize = ((j['iconSize'] as num?)?.toInt() ?? 24).clamp(20, 32);
    columns = ((j['columns'] as num?)?.toInt() ?? 0).clamp(0, 4);
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final data = await LocalCustomization.call('edgeActions');
      if (mounted) setState(() => read(data['raw'] as String));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final raw = jsonEncode({
      'order': order,
      'hidden': hidden.toList(),
      'labels': labels,
      'iconSize': iconSize,
      'columns': columns,
    });
    if (widget.initialRaw == null) {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        await LocalCustomization.call('saveEdgeActions', {'raw': raw});
      } catch (e) {
        if (mounted) {
          setState(() {
            error = '$e';
            busy = false;
          });
        }
        return;
      }
    }
    if (mounted) Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Panel actions'),
      actions: [
        TextButton(onPressed: busy ? null : save, child: const Text('Save')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Text(
          'Choose the normal bottom buttons and drag to arrange them. Hold any bottom button in the panel to reopen these controls.',
        ),
        const SizedBox(height: 12),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: order.length,
          onReorderItem: (oldIndex, newIndex) {
            if (busy) return;
            setState(() {
              final value = order.removeAt(oldIndex);
              order.insert(newIndex, value);
            });
          },
          itemBuilder: (context, i) {
            final id = order[i];
            return Card(
              key: ValueKey(id),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(edgeActionLabels[id]!),
                leading: Switch(
                  value: !hidden.contains(id),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          if (v) {
                            hidden.remove(id);
                          } else {
                            hidden.add(id);
                          }
                        }),
                ),
                trailing: ReorderableDragStartListener(
                  index: i,
                  enabled: !busy,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.more_vert),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show button labels'),
          value: labels,
          onChanged: busy ? null : (v) => setState(() => labels = v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Columns'),
          trailing: DropdownButton<int>(
            value: columns,
            items: [0, 1, 2, 3, 4]
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v == 0 ? 'Automatic' : '$v'),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => setState(() => columns = v ?? 0),
          ),
        ),
        Text('Icon size · $iconSize dp'),
        Slider(
          value: iconSize.toDouble(),
          min: 20,
          max: 32,
          divisions: 12,
          label: '$iconSize dp',
          onChanged: busy ? null : (v) => setState(() => iconSize = v.round()),
        ),
        const Text(
          'Narrow panels limit the columns to keep buttons usable. A tall action section scrolls. Edit-mode Save/Cancel and window Back/Add stay available. If Edit is hidden, long-press the panel to edit shortcuts. These settings do not change the glass material.',
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  order = edgeActionLabels.keys.toList();
                  hidden = {'clipboard'};
                  labels = true;
                  iconSize = 24;
                  columns = 0;
                }),
          child: const Text('Reset button defaults'),
        ),
      ],
    ),
  );
}
