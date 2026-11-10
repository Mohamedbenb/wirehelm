import 'package:flutter/material.dart';

import '../customization/local_customization.dart';

class DeviceSnapshotScreen extends StatefulWidget {
  const DeviceSnapshotScreen({super.key});

  @override
  State<DeviceSnapshotScreen> createState() => _DeviceSnapshotScreenState();
}

class _DeviceSnapshotScreenState extends State<DeviceSnapshotScreen> {
  Map<String, dynamic>? _baseline;
  Map<String, dynamic>? _current;
  bool _includeModules = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run('deviceSnapshotBaseline');
  }

  Future<void> _run(String operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await LocalCustomization.call(operation, {
        'includeModules': _includeModules,
      });
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (operation == 'captureDeviceSnapshot') {
          _current = snapshot;
        } else {
          _baseline = snapshot.isEmpty ? null : snapshot;
          _current = null;
          _includeModules =
              snapshot.isNotEmpty &&
              _sections(snapshot).containsKey('Root modules');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_baseline != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace saved snapshot?'),
          content: const Text('The next comparison will use the new snapshot.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    await _run('saveDeviceSnapshot');
  }

  Map<String, dynamic> _sections(Map<String, dynamic> snapshot) =>
      Map<String, dynamic>.from(snapshot['sections'] as Map);

  String _captureTime(Map<String, dynamic> snapshot) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      snapshot['capturedAt'] as int,
    );
    final format = MaterialLocalizations.of(context);
    return '${format.formatShortDate(date)} · '
        '${format.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  List<Widget> _comparison(
    Map<String, dynamic> baseline,
    Map<String, dynamic> current,
  ) {
    final before = _sections(baseline);
    final after = _sections(current);
    final groups = <Widget>[];
    for (final section in after.keys.where(before.containsKey)) {
      final old = before[section] as Map;
      final updated = after[section] as Map;
      final changed = {
        ...old.keys.cast<String>(),
        ...updated.keys.cast<String>(),
      }.where((key) => old[key] != updated[key]).toList()..sort();
      if (changed.isEmpty) continue;
      groups.add(
        ExpansionTile(
          title: Text(section),
          subtitle: Text('${changed.length} changed'),
          initiallyExpanded: section != 'Apps',
          children: [
            for (final key in changed)
              ListTile(
                title: Text(key),
                subtitle: Text(
                  !old.containsKey(key)
                      ? 'Newly listed · ${updated[key]}'
                      : !updated.containsKey(key)
                      ? 'No longer listed · ${old[key]}'
                      : '${old[key]} → ${updated[key]}',
                ),
              ),
          ],
        ),
      );
    }
    return groups.isEmpty
        ? [const ListTile(title: Text('No changes in the sections compared.'))]
        : groups;
  }

  @override
  Widget build(BuildContext context) {
    final baseline = _baseline;
    final current = _current;
    final baselineNotes = baseline?['unavailable'] as Map? ?? const {};
    final currentNotes = current?['unavailable'] as Map? ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('What changed?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Save a baseline while your phone is working well. Compare it later to see changes to Android, launchable apps, root modules, and Wirehelm’s SystemUI hook.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include root modules'),
            subtitle: const Text(
              'Reads module versions and state. Your root manager may ask for access.',
            ),
            value: _includeModules,
            onChanged: _busy
                ? null
                : (value) => setState(() => _includeModules = value),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : _loaded
                    ? _save
                    : () => _run('deviceSnapshotBaseline'),
                child: Text(
                  !_loaded
                      ? 'Load snapshot'
                      : baseline == null
                      ? 'Save snapshot'
                      : 'Replace snapshot',
                ),
              ),
              OutlinedButton(
                onPressed: _busy || baseline == null
                    ? null
                    : () => _run('captureDeviceSnapshot'),
                child: const Text('Compare now'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (baseline != null) ...[
            const SizedBox(height: 16),
            Text('Baseline saved ${_captureTime(baseline)}'),
            for (final note in baselineNotes.entries)
              Text('Baseline · ${note.value}'),
          ],
          if (current != null) ...[
            const SizedBox(height: 12),
            Text('Compared ${_captureTime(current)}'),
            for (final note in currentNotes.entries)
              Text('Current · ${note.value}'),
            ..._comparison(baseline!, current),
          ],
        ],
      ),
    );
  }
}
