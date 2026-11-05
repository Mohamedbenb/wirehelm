import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/device_discovery.dart';
import '../transport/tsnet_client.dart';
import 'add_device_screen.dart';

class DiscoverDevicesScreen extends StatefulWidget {
  final List<Device> savedDevices;
  final DiscoverySnapshot snapshot;
  const DiscoverDevicesScreen({
    super.key,
    required this.savedDevices,
    required this.snapshot,
  });
  @override
  State<DiscoverDevicesScreen> createState() => _DiscoverDevicesScreenState();
}

class _DiscoverDevicesScreenState extends State<DiscoverDevicesScreen> {
  late DeviceDiscovery discovery;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    discovery = DeviceDiscovery(() {
      if (mounted) setState(() {});
    });
    discovery.devices.addAll(widget.snapshot.devices);
    error = widget.snapshot.error;
    if (TsnetClient.supported && !widget.snapshot.searched) refresh();
  }

  @override
  void dispose() {
    widget.snapshot.devices
      ..clear()
      ..addAll(discovery.devices);
    widget.snapshot.error = error;
    discovery.cancelled = true;
    super.dispose();
  }

  Future<void> perform(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() => perform(() async {
    widget.snapshot.searched = true;
    discovery.devices.clear();
    final errors = <String>[];
    await Future.wait([
      discovery.tailnet().catchError((Object e) {
        errors.add('Tailscale: $e');
      }),
      discovery.lan(widget.savedDevices).catchError((Object e) {
        errors.add('LAN: $e');
      }),
    ]);
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  });

  Future<void> add(DiscoveredDevice found) async {
    final local = found.source == 'LAN';
    final device = await Navigator.of(context).push<Device>(
      MaterialPageRoute(
        builder: (_) => AddDeviceScreen(
          initialName: found.name,
          initialHost: found.host,
          initialLocalHost: local ? found.host : '',
          initialPort: found.port,
          initialShellStyle: found.os.toLowerCase().contains('windows')
              ? 'windows'
              : found.os.toLowerCase().contains('linux')
              ? 'linux'
              : 'auto',
        ),
      ),
    );
    if (device != null && mounted) Navigator.of(context).pop(device);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Discover devices'),
      actions: [
        IconButton(
          tooltip: 'Refresh discovery',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !TsnetClient.supported
        ? const Center(child: Text('Discovery currently requires Android.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Tailscale lists peers visible to this app. LAN finds advertised services and saved local hosts. Names alone do not prove that two addresses belong to the same device.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => perform(discovery.scanLan),
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Scan LAN for SSH'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => perform(discovery.checkAll),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Check SSH'),
                  ),
                ],
              ),
              const Text(
                'LAN scan checks SSH port 22 on up to 254 addresses in your Wi-Fi segment. It cannot find every LAN device.',
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!busy && discovery.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No devices found. Check Wi-Fi and sign in under Settings → Tailscale.',
                  ),
                ),
              for (final device in discovery.devices)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SelectableText(
                          '${device.source} · ${device.host}:${device.port}',
                        ),
                        if (device.os.isNotEmpty) Text(device.os),
                        if (device.online != null)
                          Text(
                            'Tailscale: ${device.online! ? "Online" : "Offline"}',
                          ),
                        if (device.lastSeen.isNotEmpty &&
                            device.online == false)
                          Text(
                            'Last seen: ${DateTime.tryParse(device.lastSeen)?.toLocal() ?? device.lastSeen}',
                          ),
                        Text(
                          device.reachable == null
                              ? 'SSH: not checked'
                              : device.ssh == true
                              ? 'SSH reachable'
                              : device.reachable!
                              ? 'Port open; SSH not confirmed'
                              : 'SSH unreachable',
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.savedDevices.any(
                              (saved) =>
                                  saved.host == device.host ||
                                  saved.localHost == device.host,
                            ))
                              const Text('Saved device')
                            else
                              TextButton.icon(
                                onPressed: () => add(device),
                                icon: const Icon(Icons.add),
                                label: const Text('Add'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
