import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/plasma_settings.dart';

class PlasmaTextSizeScreen extends StatefulWidget {
  const PlasmaTextSizeScreen({super.key, required this.settings});
  final PlasmaSettings settings;

  @override
  State<PlasmaTextSizeScreen> createState() => _PlasmaTextSizeScreenState();
}

class _PlasmaTextSizeScreenState extends State<PlasmaTextSizeScreen> {
  double? _active;
  double _size = 10;
  String? _family, _error;
  bool _busy = false;
  bool _sizesMatch = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read({bool apply = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.settings.run({
        'action': 'text',
        if (apply) 'size': _size,
      });
      if (!mounted) return;
      setState(() {
        _active = (result['size'] as num).toDouble();
        _size = _active!;
        _family = result['family'] as String;
        _sizesMatch = result['sizesMatch'] == true;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError ? error.message : '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(double size) =>
      '${size == size.roundToDouble() ? size.round() : size} pt';

  @override
  Widget build(BuildContext context) {
    final lowest = math.min(6.0, _size);
    final highest = math.max(32.0, _size);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plasma text size'),
        actions: [
          IconButton(
            tooltip: 'Refresh text size',
            onPressed: _busy ? null : _read,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_active != null)
              Text('General font · ${_label(_active!)} · $_family'),
            if (_active != null && !_sizesMatch)
              const Text('Apply to update font groups that use other sizes.'),
            const SizedBox(height: 16),
            Text(
              _label(_size),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Slider(
              value: _size,
              min: lowest,
              max: highest,
              divisions: (highest - lowest).round() * 2,
              label: _label(_size),
              onChanged: _busy || _active == null
                  ? null
                  : (size) => setState(
                      () => _size = (size.clamp(6, 32) * 2).round() / 2,
                    ),
            ),
            Text(
              'Sample text',
              style: TextStyle(fontSize: (_size * 1.6).clamp(8, 52)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed:
                  _busy || _active == null || (_sizesMatch && _size == _active)
                  ? null
                  : () => _read(apply: true),
              icon: const Icon(Icons.text_fields),
              label: const Text('Apply text size'),
            ),
            TextButton(
              onPressed: _busy || _active == null
                  ? null
                  : () => setState(() => _size = 10),
              child: const Text('Select Plasma default (10 pt)'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Changes the size of Plasma interface fonts, including menus, toolbars, and titles. GTK apps can use the desktop font. Some apps have their own text settings.',
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
