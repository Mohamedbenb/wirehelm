import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../customization/local_customization.dart';
import '../models/device.dart';
import '../services/device_storage.dart';
import '../services/edge_controls.dart';
import '../widgets/edge_panel_control_toggle.dart';

const edgeActionLabels = <String, String>{
  'edit': 'Edit shortcuts',
  'windows': 'Windows',
  'capture': 'Take screenshot',
  'clipboard': 'Clipboard shelf',
  'settings': 'Wirehelm settings',
};

final edgeControlLabels = {
  for (final control in EdgePanelControl.values) control.id: control.label,
};

class EdgeActionsScreen extends StatefulWidget {
  const EdgeActionsScreen({super.key});
  @override
  State<EdgeActionsScreen> createState() => _EdgeActionsScreenState();
}

class _EdgeActionsScreenState extends State<EdgeActionsScreen> {
  List<String> order = edgeActionLabels.keys.toList();
  Set<String> hidden = {'clipboard'};
  bool labels = true, busy = false;
  int iconSize = 24, columns = 0;
  String? error;
  String bulbDevice = '', pcDevice = '', keyboardDevice = '';
  List<String> controls = List.of(defaultEdgeControls);
  List<Device> savedDevices = const [];
  @override
  void initState() {
    super.initState();
    unawaited(loadControlHosts());
    unawaited(load());
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
    bulbDevice = j['bulbDevice'] as String? ?? '';
    pcDevice = j['pcDevice'] as String? ?? '';
    keyboardDevice = j['keyboardDevice'] as String? ?? '';
    final savedControls = j['controls'] as List?;
    controls = savedControls == null
        ? List.of(defaultEdgeControls)
        : savedControls
              .whereType<String>()
              .where(edgeControlLabels.containsKey)
              .toSet()
              .toList();
    labels = j['labels'] != false;
    iconSize = ((j['iconSize'] as num?)?.toInt() ?? 24).clamp(20, 32);
    columns = ((j['columns'] as num?)?.toInt() ?? 0).clamp(0, 4);
  }

  Future<void> loadControlHosts() async {
    try {
      final devices = await DeviceStorage().loadDevices();
      if (mounted) {
        setState(() => savedDevices = devices);
      }
    } catch (_) {
      // The toolbar settings are still editable if the device list is unreadable.
    }
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
      if (bulbDevice.isNotEmpty) 'bulbDevice': bulbDevice,
      if (pcDevice.isNotEmpty) 'pcDevice': pcDevice,
      if (keyboardDevice.isNotEmpty) 'keyboardDevice': keyboardDevice,
      if (!listEquals(controls, defaultEdgeControls)) 'controls': controls,
    });
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await LocalCustomization.call('saveEdgeActions', {'raw': raw});
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not save panel settings. Try again.';
          busy = false;
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context, raw);
  }

  Widget controlHost({
    required String title,
    required String prompt,
    required String hint,
    required String empty,
    required String selected,
    required List<Device> devices,
    required ValueChanged<String> change,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(
      selected.isEmpty
          ? hint
          : devices
                    .where((device) => device.id == selected)
                    .firstOrNull
                    ?.name ??
                'Saved host unavailable',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: busy
        ? null
        : () async {
            final host = await showDialog<String>(
              context: context,
              builder: (dialog) => SimpleDialog(
                title: Text(prompt),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, ''),
                    child: const Text('Off'),
                  ),
                  for (final device in devices)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, device.id),
                      child: Text(device.name),
                    ),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text(empty),
                    ),
                ],
              ),
            );
            if (mounted && host != null) setState(() => change(host));
          },
  );

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
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Controls list'),
          subtitle: const Text('Choose which tools appear in the Edge panel'),
          children: [
            for (final entry in edgeControlLabels.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                value: controls.contains(entry.key),
                onChanged: busy
                    ? null
                    : (visible) => setState(() {
                        if (visible == true) {
                          controls.add(entry.key);
                        } else {
                          controls.remove(entry.key);
                        }
                      }),
              ),
          ],
        ),
        controlHost(
          title: 'Smart bulb on the Controls page',
          prompt: 'Smart bulb host',
          hint: 'Choose the host where your bulb is set up.',
          empty: 'Add a Linux device first.',
          selected: bulbDevice,
          devices: savedDevices.where(isEdgeBulbHost).toList(),
          change: (host) => bulbDevice = host,
        ),
        controlHost(
          title: 'PC on the Controls page',
          prompt: 'PC host',
          hint: 'Choose the CachyOS PC for power and text size.',
          empty: 'Add a CachyOS device first.',
          selected: pcDevice,
          devices: savedDevices.where(isEdgePcHost).toList(),
          change: (host) => pcDevice = host,
        ),
        controlHost(
          title: 'Remote keyboard on the Controls page',
          prompt: 'Keyboard host',
          hint: 'Choose the desktop that receives your text and keys.',
          empty: 'Add an SSH device first.',
          selected: keyboardDevice,
          devices: savedDevices,
          change: (host) => keyboardDevice = host,
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
