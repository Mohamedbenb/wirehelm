import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../customization/local_customization.dart';

class NotificationUndoScreen extends StatefulWidget {
  const NotificationUndoScreen({super.key});
  @override
  State<NotificationUndoScreen> createState() => _NotificationUndoScreenState();
}
class _NotificationUndoScreenState extends State<NotificationUndoScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _state = {};
  bool _working = false;
  String? _error;
  Map<String, dynamic> get _config => Map<String, dynamic>.from((_state['config'] as Map?) ?? {'enabled': false, 'shake': true, 'button': true, 'sensitivity': 1});
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _call('notificationUndoState'); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _call('notificationUndoState'); }
  Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    if (_working) return;
    setState(() { _working = true; _error = null; });
    try {
      final value = await LocalCustomization.call(method, args);
      if (mounted) setState(() => _state = value);
    } catch (e) {
      if (mounted) setState(() => _error = e is PlatformException ? (e.message ?? 'Unable to complete the request.') : '$e');
    } finally { if (mounted) setState(() => _working = false); }
  }
  Future<void> _save(Map<String, dynamic> changes) => _call('applyNotificationUndo', {'config': jsonEncode({..._config, ...changes})});
  Future<void> _postSample() async {
    if (_working) return;
    if (_state['notificationsAllowed'] != true) {
      await _call('requestSampleNotificationPermission');
      if (!mounted || _state['notificationsAllowed'] != true) return;
    }
    await _call('postNotificationUndoSample');
  }
  @override
  Widget build(BuildContext context) {
    final config = _config;
    final enabled = config['enabled'] == true;
    final shake = config['shake'] != false;
    final sample = Map<String, dynamic>.from((_state['sample'] as Map?) ?? {});
    final status = '${_state['status'] ?? 'Waiting for SystemUI'}';
    final skip = RegExp(r'lastSkip=([^;]+)').firstMatch(status)?.group(1);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Undo')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Undo a dismissed notification', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('Swipe a notification away, then tap Undo or shake twice within five seconds. The original notification returns with its original actions.'),
        const SizedBox(height: 16),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable Notification Undo'), subtitle: const Text('Stays enabled after locking, unlocking and restarting SystemUI.'), value: enabled, onChanged: _working ? null : (value) => _save({'enabled': value})),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Undo button'), subtitle: const Text('Turn off for shake-only Undo.'), value: config['button'] != false, onChanged: _working ? null : (value) => _save({'button': value})),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Shake to Undo'), subtitle: const Text('Listens only after a dismissal, including on the awake lock screen.'), value: shake, onChanged: _working ? null : (value) => _save({'shake': value})),
        if (shake) DropdownButtonFormField<int>(key: ValueKey(config['sensitivity']), initialValue: (config['sensitivity'] as num?)?.toInt() ?? 1, decoration: const InputDecoration(labelText: 'Shake strength'), items: const [DropdownMenuItem(value: 0, child: Text('Gentle')), DropdownMenuItem(value: 1, child: Text('Standard')), DropdownMenuItem(value: 2, child: Text('Firm'))], onChanged: _working ? null : (value) => _save({'sensitivity': value ?? 1})),
        const SizedBox(height: 12),
        SizedBox(height: 2, child: _working ? const LinearProgressIndicator() : null),
        const SizedBox(height: 16),
        const Text('Works in the drawer and on the awake lock screen. Android controls which notifications are visible. Turning the screen off completes a pending dismissal; Undo stays enabled for the next one.'),
        const SizedBox(height: 12),
        const Text('Individual messages and original notification groups support Undo. Clear all, calls, media, foreground services and active reply fields keep their normal behavior.'),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 24),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Diagnostics and sample notification'), children: [
          const Text('Post a sample, swipe and Undo it, then try its original tap or Reply. Undo should leave the app dismissal count unchanged; expiry should increase it.'),
          const SizedBox(height: 12),
          if (_state['notificationsAllowed'] == false) ...[
            const Text('Allow Node Cockpit notifications to post the sample. Undo on other apps is independent of this permission.'),
            TextButton(onPressed: _working ? null : () => _call('requestSampleNotificationPermission'), child: const Text('Allow sample notifications')),
            TextButton(onPressed: _working ? null : () => _call('openSampleNotificationSettings'), child: const Text('Open notification settings')),
          ],
          OutlinedButton(onPressed: _working ? null : _postSample, child: const Text('Post sample notification')),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: Text('Samples posted: ${sample['posts'] ?? 0}\nOriginal replies received: ${sample['replies'] ?? 0}\nApp dismissals received: ${sample['deletes'] ?? 0}')),
          const SizedBox(height: 8),
          const Text('Reply text is not stored. A new sample replaces the previous sample.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _working ? null : () => _call('notificationUndoState'), icon: const Icon(Icons.refresh), label: const Text('Refresh status')),
          if (skip != null && skip != 'none') Align(alignment: Alignment.centerLeft, child: Text('Last excluded dismissal: $skip')),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ]),
    );
  }
}
