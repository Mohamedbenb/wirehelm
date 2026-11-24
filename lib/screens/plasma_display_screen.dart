import 'dart:async';

import 'package:flutter/material.dart';

import '../services/plasma_settings.dart';

class PlasmaDisplayScreen extends StatefulWidget {
  const PlasmaDisplayScreen({super.key, required this.settings});
  final PlasmaSettings settings;

  @override
  State<PlasmaDisplayScreen> createState() => _PlasmaDisplayScreenState();
}

class _PlasmaDisplayScreenState extends State<PlasmaDisplayScreen> {
  static const _rotations = {
    1: 'Landscape',
    2: 'Left',
    4: 'Upside down',
    8: 'Right',
    16: 'Mirrored',
    32: 'Mirrored left',
    64: 'Mirrored upside down',
    128: 'Mirrored right',
  };

  final _x = TextEditingController();
  final _y = TextEditingController();
  List<PlasmaDisplay> _outputs = [];
  PlasmaDisplay? _selected;
  bool _enabled = false, _primary = false, _busy = false;
  int _rotation = 1;
  double _scale = 1;
  String? _mode, _mirror, _error, _message, _restoreToken;
  Timer? _restoreExpiry;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _restoreExpiry?.cancel();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _choose(PlasmaDisplay display) {
    _selected = display;
    _enabled = display.enabled;
    _primary = display.primary;
    _rotation = display.rotation;
    _scale = display.scale;
    _mode = display.currentMode;
    if (!display.modes.any((mode) => mode.id == _mode)) {
      _mode = display.modes.firstOrNull?.id;
    }
    _mirror = _outputs
        .where((item) => item.id == display.mirrorId)
        .firstOrNull
        ?.name;
    _x.text = display.x.toString();
    _y.text = display.y.toString();
  }

  void _readOutputs(Map<String, dynamic> result) {
    final selectedName = _selected?.name;
    _outputs = PlasmaDisplay.fromResponse(result);
    final display =
        _outputs.where((item) => item.name == selectedName).firstOrNull ??
        _outputs.where((item) => item.primary).firstOrNull ??
        _outputs.first;
    _choose(display);
    _restoreExpiry?.cancel();
    final remaining = result['restoreMs'] as int? ?? 0;
    _restoreToken = remaining > 0 ? result['restoreToken'] as String? : null;
    if (_restoreToken != null) {
      _restoreExpiry = Timer(Duration(milliseconds: remaining), () {
        if (mounted) setState(() => _restoreToken = null);
      });
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.settings.run({'action': 'displays'});
      if (mounted) setState(() => _readOutputs(result));
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) =>
      error is StateError ? error.message : '$error';

  Future<void> _apply() async {
    final output = _selected;
    if (output == null || _busy) return;
    final x = int.tryParse(_x.text.trim());
    final y = int.tryParse(_y.text.trim());
    if (x == null || y == null) {
      setState(
        () => _error = 'Enter a whole number for each display position.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.settings.run({
        'action': 'apply',
        'id': output.id,
        'name': output.name,
        'enabled': _enabled,
        'primary': _primary,
        'mode': _mode,
        'scale': _scale,
        'rotation': _rotation,
        'x': x,
        'y': y,
        'mirror': _mirror,
      });
      if (!mounted) return;
      setState(() {
        _readOutputs(result);
        _message = 'Display changes applied.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final token = _restoreToken;
    if (_busy || token == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.settings.run({
        'action': 'restore',
        'token': token,
      });
      if (!mounted) return;
      setState(() {
        _readOutputs(result);
        _message = 'Previous display settings restored.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _select<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? change,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          isExpanded: true,
          value: value,
          items: items,
          onChanged: change,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final canDisable = _outputs.any(
      (item) => item.name != selected?.name && item.enabled,
    );
    final scales = <double>{
      .5,
      .75,
      1,
      1.25,
      1.5,
      1.75,
      2,
      2.25,
      2.5,
      3,
      4,
      _scale,
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Display configuration'),
        actions: [
          IconButton(
            tooltip: 'Refresh displays',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: _restoreToken == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.undo),
                label: const Text('Restore previous settings'),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (selected != null) ...[
              _select<String>(
                label: 'Display',
                value: selected.name,
                items: [
                  for (final output in _outputs)
                    DropdownMenuItem(
                      value: output.name,
                      child: Text(
                        '${output.name}${output.primary && output.enabled
                            ? ' · Primary'
                            : !output.enabled
                            ? ' · Disabled'
                            : ''}',
                      ),
                    ),
                ],
                change: _busy
                    ? null
                    : (name) => setState(() {
                        _choose(
                          _outputs.firstWhere((item) => item.name == name),
                        );
                        _error = _message = null;
                      }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable display'),
                value: _enabled,
                onChanged: _busy || (_enabled && !canDisable)
                    ? null
                    : (enabled) => setState(() => _enabled = enabled),
              ),
              if (_enabled) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary display'),
                  value: _primary,
                  onChanged: _busy || selected.primary && selected.enabled
                      ? null
                      : (primary) => setState(() => _primary = primary),
                ),
                if (_mode != null)
                  _select<String>(
                    label: 'Resolution and refresh rate',
                    value: _mode!,
                    items: [
                      for (final mode in selected.modes)
                        DropdownMenuItem(
                          value: mode.id,
                          child: Text(mode.label),
                        ),
                    ],
                    change: _busy
                        ? null
                        : (mode) => setState(() => _mode = mode),
                  ),
                _select<double>(
                  label: 'Scale',
                  value: _scale,
                  items: [
                    for (final scale in scales)
                      DropdownMenuItem(
                        value: scale,
                        child: Text('${(scale * 100).round()}%'),
                      ),
                  ],
                  change: _busy
                      ? null
                      : (scale) => setState(() => _scale = scale!),
                ),
                _select<int>(
                  label: 'Orientation',
                  value: _rotation,
                  items: [
                    for (final rotation in _rotations.entries)
                      DropdownMenuItem(
                        value: rotation.key,
                        child: Text(rotation.value),
                      ),
                  ],
                  change: _busy
                      ? null
                      : (rotation) => setState(() => _rotation = rotation!),
                ),
                if (_outputs.length > 1) ...[
                  _select<String>(
                    label: 'Mirror display',
                    value: _mirror ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Independent'),
                      ),
                      for (final output in _outputs)
                        if (output.name != selected.name &&
                            (output.enabled || output.name == _mirror))
                          DropdownMenuItem(
                            value: output.name,
                            child: Text(output.name),
                          ),
                    ],
                    change: _busy
                        ? null
                        : (name) => setState(
                            () => _mirror = name == '' ? null : name,
                          ),
                  ),
                  if (_mirror == null)
                    Row(
                      children: [
                        Expanded(child: _position(_x, 'Horizontal (X)')),
                        const SizedBox(width: 12),
                        Expanded(child: _position(_y, 'Vertical (Y)')),
                      ],
                    ),
                ],
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || (_enabled && _mode == null) ? null : _apply,
                icon: const Icon(Icons.monitor),
                label: const Text('Apply display changes'),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _position(TextEditingController controller, String label) => TextField(
    controller: controller,
    enabled: !_busy,
    keyboardType: const TextInputType.numberWithOptions(signed: true),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
