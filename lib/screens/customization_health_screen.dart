import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customization/customization_health.dart';
import '../customization/local_customization.dart';

class CustomizationHealthScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  const CustomizationHealthScreen({super.key, required this.initialData});
  @override
  State<CustomizationHealthScreen> createState() =>
      _CustomizationHealthScreenState();
}

class _CustomizationHealthScreenState extends State<CustomizationHealthScreen>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _data = widget.initialData;
  Timer? _timer;
  bool _busy = false, _resumed = true;
  String? _error;
  DateTime? _updated;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_resumed) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool root = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await LocalCustomization.call('probe', {
        'requestRoot': root,
      });
      if (mounted) {
        setState(() {
          _data = next;
          _error = null;
          _updated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Expanded(
          child: SelectableText('${value ?? '—'}', textAlign: TextAlign.end),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final checks = customizationChecks(_data);
    final issues = checks.where((c) => c.attention).length;
    final colors = Theme.of(context).colorScheme;
    final root = healthSection(_data, 'root');
    final carrier = healthSection(_data, 'carrier');
    final hook = healthSection(_data, 'hook');
    final metrics = healthSection(hook, 'metrics');
    final events = ((_data['events'] as List?) ?? [])
        .whereType<Map>()
        .toList()
        .reversed;
    final json = const JsonEncoder.withIndent('  ').convert(_data);
    final rawAge = (hook['ageMs'] as num?)?.toInt() ?? -1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customization health'),
        actions: [
          IconButton(
            tooltip: 'Refresh health',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Card(
                color: issues == 0
                    ? colors.primaryContainer
                    : colors.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            issues == 0
                                ? Icons.verified_outlined
                                : Icons.troubleshoot,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              issues == 0
                                  ? 'Checks passing'
                                  : '$issues ${issues == 1 ? 'check needs' : 'checks need'} attention',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(indicatorStatus(_data)),
                      const SizedBox(height: 6),
                      Text(
                        _updated == null
                            ? 'Checking…'
                            : 'Live · refreshed ${TimeOfDay.fromDateTime(_updated!).format(context)}',
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 14, 8, 8),
                child: Text('Health checks'),
              ),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < checks.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(
                          checks[i].attention
                              ? Icons.info_outline
                              : Icons.check_circle_outline,
                          color: checks[i].attention
                              ? colors.tertiary
                              : colors.primary,
                        ),
                        title: Text(checks[i].title),
                        subtitle: Text(checks[i].detail),
                      ),
                    ],
                  ],
                ),
              ),
              _card('Live measurements', Icons.monitor_heart_outlined, [
                _row(
                  'Hook heartbeat age',
                  rawAge < 0
                      ? 'Not observed'
                      : '${(rawAge / 1000).toStringAsFixed(1)} s',
                ),
                _row('Download', '${metrics['downloadBps'] ?? '—'} B/s'),
                _row('Upload', '${metrics['uploadBps'] ?? '—'} B/s'),
                _row(
                  'Safety lease remaining',
                  '${((_data['safetyLeaseRemainingMs'] as num? ?? 0) / 1000).round()} s',
                ),
                if (metrics['cameraRing'] != null)
                  _row('Notification ring', metrics['cameraRing']),
                _row('Preference refreshes', metrics['preferenceUpdates']),
                _row('Window recovery scans', metrics['recoveryScans']),
                _row(
                  'Diagnostic delivery failures',
                  metrics['deliveryFailures'],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Counters are per SystemUI process. Measurements describe the latest hook report; fullscreen apps and the lock screen may hide the normal status bar.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _refresh(root: true),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Check root now'),
                ),
              ]),
              _card('Backend versions', Icons.extension_outlined, [
                _row('Framework', healthSection(_data, 'xposed')['version']),
                _row('KernelSU', healthSection(_data, 'kernelsu')['version']),
                _row('Recovery module', root['moduleVersion']),
                _row('Recovery protocol', root['protocol']),
                _row('Hook protocol', hook['version']),
                _row(
                  'Carrier module',
                  carrier['installed'] == true
                      ? '${carrier['moduleVersion'] ?? 'Legacy'} · ${carrier['moduleState']}'
                      : 'Not installed',
                ),
                _row(
                  'LSPosed',
                  healthSection(_data, 'lsposed')['installed'] == true
                      ? healthSection(_data, 'lsposed')['version']
                      : 'Not installed',
                ),
              ]),
              _card('Carrier profile', Icons.network_cell_outlined, [
                _row(
                  'Supported carrier',
                  carrier['supportedCarrierDetected'] == true
                      ? 'Detected'
                      : 'Not detected',
                ),
                _row('Default carrier ID', carrier['currentCarrierId']),
                _row('Intended profile', carrier['intendedProfile']),
                _row('Data network', carrier['dataNetworkName']),
                if (carrier['nrAvailable'] != null)
                  _row('NR available', carrier['nrAvailable']),
                if (carrier['endcAvailable'] != null)
                  _row('EN-DC available', carrier['endcAvailable']),
                if (carrier['nrState'] != null)
                  _row('NR registration state', carrier['nrState']),
                if (carrier['nrFrequencyRange'] != null)
                  _row('NR frequency range', carrier['nrFrequencyRange']),
                if (carrier['overrideNetworkType'] != null)
                  _row(
                    'Displayed network override',
                    carrier['overrideNetworkType'],
                  ),
                _row(
                  'Database',
                  carrier['configurationValid'] == true
                      ? 'Validated'
                      : 'Not validated',
                ),
                _row(
                  'Override mounted',
                  carrier['mounted'] == true ? 'Yes' : 'No',
                ),
                _row(
                  'Override active',
                  carrier['active'] == true ? 'Yes' : 'No',
                ),
                _row(
                  'Reboot required',
                  carrier['rebootRequired'] == true ? 'Yes' : 'No',
                ),
                if (carrier['lastMount'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last mount result',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SelectableText('${carrier['lastMount']}'),
                ],
                const SizedBox(height: 8),
                const Text(
                  'A validated database and active mount confirm the backend. LTE or unavailable NR can still reflect local coverage, provisioning, or radio conditions.',
                ),
              ]),
              _card('Device & security', Icons.security_outlined, [
                _row('Device', _data['device']),
                _row('Android', '${_data['android']} · API ${_data['sdk']}'),
                _row(
                  'Verified boot',
                  '${root['verifiedBoot'] ?? 'unknown'} (${const {'green', 'yellow', 'orange', 'red'}.contains(root['verifiedBootRaw']) ? root['verifiedBootRaw'] : 'unknown'})',
                ),
                _row(
                  'Bootloader locked',
                  root['bootloaderLocked'] == '1'
                      ? 'Yes'
                      : root['bootloaderLocked'],
                ),
                _row('SELinux', root['selinux']),
                const SizedBox(height: 8),
                Text(
                  'Build fingerprint',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  '${_data['fingerprint'] ?? '—'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
              _card('Recent events', Icons.history, [
                if (events.isEmpty)
                  const Text(
                    'No recovery or configuration events recorded yet.',
                  ),
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${event['type']} · ${_eventTime(event['at'])}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 3),
                        Text('${event['detail']}'),
                      ],
                    ),
                  ),
              ]),
              Card(
                child: ExpansionTile(
                  title: const Text('Raw diagnostic data'),
                  subtitle: const Text('For troubleshooting'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: json));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Diagnostics copied'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy diagnostics'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        json,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _eventTime(Object? value) {
    if (value is! num) return '—';
    final at = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return '${at.day}/${at.month} ${TimeOfDay.fromDateTime(at).format(context)}';
  }
}
