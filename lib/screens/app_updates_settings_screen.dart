import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/device_storage.dart';
import '../services/app_update.dart';
import '../devices/device_connection_service.dart';
import '../devices/host_key_dialogs.dart';
import '../ssh/ssh_session_manager.dart';
import 'app_update_screen.dart';

class AppUpdatesSettingsScreen extends StatefulWidget {
  const AppUpdatesSettingsScreen({super.key});
  @override
  State<AppUpdatesSettingsScreen> createState() =>
      _AppUpdatesSettingsScreenState();
}

class _AppUpdatesSettingsScreenState extends State<AppUpdatesSettingsScreen> {
  List<Device> _devices = [];
  String? _source, _error;
  String? _installed;
  bool _loading = true, _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final devices = await DeviceStorage().loadDevices();
      final prefs = await SharedPreferences.getInstance();
      final info = await AppUpdate.channel.invokeMapMethod<String, dynamic>(
        'installed',
      );
      final saved = prefs.getString('apk_update_source');
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _installed = info == null
            ? null
            : '${info['version']} (${info['build']})';
        _source = devices.any((d) => d.id == saved) ? saved : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _open({bool speedTest = false}) async {
    final device = _devices.firstWhere((d) => d.id == _source);
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('apk_update_source', device.id);
      final session = sshSessions.sessionFor(device.id);
      if (!session.isConnected) {
        await DeviceConnectionService().connect(
          device,
          targetSession: session,
          verifyHostKey: (device, type, fingerprint) async {
            if (!mounted) return false;
            return HostKeyDialogs().verifyHostKey(
              context: context,
              device: device,
              keyType: type,
              fingerprintBytes: fingerprint,
            );
          },
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppUpdateScreen(
            device: device,
            session: session,
            startSpeedTest: speedTest,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App updates')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose the device that stores the Node Cockpit APK. Your source and APK path are remembered. The app connects through LAN or Tailscale as needed.',
          ),
          const SizedBox(height: 20),
          if (_installed != null) Text('Installed: $_installed'),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_devices.isEmpty)
            const Text('Add an SSH device first to download updates.')
          else
            DropdownButtonFormField<String>(
              initialValue: _source,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Update source',
                border: OutlineInputBorder(),
              ),
              items: _devices
                  .map(
                    (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                  )
                  .toList(),
              onChanged: _connecting
                  ? null
                  : (value) async {
                      setState(() => _source = value);
                      final prefs = await SharedPreferences.getInstance();
                      if (value != null) {
                        await prefs.setString('apk_update_source', value);
                      }
                    },
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _source == null || _connecting ? null : () => _open(),
            icon: const Icon(Icons.system_update),
            label: Text(_connecting ? 'Connecting…' : 'Continue to download'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _source == null || _connecting
                ? null
                : () => _open(speedTest: true),
            icon: const Icon(Icons.speed),
            label: const Text('Test download speed'),
          ),
          const Text(
            'The speed test downloads the APK twice to compare network-only transfer with the full updater. Both copies are discarded without installing.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(_error!),
            ),
        ],
      ),
    ),
  );
}
