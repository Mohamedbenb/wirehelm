import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/device_information.dart';
import '../ssh/ssh_session.dart';

class DeviceInformationScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  const DeviceInformationScreen({
    super.key,
    required this.device,
    required this.session,
  });
  @override
  State<DeviceInformationScreen> createState() =>
      _DeviceInformationScreenState();
}

class _DeviceInformationScreenState extends State<DeviceInformationScreen> {
  DeviceInformation? information;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await fetchDeviceInformation(widget.device, widget.session);
      if (mounted) setState(() => information = data);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget row(String label, String value) => ListTile(
    title: Text(label),
    subtitle: SelectableText(value.isEmpty ? 'Not reported' : value),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.device.name} information'),
      actions: [
        IconButton(
          tooltip: 'Refresh information',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          row('Internet host', widget.device.host),
          if (widget.device.localHost.isNotEmpty)
            row('Local host', widget.device.localHost),
          row('SSH port', '${widget.device.port}'),
          row('Account', widget.device.username),
          row('Status refresh', '${widget.device.refreshSeconds} seconds'),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (information != null) ...[
            Text(
              error == null ? 'System' : 'System (last loaded)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final entry in information!.system.entries)
              row(
                {
                      'hostname': 'Hostname',
                      'os': 'Operating system',
                      'kernel': 'Kernel / version',
                      'architecture': 'Architecture',
                      'cpu': 'CPU',
                      'model': 'Hardware',
                      'memory': 'Memory',
                      'uptime': 'Uptime',
                      'disk': 'System disk',
                      'user': 'Signed-in SSH account',
                    }[entry.key] ??
                    entry.key,
                entry.value,
              ),
            Text(
              'Network adapters',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (information!.adapters.isEmpty)
              const Text('No adapter information was reported.'),
            for (final adapter in information!.adapters)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    row('Adapter', adapter['name'] ?? ''),
                    row('State', adapter['status'] ?? ''),
                    if ((adapter['internet'] ?? '').toLowerCase() == 'true' ||
                        (adapter['internet'] ?? '') == 'yes')
                      const ListTile(
                        leading: Icon(Icons.public),
                        title: Text('Default route · likely internet path'),
                        subtitle: Text(
                          'The operating system sends internet-bound traffic through this adapter.',
                        ),
                      ),
                    row('IP addresses', adapter['ips'] ?? ''),
                    ListTile(
                      title: const Text('MAC address'),
                      subtitle: SelectableText(
                        adapter['mac']?.isNotEmpty == true
                            ? adapter['mac']!
                            : 'Not reported',
                      ),
                      trailing: IconButton(
                        tooltip: 'Copy MAC address',
                        onPressed: adapter['mac']?.isNotEmpty == true
                            ? () async {
                                await Clipboard.setData(
                                  ClipboardData(text: adapter['mac']!),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('MAC address copied'),
                                    ),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.copy),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Connected peripherals',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (information!.peripherals.isEmpty)
              const ListTile(
                leading: Icon(Icons.devices_other),
                title: Text('No attached peripherals reported'),
              ),
            for (final device in information!.peripherals)
              ListTile(
                leading: const Icon(Icons.usb),
                title: SelectableText(device),
              ),
          ],
        ],
      ),
    ),
  );
}
