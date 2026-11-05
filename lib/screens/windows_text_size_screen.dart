import 'package:flutter/material.dart';

import '../services/windows_text_size.dart';
import '../ssh/ssh_session.dart';

class WindowsTextSizeScreen extends StatefulWidget {
  final SshSession session;
  const WindowsTextSizeScreen({super.key, required this.session});
  @override
  State<WindowsTextSizeScreen> createState() => _WindowsTextSizeScreenState();
}

class _WindowsTextSizeScreenState extends State<WindowsTextSizeScreen> {
  int? _active;
  double _selected = 100;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run({bool apply = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = apply
          ? await applyWindowsTextSize(widget.session, _selected.round())
          : await readWindowsTextSize(widget.session);
      if (mounted) {
        setState(() {
          _active = value;
          _selected = value.toDouble();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Windows text size'),
      actions: [
        IconButton(
          onPressed: _busy ? null : () => _run(),
          icon: const Icon(Icons.refresh),
          tooltip: 'Read active text size',
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _active == null
                ? 'Reading active text size…'
                : 'Active text size: $_active%',
          ),
          const SizedBox(height: 20),
          Text(
            '${_selected.round()}%',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Slider(
            value: _selected,
            min: 100,
            max: 225,
            divisions: 125,
            label: '${_selected.round()}%',
            onChanged: _busy || _active == null
                ? null
                : (v) => setState(() => _selected = v),
          ),
          Text('Sample text', style: TextStyle(fontSize: 18 * _selected / 100)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy || _active == null || _selected.round() == _active
                ? null
                : () => _run(apply: true),
            icon: const Icon(Icons.text_fields),
            label: const Text('Apply text size'),
          ),
          TextButton(
            onPressed: _busy || _active == null
                ? null
                : () => setState(() => _selected = 100),
            child: const Text('Select default (100%)'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          const Text(
            'Uses Windows Settings → Accessibility → Text size and its Apply button. Settings opens on the PC during the change. The Windows user must be signed in with the desktop unlocked. Some apps use their own font sizes or need reopening.',
          ),
        ],
      ),
    ),
  );
}
