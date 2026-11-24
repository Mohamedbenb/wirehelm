import 'dart:async';

import 'package:flutter/material.dart';

import '../services/smart_bulb.dart';

class SmartBulbScreen extends StatefulWidget {
  const SmartBulbScreen({super.key, required this.bulb});

  final SmartBulb bulb;

  @override
  State<SmartBulbScreen> createState() => _SmartBulbScreenState();
}

typedef _BulbAppearance = ({
  bool color,
  int brightness,
  int temperature,
  int hue,
  int saturation,
});

class _SmartBulbScreenState extends State<SmartBulbScreen> {
  static const _liveUpdateInterval = Duration(milliseconds: 120);
  SmartBulbState? _state;
  SmartBulbException? _error;
  String? _activity;
  bool _color = false;
  int _whiteBrightness = 100;
  int _temperature = 50;
  int _hue = 0;
  int _saturation = 100;
  int _colorBrightness = 100;
  _BulbAppearance? _queuedAppearance;
  Timer? _updateDelay;
  bool _sendingAppearance = false;
  bool _sendImmediately = false;
  bool _leaving = false;

  bool get _busy =>
      _activity != null || _sendingAppearance || _queuedAppearance != null;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _leaving = true;
    // Deliver the final setting even if the screen closes before the reply.
    _scheduleAppearance(immediately: true);
    super.dispose();
  }

  void _setStateFromBulb(SmartBulbState data) {
    _state = data;
    _color = data.mode == 'colour';
    _whiteBrightness = data.whiteBrightness;
    _temperature = data.temperature;
    _hue = data.hue;
    _saturation = data.saturation;
    _colorBrightness = data.colorBrightness;
    _error = null;
  }

  Future<void> _request(
    String activity,
    Future<SmartBulbState> Function() operation,
  ) async {
    if (_busy) return;
    setState(() {
      _activity = activity;
      _error = null;
    });
    try {
      final data = await operation();
      if (mounted) setState(() => _setStateFromBulb(data));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _requestError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _activity = null);
    }
  }

  Future<void> _refresh() => _request('Reading bulb…', widget.bulb.read);

  Future<void> _configure() async {
    final state = await showDialog<SmartBulbState>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BulbConnectionDialog(bulb: widget.bulb, current: _state),
    );
    if (mounted && state != null) setState(() => _setStateFromBulb(state));
  }

  SmartBulbException _requestError(Object error) => error is SmartBulbException
      ? error
      : const SmartBulbException(
          'The request failed. Check the SSH connection and try again.',
        );

  _BulbAppearance get _appearance => (
    color: _color,
    brightness: _color ? _colorBrightness : _whiteBrightness,
    temperature: _temperature,
    hue: _hue,
    saturation: _saturation,
  );

  void _changeAppearance(VoidCallback change, {bool immediately = false}) {
    final previous = _appearance;
    change();
    final next = _appearance;
    if (next == previous && _error == null) return;
    setState(() {
      _queuedAppearance = next;
      _error = null;
    });
    _scheduleAppearance(immediately: immediately);
  }

  void _scheduleAppearance({bool immediately = false}) {
    if (immediately) {
      _sendImmediately = true;
      _updateDelay?.cancel();
      _updateDelay = null;
    }
    if (_queuedAppearance == null || _sendingAppearance) return;
    if (_sendImmediately) {
      unawaited(_sendAppearance());
    } else {
      _updateDelay ??= Timer(_liveUpdateInterval, () {
        _updateDelay = null;
        unawaited(_sendAppearance());
      });
    }
  }

  Future<void> _sendAppearance() async {
    final appearance = _queuedAppearance;
    if (appearance == null || _sendingAppearance) return;
    _sendingAppearance = true;
    _queuedAppearance = null;
    _sendImmediately = false;
    try {
      _state = appearance.color
          ? await widget.bulb.color(
              appearance.brightness,
              appearance.hue,
              appearance.saturation,
            )
          : await widget.bulb.white(
              appearance.brightness,
              appearance.temperature,
            );
      // Keep the sliders where the user moved them while the request was running.
      _error = null;
    } catch (error) {
      _error = _queuedAppearance == null ? _requestError(error) : null;
    } finally {
      _sendingAppearance = false;
      if (mounted && !_leaving) setState(() {});
      _scheduleAppearance(immediately: _leaving);
    }
  }

  Widget _slider(
    String name,
    int value,
    ValueChanged<int> change, {
    int min = 0,
    int max = 100,
    String suffix = '%',
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(name)),
          Text('$value$suffix'),
        ],
      ),
      Slider(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        semanticFormatterCallback: (position) => '${position.round()}$suffix',
        onChanged: _activity == null
            ? (position) => _changeAppearance(() => change(position.round()))
            : null,
        onChangeEnd: (_) {
          if (_queuedAppearance != null) {
            _scheduleAppearance(immediately: true);
          }
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;
    final busy = _busy;
    final error = _error;
    final color = HSVColor.fromAHSV(
      1,
      _hue.toDouble(),
      _saturation / 100,
      _colorBrightness / 100,
    ).toColor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart bulb'),
        actions: [
          IconButton(
            tooltip: 'Refresh bulb state',
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Bulb connection settings',
            onPressed: busy || error?.code == 'dependency' ? null : _configure,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Via ${widget.bulb.device.name}',
              style: theme.textTheme.bodySmall,
            ),
            if (_activity != null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(_activity!),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error.message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              if (error.code == 'dependency')
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: busy
                        ? null
                        : () => _request('Installing TinyTuya…', () async {
                            await widget.bulb.install();
                            return widget.bulb.read();
                          }),
                    child: const Text('Install TinyTuya'),
                  ),
                ),
              if (error.code == 'configuration')
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: busy ? null : _configure,
                    child: const Text('Set up bulb'),
                  ),
                ),
            ],
            if (state != null) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Power'),
                  subtitle: Text(state.on ? 'On' : 'Off'),
                  secondary: Icon(
                    state.on ? Icons.lightbulb : Icons.lightbulb_outline,
                    color: state.on ? theme.colorScheme.primary : null,
                  ),
                  value: state.on,
                  onChanged: busy
                      ? null
                      : (on) => _request(
                          on ? 'Turning on…' : 'Turning off…',
                          () => widget.bulb.power(on),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('White')),
                  ButtonSegment(value: true, label: Text('Color')),
                ],
                selected: {_color},
                onSelectionChanged: _activity != null
                    ? null
                    : (selected) => _changeAppearance(
                        () => _color = selected.single,
                        immediately: true,
                      ),
              ),
              const SizedBox(height: 20),
              if (_color) ...[
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 16),
                _slider(
                  'Hue',
                  _hue,
                  (value) => _hue = value,
                  max: 359,
                  suffix: '°',
                ),
                _slider(
                  'Saturation',
                  _saturation,
                  (value) => _saturation = value,
                ),
                _slider(
                  'Brightness',
                  _colorBrightness,
                  (value) => _colorBrightness = value,
                  min: 1,
                ),
              ] else ...[
                _slider(
                  'Brightness',
                  _whiteBrightness,
                  (value) => _whiteBrightness = value,
                  min: 1,
                ),
                _slider(
                  'White temperature',
                  _temperature,
                  (value) => _temperature = value,
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('Warm'), Text('Cool')],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BulbConnectionDialog extends StatefulWidget {
  const _BulbConnectionDialog({required this.bulb, this.current});

  final SmartBulb bulb;
  final SmartBulbState? current;

  @override
  State<_BulbConnectionDialog> createState() => _BulbConnectionDialogState();
}

class _BulbConnectionDialogState extends State<_BulbConnectionDialog> {
  late final _address = TextEditingController(text: widget.current?.address);
  late final _id = TextEditingController(text: widget.current?.deviceId);
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _id.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await widget.bulb.configure(
        address: _address.text.trim(),
        deviceId: _id.text.trim(),
        localKey: _key.text,
      );
      if (mounted) Navigator.pop(context, state);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is SmartBulbException
            ? error.message
            : 'Could not verify the connection to the bulb.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Bulb connection'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Local IP address'),
          ),
          TextField(
            controller: _id,
            enabled: !_busy,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Smart Life Virtual ID',
            ),
          ),
          TextField(
            controller: _key,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Tuya local key',
              helperText: widget.current == null
                  ? null
                  : 'Leave empty to reuse the saved key.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Checking…' : 'Save and connect'),
      ),
    ],
  );
}
