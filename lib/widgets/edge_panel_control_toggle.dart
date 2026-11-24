import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customization/local_customization.dart';

enum EdgePanelControl {
  bulb('bulb', 'Smart bulb', 'bulbDevice'),
  power('power', 'PC power', 'pcDevice'),
  textSize('text', 'PC text size', 'pcDevice'),
  keyboard('keyboard', 'Remote keyboard', 'keyboardDevice');

  const EdgePanelControl(this.id, this.label, this.hostKey);

  final String id;
  final String label;
  final String hostKey;
}

const defaultEdgeControls = ['bulb', 'power', 'text'];

class EdgePanelControlToggle extends StatefulWidget {
  const EdgePanelControlToggle({
    super.key,
    required this.control,
    required this.deviceId,
  });

  final EdgePanelControl control;
  final String deviceId;

  @override
  State<EdgePanelControlToggle> createState() => _EdgePanelControlToggleState();
}

class _EdgePanelControlToggleState extends State<EdgePanelControlToggle> {
  bool? _shown;
  String _host = '';
  String? _error;
  bool _saving = false;
  bool _available = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _update(Map<String, dynamic> result) {
    final saved = jsonDecode(result['raw'] as String) as Map;
    final controls = saved['controls'] as List? ?? defaultEdgeControls;
    setState(() {
      _shown = controls.contains(widget.control.id);
      _host = saved[widget.control.hostKey] as String? ?? '';
      _error = null;
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final settings = await LocalCustomization.call('edgeActions');
      if (mounted) _update(settings);
    } on MissingPluginException {
      if (mounted) setState(() => _available = false);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load panel settings. Tap to retry.');
      }
    }
  }

  Future<void> _save(bool shown) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = await LocalCustomization.call(
        'setEdgeControlVisibility',
        {
          'control': widget.control.id,
          'shown': shown,
          'device': widget.deviceId,
        },
      );
      if (mounted) _update(settings);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save panel settings. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    const title = Text('Show in Edge panel');
    const icon = Icon(Icons.view_sidebar_outlined);
    if (_shown == null && _error != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: title,
        subtitle: Text(_error!),
        onTap: _load,
      );
    }
    final hint =
        _error ??
        (_shown == true && _host.isNotEmpty && _host != widget.deviceId
            ? 'The panel uses a different host selected in Panel actions.'
            : null);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: icon,
      title: title,
      subtitle: hint == null ? null : Text(hint),
      value: _shown ?? false,
      onChanged: _shown == null || _saving ? null : _save,
    );
  }
}
