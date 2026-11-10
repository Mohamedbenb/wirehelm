import 'dart:async';

import 'package:flutter/material.dart';

import '../customization/local_customization.dart';

class ButtonShortcutsScreen extends StatefulWidget {
  const ButtonShortcutsScreen({super.key});

  @override
  State<ButtonShortcutsScreen> createState() => _ButtonShortcutsScreenState();
}

class _ButtonShortcutsScreenState extends State<ButtonShortcutsScreen>
    with WidgetsBindingObserver {
  static const actions = {
    'none': 'No shortcut',
    'torch': 'Toggle flashlight',
    'resume_media': 'Resume media',
    'timed_torch': 'Timed flashlight',
    'ringer': 'Vibrate ↔ Ring',
    'dnd': 'Do Not Disturb for 30 minutes',
    'bookmark': 'Bookmark this moment',
  };
  static const gestures = {
    '': 'Long press',
    '_double': 'Double tap',
    '_triple': 'Triple tap',
    '_tap_hold': 'Tap, then hold',
  };

  final _bindings = <String, String>{};
  double _holdMs = 800;
  double _torchMinutes = 5;
  String _state = 'Loading';
  String? _error;
  bool _busy = false;
  bool _supported = false;
  bool _alarmAccess = false;
  bool _dndAccess = false;
  bool _powerAvailable = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh(loadChoices: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh({bool loadChoices = false}) async {
    if (_busy) return;
    try {
      final status = await LocalCustomization.call('buttonShortcutsStatus');
      if (!mounted || _busy) return;
      setState(() {
        _updateStatus(status);
        if (loadChoices) {
          _bindings
            ..clear()
            ..addAll(Map<String, String>.from(status['extra'] as Map? ?? {}))
            ..['up'] = status['up'] as String
            ..['down'] = status['down'] as String;
          _holdMs = (status['holdMs'] as num).toDouble();
          _torchMinutes = (status['torchMinutes'] as num? ?? 5).toDouble();
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _updateStatus(Map<String, dynamic> status) {
    _state = status['state'] as String;
    _supported = status['supported'] == true;
    _alarmAccess = status['alarmAccess'] == true;
    _dndAccess = status['dndAccess'] == true;
    _powerAvailable = status['powerAvailable'] == true;
    final error = status['error'] as String?;
    _error = error == null || error.isEmpty ? null : error;
    if (_state == 'Starting' || _state == 'Listening') {
      _poll ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refresh()),
      );
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _apply({bool start = false, bool stop = false}) async {
    setState(() => _busy = true);
    try {
      final status = stop
          ? await LocalCustomization.call('stopButtonShortcuts')
          : await LocalCustomization.call('saveButtonShortcuts', {
              'up': _bindings['up'] ?? 'none',
              'down': _bindings['down'] ?? 'none',
              'holdMs': _holdMs.round(),
              'extra': {
                for (final entry in _bindings.entries)
                  if (entry.key != 'up' && entry.key != 'down')
                    entry.key: entry.value,
              },
              'torchMinutes': _torchMinutes.round(),
            });
      final result = start
          ? await LocalCustomization.call('startButtonShortcuts')
          : status;
      if (mounted) setState(() => _updateStatus(result));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAccess(String type) async {
    try {
      await LocalCustomization.call('buttonShortcutAccess', {'type': type});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _button(String key, String title, {bool expanded = false}) =>
      ExpansionTile(
        title: Text(title),
        initiallyExpanded: expanded,
        tilePadding: EdgeInsets.zero,
        children: [
          if (key == 'power' && _supported && !_powerAvailable)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Android’s double-press shortcut has priority'),
              subtitle: const Text(
                'Turn it off in Settings → System → Gestures to use Power shortcuts here.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openAccess('power'),
            ),
          for (final gesture in gestures.entries)
            if (key != 'power' ||
                gesture.key == '_double' ||
                gesture.key == '_triple')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _action(
                  gesture.value,
                  _bindings[key + gesture.key] ?? 'none',
                  (value) => _bindings[key + gesture.key] = value,
                ),
              ),
        ],
      );

  DropdownButtonFormField<String> _action(
    String label,
    String current,
    ValueChanged<String> setAction,
  ) => DropdownButtonFormField<String>(
    initialValue: current,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final action in actions.entries)
        DropdownMenuItem(value: action.key, child: Text(action.value)),
    ],
    onChanged: !_supported || _busy
        ? null
        : (value) => setState(() => setAction(value!)),
  );

  @override
  Widget build(BuildContext context) {
    final monitoring = _state == 'Starting' || _state == 'Listening';
    final hasTimedTorch = _bindings.containsValue('timed_torch');
    final hasDnd = _bindings.containsValue('dnd');
    return Scaffold(
      appBar: AppBar(title: const Text('Screen-off buttons')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'These gestures run with the screen off and audio idle. '
            'Android also receives every press and may change the volume.',
          ),
          const SizedBox(height: 16),
          _button('up', 'Volume Up', expanded: true),
          _button('down', 'Volume Down'),
          _button('power', 'Power'),
          const SizedBox(height: 16),
          Text('Minimum hold · ${(_holdMs / 1000).toStringAsFixed(1)} s'),
          Slider(
            value: _holdMs,
            min: 500,
            max: 2000,
            divisions: 15,
            onChanged: !_supported || _busy
                ? null
                : (value) => setState(() => _holdMs = value),
          ),
          if (hasTimedTorch) ...[
            Text('Flashlight timer · ${_torchMinutes.round()} min'),
            Slider(
              value: _torchMinutes,
              min: 1,
              max: 15,
              divisions: 14,
              onChanged: !_supported || _busy
                  ? null
                  : (value) => setState(() => _torchMinutes = value),
            ),
          ],
          if (_supported && (hasTimedTorch || hasDnd) && !_alarmAccess)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Alarms & reminders'),
              subtitle: const Text('Required for timed shortcuts'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openAccess('alarms'),
            ),
          if (_supported && hasDnd && !_dndAccess)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Do Not Disturb access'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openAccess('policy'),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Moment bookmarks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const _ButtonBookmarksScreen()),
            ),
          ),
          const Text(
            'Power taps start with the screen off. Holding Power and Emergency SOS stay with Android. Root access is required.',
          ),
          const SizedBox(height: 12),
          Text('Status · $_state'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!_supported && _state != 'Loading')
            const Text('Requires the supported rooted Pixel firmware.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed:
                    !_supported ||
                        _busy ||
                        (!monitoring &&
                            !_bindings.values.any((value) => value != 'none'))
                    ? null
                    : () => _apply(start: !monitoring),
                child: Text(monitoring ? 'Save choices' : 'Start shortcuts'),
              ),
              if (monitoring)
                OutlinedButton(
                  onPressed: _busy ? null : () => _apply(stop: true),
                  child: const Text('Stop'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ButtonBookmarksScreen extends StatefulWidget {
  const _ButtonBookmarksScreen();

  @override
  State<_ButtonBookmarksScreen> createState() => _ButtonBookmarksScreenState();
}

class _ButtonBookmarksScreenState extends State<_ButtonBookmarksScreen> {
  List<Map<String, dynamic>>? _bookmarks;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({String? id, String? note}) async {
    try {
      final result = id == null
          ? await LocalCustomization.call('buttonBookmarks')
          : await LocalCustomization.call('updateButtonBookmark', {
              'id': id,
              'note': note,
            });
      if (!mounted) return;
      setState(() {
        _error = null;
        _bookmarks = (result['bookmarks'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    var note = item['note'] as String;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bookmark note'),
        content: TextFormField(
          initialValue: note,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          onChanged: (value) => note = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      await _load(id: item['id'] as String, note: note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = _bookmarks;
    final local = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moment bookmarks'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh bookmarks',
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : bookmarks == null
          ? const Center(child: CircularProgressIndicator())
          : bookmarks.isEmpty
          ? const Center(child: Text('No moments bookmarked yet.'))
          : ListView.builder(
              itemCount: bookmarks.length,
              itemBuilder: (context, index) {
                final item = bookmarks[index];
                final date = DateTime.fromMillisecondsSinceEpoch(
                  item['at'] as int,
                );
                final note = item['note'] as String;
                return ListTile(
                  title: Text(
                    '${local.formatShortDate(date)} · '
                    '${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                  ),
                  subtitle: Text(note.isEmpty ? 'Add a note' : note),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(item),
                );
              },
            ),
    );
  }
}
