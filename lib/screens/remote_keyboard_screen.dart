import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/remote_keyboard.dart';
import '../ssh/ssh_session.dart';

enum _KeyboardPad { keys, shortcuts }

class RemoteKeyboardScreen extends StatefulWidget {
  final Device device;
  final SshSession session;

  const RemoteKeyboardScreen({
    super.key,
    required this.device,
    required this.session,
  });

  @override
  State<RemoteKeyboardScreen> createState() => _RemoteKeyboardScreenState();
}

class _RemoteKeyboardScreenState extends State<RemoteKeyboardScreen> {
  final text = TextEditingController();
  bool busy = false;
  bool failed = false;
  String? message;
  String? sendingKey;
  bool? windows;
  String? lastSentText;
  _KeyboardPad pad = _KeyboardPad.keys;
  static const _availableKeys = <String>[
    'Escape',
    'Tab',
    'Backspace',
    'Delete',
    'Enter',
    'Left',
    'Right',
    'Up',
    'Down',
    'Home',
    'End',
    'Page Up',
    'Page Down',
    'Insert',
    'Space',
    'Print screen',
    'Pause',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
  ];
  static const _defaultKeys = <String>[
    'Escape',
    'Tab',
    'Backspace',
    'Enter',
    'Left',
    'Right',
    'Up',
    'Down',
    'Home',
    'End',
    'Page Up',
    'Page Down',
  ];
  static const _defaultShortcuts = <String>[
    'Enter',
    'Copy',
    'Paste',
    'Select all',
    'Undo',
    'Switch window',
    'F5',
    'F11',
  ];
  List<String> _shownKeys = List.of(_defaultKeys),
      _shownShortcuts = List.of(_defaultShortcuts);
  List<Map<String, String>> _customShortcuts = [];

  String get _layoutKey => 'remote_keyboard_layout_${widget.device.id}';

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_layoutKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedKeys = (data['keys'] as List?)
          ?.whereType<String>()
          .where(remoteKeys.containsKey)
          .toList();
      final savedCustom = (data['custom'] as List?)
          ?.whereType<Map>()
          .map((item) => Map<String, String>.from(item))
          .where((item) => item['name'] != null && item['chord'] != null)
          .toList();
      if (savedCustom != null) _customShortcuts = savedCustom;
      final savedShortcuts = (data['shortcuts'] as List?)
          ?.whereType<String>()
          .where(
            (key) =>
                remoteKeys.containsKey(key) ||
                _customShortcuts.any((item) => item['name'] == key),
          )
          .toList();
      if (savedShortcuts != null) {
        _shownShortcuts = savedShortcuts;
        // Build 24 omitted Enter from the shortcuts pad. Restore it once for
        // existing layouts, while preserving future user customization.
        if ((data['version'] as int? ?? 0) < 2 &&
            !_shownShortcuts.contains('Enter')) {
          _shownShortcuts.insert(0, 'Enter');
        }
      }
      if (savedKeys != null) _shownKeys = savedKeys;
    } catch (_) {
      /* Keep the built-in keyboard layout. */
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _layoutKey,
      jsonEncode({
        'version': 2,
        'keys': _shownKeys,
        'shortcuts': _shownShortcuts,
        'custom': _customShortcuts,
      }),
    );
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> send({String? key, String? shortcut}) async {
    if (busy) return;
    final value = text.text;
    final sendingText = key == null && shortcut == null;
    if (sendingText && value.isEmpty) return;
    setState(() {
      busy = true;
      failed = false;
      sendingKey = shortcut == null
          ? key
          : _customShortcuts.firstWhere(
              (item) => item['chord'] == shortcut,
            )['name'];
      message = null;
    });
    try {
      windows ??= widget.device.shellStyle == 'auto'
          ? !utf8
                .decode(
                  await widget.session.run(
                    'uname -s',
                    timeout: const Duration(seconds: 5),
                  ),
                  allowMalformed: true,
                )
                .contains('Linux')
          : widget.device.shellStyle == 'windows';
      await sendRemoteKeyboard(
        widget.device,
        widget.session,
        windows: windows!,
        key: key,
        shortcut: shortcut,
        text: sendingText ? value : null,
      );
      if (mounted) {
        setState(() {
          message = sendingText
              ? 'Text sent.'
              : shortcut != null
              ? 'Shortcut sent.'
              : '$key sent.';
          if (sendingText) {
            lastSentText = value;
            if (text.text == value) text.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _paste() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || busy || clipboard?.text == null) return;
    final selection = text.selection;
    final start = selection.isValid ? selection.start : text.text.length;
    final end = selection.isValid ? selection.end : start;
    final pasted = clipboard!.text!;
    text.value = TextEditingValue(
      text: text.text.replaceRange(start, end, pasted),
      selection: TextSelection.collapsed(offset: start + pasted.length),
    );
  }

  Future<void> _restore() async {
    final previous = lastSentText;
    if (busy || previous == null) return;
    if (text.text.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace this draft?'),
          content: const Text('Restore the last text sent to the device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    setState(() {
      text.value = TextEditingValue(
        text: previous,
        selection: TextSelection.collapsed(offset: previous.length),
      );
      lastSentText = null;
      message = null;
    });
  }

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Using the remote keyboard'),
      content: const SingleChildScrollView(
        child: Text(
          'Input goes to the focused window on the remote device. '
          'Type a draft here and tap Send text; typing alone sends nothing. '
          'The key pads send one key or shortcut per tap.\n\n'
          'Paste beside the text field inserts the phone clipboard into your '
          'draft. Paste in Shortcuts uses the remote device clipboard.\n\n'
          'Text clears after the remote input command completes. This confirms '
          'the command completed, not which app accepted the text. '
          'Restore last sent text brings your last draft back.\n\n'
          'Windows requires a signed-in desktop. Linux requires xdotool and '
          'access to the X11 display (DISPLAY, default :0). '
          'Wayland is not supported yet.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _key(String key) {
    final custom = _customShortcuts.cast<Map<String, String>?>().firstWhere(
      (item) => item?['name'] == key,
      orElse: () => null,
    );
    assert(remoteKeys.containsKey(key) || custom != null);
    final icon = switch (key) {
      'Left' => Icons.arrow_back,
      'Right' => Icons.arrow_forward,
      'Up' => Icons.arrow_upward,
      'Down' => Icons.arrow_downward,
      'Backspace' => Icons.backspace_outlined,
      _ => null,
    };
    final label = switch (key) {
      'Escape' => 'Esc',
      'Page Up' => 'PgUp',
      'Page Down' => 'PgDn',
      'Switch window' => 'Switch app',
      _ => key,
    };
    final description = custom != null
        ? '${custom['name']} (${custom['chord']}) on remote device'
        : switch (key) {
            'Copy' => 'Copy on remote device (Ctrl+C)',
            'Paste' => 'Paste on remote device (Ctrl+V)',
            'Select all' => 'Select all on remote device (Ctrl+A)',
            'Undo' => 'Undo on remote device (Ctrl+Z)',
            'Switch window' => 'Switch window on remote device (Alt+Tab)',
            _ => '$key on remote device',
          };
    final child = icon != null
        ? Icon(icon, size: 22)
        : Text(label, textAlign: TextAlign.center);
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Tooltip(
      message: description,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        button: true,
        enabled: !busy,
        onTap: busy
            ? null
            : () => custom == null
                  ? send(key: key)
                  : send(shortcut: custom['chord']),
        child: key == 'Enter'
            ? FilledButton.tonal(
                style: style,
                onPressed: busy
                    ? null
                    : () => custom == null
                          ? send(key: key)
                          : send(shortcut: custom['chord']),
                child: child,
              )
            : OutlinedButton(
                style: style,
                onPressed: busy
                    ? null
                    : () => custom == null
                          ? send(key: key)
                          : send(shortcut: custom['chord']),
                child: child,
              ),
      ),
    );
  }

  Widget _keyGrid(List<String> keys, {int maximumColumns = 4}) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (constraints.maxWidth / (68 * scale)).floor().clamp(
        2,
        maximumColumns,
      );
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: 52 * scale.clamp(1, 3),
        ),
        itemCount: keys.length,
        itemBuilder: (context, index) => _key(keys[index]),
      );
    },
  );

  Future<void> _addShortcut(StateSetter update, Set<String> selected) async {
    if (_customShortcuts.length >= 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can create up to 24 shortcuts.')),
      );
      return;
    }
    final name = TextEditingController(), chord = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create shortcut'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Button name'),
                validator: (value) =>
                    (value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 20 ||
                        [
                          ..._defaultShortcuts,
                          ..._customShortcuts.map((item) => item['name']!),
                        ].any(
                          (existing) =>
                              existing.toLowerCase() ==
                              value.trim().toLowerCase(),
                        ))
                    ? 'Enter a unique name (up to 20 characters)'
                    : null,
              ),
              TextFormField(
                controller: chord,
                decoration: const InputDecoration(
                  labelText: 'Keys',
                  hintText: 'Ctrl+Shift+Esc',
                ),
                validator: (value) {
                  try {
                    normalizeRemoteChord(value ?? '');
                    return null;
                  } catch (_) {
                    return 'Example: Ctrl+Alt+R';
                  }
                },
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
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'chord': chord.text.trim(),
                });
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    name.dispose();
    chord.dispose();
    if (result == null || !mounted) return;
    _customShortcuts = [..._customShortcuts, result];
    _shownShortcuts = [..._shownShortcuts, result['name']!];
    selected.add(result['name']!);
    update(() {});
    setState(() {});
    await _saveLayout();
  }

  Future<void> _customizeButtons() async {
    final keys = {..._shownKeys}, shortcuts = {..._shownShortcuts};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Customize keyboard buttons'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Keys'),
                  ),
                  for (final key in _availableKeys)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(key),
                      value: keys.contains(key),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          keys.add(key);
                        } else {
                          keys.remove(key);
                        }
                      }),
                    ),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Shortcuts'),
                  ),
                  for (final key in [
                    ..._defaultShortcuts,
                    ..._customShortcuts.map((item) => item['name']!),
                  ])
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: shortcuts.contains(key),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            shortcuts.add(key);
                          } else {
                            shortcuts.remove(key);
                          }
                        }),
                      ),
                      title: Text(key),
                      subtitle: _shortcutSubtitle(key),
                      trailing:
                          _customShortcuts.any((item) => item['name'] == key)
                          ? IconButton(
                              tooltip: 'Delete custom shortcut',
                              onPressed: () {
                                _customShortcuts.removeWhere(
                                  (item) => item['name'] == key,
                                );
                                shortcuts.remove(key);
                                _shownShortcuts.remove(key);
                                update(() {});
                                setState(() {});
                                unawaited(_saveLayout());
                              },
                              icon: const Icon(Icons.delete_outline),
                            )
                          : null,
                      onTap: () => update(() {
                        if (shortcuts.remove(key)) {
                          return;
                        }
                        shortcuts.add(key);
                      }),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addShortcut(update, shortcuts),
                      icon: const Icon(Icons.add),
                      label: const Text('Create shortcut'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                _shownKeys = _availableKeys.where(keys.contains).toList();
                _shownShortcuts = [
                  ..._defaultShortcuts.where(shortcuts.contains),
                  ..._customShortcuts
                      .map((item) => item['name']!)
                      .where(shortcuts.contains),
                ];
                await _saveLayout();
                if (mounted && context.mounted) {
                  setState(() {});
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _shortcutSubtitle(String name) {
    for (final item in _customShortcuts) {
      if (item['name'] == name) return Text(item['chord']!);
    }
    return null;
  }

  Widget _feedback() {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                failed ? Icons.error_outline : Icons.check_circle_outline,
                size: 18,
                color: failed ? colors.error : colors.primary,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                busy
                    ? sendingKey == null
                          ? 'Sending text…'
                          : 'Sending $sendingKey…'
                    : message!,
                style: TextStyle(color: failed ? colors.error : colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(56).clamp(56, 96),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remote keyboard',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Choose visible keys and shortcuts',
          onPressed: _customizeButtons,
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: 'Keyboard help',
          onPressed: _showHelp,
          icon: const Icon(Icons.help_outline),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Type text',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Paste from phone',
                        onPressed: busy ? null : _paste,
                        icon: const Icon(Icons.content_paste, size: 20),
                      ),
                    ],
                  ),
                  TextField(
                    controller: text,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Type here, then send',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'To the focused window',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: text,
                        builder: (context, value, child) => FilledButton.icon(
                          onPressed: busy || value.text.isEmpty
                              ? null
                              : () => send(),
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Send text'),
                        ),
                      ),
                    ],
                  ),
                  if (busy || message != null) _feedback(),
                  if (lastSentText != null)
                    TextButton.icon(
                      onPressed: busy ? null : _restore,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restore last sent text'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_KeyboardPad>(
            segments: const [
              ButtonSegment(
                value: _KeyboardPad.keys,
                icon: Icon(Icons.keyboard_outlined),
                label: Text('Keys'),
              ),
              ButtonSegment(
                value: _KeyboardPad.shortcuts,
                icon: Icon(Icons.touch_app_outlined),
                label: Text('Shortcuts'),
              ),
            ],
            selected: {pad},
            showSelectedIcon: false,
            onSelectionChanged: (selected) =>
                setState(() => pad = selected.single),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _customizeButtons,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Choose visible buttons · create shortcuts'),
            ),
          ),
          const SizedBox(height: 12),
          if (pad == _KeyboardPad.keys)
            _keyGrid(_shownKeys)
          else
            _keyGrid(_shownShortcuts, maximumColumns: 3),
        ],
      ),
    ),
  );
}
