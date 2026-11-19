import 'dart:async';

import 'package:flutter/material.dart';

class CarrierSelectionDialog extends StatefulWidget {
  const CarrierSelectionDialog({
    super.key,
    required this.selected,
    required this.load,
  });
  final Set<String> selected;
  final Future<Map<String, dynamic>> Function(String) load;
  @override
  State<CarrierSelectionDialog> createState() => _CarrierSelectionDialogState();
}

class _CarrierSelectionDialogState extends State<CarrierSelectionDialog> {
  late final Set<String> selected = {...widget.selected};
  final names = <String, String>{};
  List<Map<String, dynamic>> items = [];
  Timer? timer;
  int generation = 0;
  bool loading = true, more = false;
  String query = '';
  String? error;
  @override
  void initState() {
    super.initState();
    fetch();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> fetch() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.load(query);
      if (!mounted || request != generation) return;
      final rows = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final row in [
        ...rows,
        ...(data['selected'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      ]) {
        names['${row['mccmnc']}'] = '${row['name']}';
      }
      setState(() {
        items = rows;
        more = data['more'] == true;
        loading = false;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose carriers'),
    content: SizedBox(
      width: 480,
      height: 480,
      child: Column(
        children: [
          TextField(
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Carrier name or MCC/MNC',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              query = value;
              timer?.cancel();
              generation++;
              setState(() {
                loading = true;
              });
              timer = Timer(const Duration(milliseconds: 300), fetch);
            },
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 4,
                children: [
                  for (final code in selected.toList()..sort())
                    InputChip(
                      label: Text('${names[code] ?? code} ($code)'),
                      onDeleted: () => setState(() => selected.remove(code)),
                    ),
                ],
              ),
            ),
          ),
          Text(
            '${selected.length}/32 selected. Changes apply after enabling and rebooting.',
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: fetch, child: const Text('Retry')),
          ],
          Expanded(
            child: ListView(
              children: [
                for (final row in items)
                  CheckboxListTile(
                    title: Text('${row['name']}'),
                    subtitle: Text('${row['mccmnc']}'),
                    value: selected.contains('${row['mccmnc']}'),
                    onChanged:
                        loading ||
                            (!selected.contains('${row['mccmnc']}') &&
                                selected.length >= 32)
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              selected.add('${row['mccmnc']}');
                            } else {
                              selected.remove('${row['mccmnc']}');
                            }
                          }),
                  ),
                if (more)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('More carriers available. Refine your search.'),
                  ),
                if (!loading && error == null && items.isEmpty)
                  const Text('No matching carriers in this firmware.'),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: selected.isEmpty
            ? null
            : () => Navigator.pop(context, selected),
        child: const Text('Save'),
      ),
    ],
  );
}
