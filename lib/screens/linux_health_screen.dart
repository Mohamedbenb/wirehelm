import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/linux_health.dart';
import '../services/pi_wake.dart';
import '../ssh/ssh_session.dart';

class LinuxHealthScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  final List<Device> peerDevices;
  final Future<void> Function(Device)? onOpenPeer;

  const LinuxHealthScreen({
    super.key,
    required this.device,
    required this.session,
    this.peerDevices = const [],
    this.onOpenPeer,
  });

  @override
  State<LinuxHealthScreen> createState() => _LinuxHealthScreenState();
}

class _LinuxHealthScreenState extends State<LinuxHealthScreen> {
  Device? _peer;
  LinuxHealthReport? _report;
  Object? _error;
  bool _loading = false;
  bool _waking = false, _cancelWake = false, _readyToConnect = false;
  String? _savedMac, _wakeStatus;

  List<Device> get _pcs => widget.peerDevices
      .where(
        (device) =>
            device.id != widget.device.id &&
            (device.shellStyle == 'windows' || device.shellStyle == 'auto'),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    final pcs = _pcs;
    if (pcs.length == 1) _peer = pcs.single;
    _loadWakeMac();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading || _waking) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await fetchLinuxHealth(
        device: widget.device,
        session: widget.session,
        peer: _peer,
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _wakeMac {
    if (_savedMac != null) return _savedMac!;
    if (_pcs.length != 1) return '';
    for (final command in widget.device.commands) {
      if (!command.command.contains('wakeonlan')) continue;
      for (final parameter in command.parameters) {
        if (parameter.key == 'mac') return parameter.defaultValue?.trim() ?? '';
      }
    }
    return '';
  }

  String _macKey(Device peer) => 'pi_wake_mac_${widget.device.id}_${peer.id}';

  Future<void> _loadWakeMac() async {
    final peer = _peer;
    if (peer == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString(_macKey(peer));
      if (mounted && _peer?.id == peer.id) setState(() => _savedMac = mac);
    } catch (_) {
      /* Existing command defaults remain usable. */
    }
  }

  String? get _broadcast {
    final report = _report;
    if (report == null || !report.directLan) return null;
    try {
      return wakeBroadcast(report.value('pc_cidr'), report.value('pc_ip'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _configureWake() async {
    final peer = _peer;
    if (peer == null) return;
    final form = GlobalKey<FormState>();
    final controller = TextEditingController(text: _wakeMac);
    final mac = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Wake ${peer.name}'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'PC Ethernet MAC address',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
                validator: (value) {
                  try {
                    normalizeWakeMac(value ?? '');
                    return null;
                  } catch (_) {
                    return 'Enter a valid Ethernet MAC address';
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Use the wired adapter connected to the switch. The broadcast address is calculated from the Pi’s current subnet each time.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, normalizeWakeMac(controller.text));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (mac == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_macKey(peer), mac);
      if (mounted) setState(() => _savedMac = mac);
    } catch (e) {
      if (mounted) setState(() => _wakeStatus = 'Could not save MAC: $e');
    }
  }

  Future<void> _wake() async {
    final peer = _peer;
    if (peer == null || _waking) return;
    setState(() {
      _waking = true;
      _cancelWake = false;
      _readyToConnect = false;
    });
    try {
      final ready = await wakePcViaPi(
        pi: widget.device,
        peer: peer,
        session: widget.session,
        mac: _wakeMac,
        cancelled: () => !mounted || _cancelWake,
        onStatus: (status) {
          if (mounted) setState(() => _wakeStatus = status);
        },
      );
      if (mounted && !_cancelWake) setState(() => _readyToConnect = ready);
    } catch (error) {
      if (mounted && !_cancelWake) setState(() => _wakeStatus = '$error');
    } finally {
      if (mounted) setState(() => _waking = false);
    }
  }

  Widget _wakeControls() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _wakeMac.isEmpty
              ? 'Save the PC’s Ethernet MAC to enable Wake-on-LAN.'
              : 'Ethernet MAC: $_wakeMac',
        ),
        Text(
          _broadcast == null
              ? 'A direct LAN subnet is required for Wake-on-LAN.'
              : 'Automatic broadcast: $_broadcast',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _waking ? null : _configureWake,
              icon: const Icon(Icons.settings_ethernet),
              label: const Text('Wake setup'),
            ),
            FilledButton.icon(
              onPressed:
                  _waking || _loading || _wakeMac.isEmpty || _broadcast == null
                  ? null
                  : _wake,
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Wake PC'),
            ),
            if (_waking)
              TextButton(
                onPressed: () => setState(() {
                  _cancelWake = true;
                  _wakeStatus = 'Stopped waiting. Any wake packet already sent cannot be recalled.';
                }),
                child: const Text('Stop waiting'),
              ),
            if ((_readyToConnect || _report?.value('pc_ssh') == 'reachable') &&
                widget.onOpenPeer != null)
              FilledButton.tonalIcon(
                onPressed: _waking ? null : () => widget.onOpenPeer!(_peer!),
                icon: const Icon(Icons.link),
                label: const Text('Connect to PC'),
              ),
          ],
        ),
        if (_waking)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_wakeStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_wakeStatus!),
          ),
      ],
    ),
  );

  Widget _sectionTitle(BuildContext context, String title, IconData icon) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      );

  Widget _resultRow(
    BuildContext context,
    String title,
    String value, {
    bool? good,
    String? detail,
  }) {
    final color = good == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : good
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: detail == null ? null : Text(detail),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: good == null ? null : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _toolState(String key) =>
      _report?.value(key) == 'yes' ? 'Available' : 'Missing';

  String _formatTemperature(String raw) {
    final temp = double.tryParse(raw);
    if (temp == null) return raw == 'unavailable' ? 'Not reported' : raw;
    return '${temp.toStringAsFixed(1)} °C';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final pcs = _pcs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network & Pi health'),
        actions: [
          IconButton(
            tooltip: 'Refresh checks',
            onPressed: _loading || _waking ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Phone → Pi · ${widget.session.connectionRoute ?? 'SSH'}',
                ),
                subtitle: Text(
                  'Connected address: ${widget.session.connectedHost ?? widget.device.host}\nSaved LAN: ${widget.device.localHost.isEmpty ? 'Not configured' : widget.device.localHost}',
                ),
              ),
              Text(
                'Checks run from the Pi over SSH. A failed ping can mean ICMP is blocked; the SSH-port test is the stronger PC reachability check.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (pcs.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<Device>(
                  initialValue: _peer,
                  decoration: const InputDecoration(
                    labelText: 'PC to check',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final device in pcs)
                      DropdownMenuItem(value: device, child: Text(device.name)),
                  ],
                  onChanged: _loading || _waking
                      ? null
                      : (peer) {
                          setState(() {
                            _peer = peer;
                            _report = null;
                            _savedMac = null;
                            _wakeStatus = null;
                            _readyToConnect = false;
                          });
                          _loadWakeMac();
                          _refresh();
                        },
                ),
                if (_peer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Testing ${_peer!.localHost.trim().isNotEmpty ? _peer!.localHost : _peer!.host}:${_peer!.port}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 14),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Add the PC as a saved device to test reachability from the Pi.',
                    ),
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Checking the Pi and network…'),
              ],
              if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Health check failed',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText('$_error'),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _loading ? null : _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (report != null) ...[
                _sectionTitle(context, 'Network path', Icons.router_outlined),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _resultRow(
                        context,
                        'Default router',
                        report.value('gateway', 'none'),
                        good: report.value('router') == 'reachable'
                            ? true
                            : report.value('router') == 'no_ping_reply'
                            ? null
                            : false,
                        detail:
                            '${report.value('adapter')} · ${report.value('local_ip')}',
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Router response',
                        switch (report.value('router')) {
                          'reachable' => 'Reachable',
                          'no_ping_reply' => 'No ping reply',
                          _ => 'No default route',
                        },
                        good: report.value('router') == 'reachable'
                            ? true
                            : report.value('router') == 'no_ping_reply'
                            ? null
                            : false,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'DNS',
                        report.value('dns') == 'reachable'
                            ? 'Working'
                            : 'Unavailable',
                        good: report.value('dns') == 'reachable',
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Internet access',
                        report.value('internet') == 'reachable'
                            ? 'Working'
                            : 'Unavailable',
                        good: report.value('internet') == 'reachable',
                      ),
                    ],
                  ),
                ),
                if (_peer != null) ...[
                  _sectionTitle(context, 'PC access', Icons.desktop_windows),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _resultRow(
                          context,
                          'Network route',
                          '${report.value('pc_ip')} · ${report.value('pc_route')}',
                        ),
                        _resultRow(
                          context,
                          'Direct Pi → PC access',
                          report.directLan
                              ? (report.pcReachable
                                    ? 'Reachable on LAN'
                                    : 'No response on LAN')
                              : report.value('pc_route_kind') == 'overlay'
                              ? 'Via VPN / overlay'
                              : 'No direct LAN route',
                          good: report.directLan && report.pcReachable
                              ? true
                              : null,
                          detail:
                              'Gateway: ${report.value('pc_gateway', 'none')}',
                        ),
                        const Divider(height: 1, indent: 16),
                        _resultRow(
                          context,
                          'Ping',
                          report.value('pc_ping') == 'reachable'
                              ? 'Responding'
                              : 'No reply',
                          good: report.value('pc_ping') == 'reachable'
                              ? true
                              : null,
                        ),
                        const Divider(height: 1, indent: 16),
                        _resultRow(
                          context,
                          'SSH port ${_peer!.port}',
                          report.value('pc_ssh') == 'reachable'
                              ? 'Reachable'
                              : 'No response',
                          good: report.value('pc_ssh') == 'reachable',
                          detail: report.value('pc_ssh') == 'unreachable'
                              ? 'PC may be asleep, SSH may be stopped, or a firewall may block the port.'
                              : null,
                        ),
                        const Divider(height: 1, indent: 16),
                        _resultRow(
                          context,
                          'Wake-on-LAN route',
                          report.value('wol_tool') == 'installed'
                              ? report.value('pc_broadcast', 'unavailable')
                              : 'Install wakeonlan',
                          good:
                              report.value('wol_tool') == 'installed' &&
                              report.value('pc_broadcast') != 'unavailable' &&
                              RegExp(
                                r'^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$',
                              ).hasMatch(_wakeMac),
                          detail: report.value('pc_broadcast') == 'unavailable'
                              ? 'No LAN broadcast address found on the route to this PC.'
                              : _wakeMac.isEmpty
                              ? 'Save the PC Ethernet MAC in Wake setup below.'
                              : 'Adapter ${report.value('pc_route').split(' · ').first} · MAC $_wakeMac',
                        ),
                        _wakeControls(),
                      ],
                    ),
                  ),
                ],
                _sectionTitle(context, 'Pi health', Icons.memory_outlined),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _resultRow(
                        context,
                        'CPU temperature',
                        _formatTemperature(report.value('cpu_temp')),
                        good: double.tryParse(report.value('cpu_temp')) == null
                            ? null
                            : double.parse(report.value('cpu_temp')) < 80,
                      ),
                      if (double.tryParse(report.value('cpu_temp')) != null &&
                          double.parse(report.value('cpu_temp')) >= 80)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'High temperature may cause the Pi to throttle.',
                          ),
                        ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Undervoltage',
                        report.value('throttled') == 'unavailable'
                            ? 'Not reported'
                            : report.hasUndervoltage
                            ? 'Detected'
                            : 'No current or recorded warning',
                        good: report.value('throttled') == 'unavailable'
                            ? null
                            : !report.hasUndervoltage,
                        detail: report.value('throttled') == 'unavailable'
                            ? 'Install raspberrypi-utils for vcgencmd.'
                            : report.hasThrottling
                            ? 'Throttling has also been recorded (throttled=${report.value('throttled')}).'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Available memory',
                        report.value('memory_free'),
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'System storage',
                        report.value('disk'),
                      ),
                      if (int.tryParse(report.value('disk_used')) != null &&
                          int.parse(report.value('disk_used')) >= 90)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Storage is almost full. Remove old files or expand the filesystem.',
                          ),
                        ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(context, 'Uptime', report.value('uptime')),
                    ],
                  ),
                ),
                _sectionTitle(
                  context,
                  'Remote capabilities',
                  Icons.build_outlined,
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _resultRow(
                        context,
                        'Camera streaming · ffmpeg',
                        _toolState('tool_ffmpeg'),
                        good: _report?.value('tool_ffmpeg') == 'yes',
                        detail: _report?.value('tool_ffmpeg') == 'no'
                            ? 'Install with: sudo apt install ffmpeg'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Screenshot capture',
                        (report.value('tool_scrot') == 'yes' ||
                                report.value('tool_grim') == 'yes' ||
                                report.value('tool_gnome-screenshot') == 'yes')
                            ? 'Available'
                            : 'Missing',
                        good:
                            report.value('tool_scrot') == 'yes' ||
                            report.value('tool_grim') == 'yes' ||
                            report.value('tool_gnome-screenshot') == 'yes',
                        detail:
                            report.value('tool_scrot') == 'no' &&
                                report.value('tool_grim') == 'no'
                            ? 'Install scrot for X11 or grim for Wayland: sudo apt install scrot'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Bluetooth controls',
                        _toolState('tool_bluetoothctl'),
                        good: report.value('tool_bluetoothctl') == 'yes',
                        detail: report.value('tool_bluetoothctl') == 'no'
                            ? 'Install with: sudo apt install bluez'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'NetworkManager controls',
                        _toolState('tool_nmcli'),
                        good: report.value('tool_nmcli') == 'yes',
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'USB inventory · lsusb',
                        _toolState('tool_lsusb'),
                        good: report.value('tool_lsusb') == 'yes',
                        detail: report.value('tool_lsusb') == 'no'
                            ? 'Install with: sudo apt install usbutils'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Camera device access',
                        switch (report.value('video_access')) {
                          'available' => 'Available',
                          'permission_denied' => 'Permission denied',
                          _ => 'No camera device',
                        },
                        good: report.value('video_access') == 'available'
                            ? true
                            : report.value('video_access') ==
                                  'permission_denied'
                            ? false
                            : null,
                        detail:
                            report.value('video_access') == 'permission_denied'
                            ? 'Grant the SSH user video device access, then reconnect.'
                            : null,
                      ),
                      const Divider(height: 1, indent: 16),
                      _resultRow(
                        context,
                        'Audio device access',
                        switch (report.value('audio_access')) {
                          'available' => 'Available',
                          'permission_denied' => 'Permission denied',
                          _ => 'No audio device',
                        },
                        good: report.value('audio_access') == 'available'
                            ? true
                            : report.value('audio_access') ==
                                  'permission_denied'
                            ? false
                            : null,
                        detail:
                            report.value('audio_access') == 'permission_denied'
                            ? 'Grant the SSH user audio device access, then reconnect.'
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
              if (!_loading && report == null && _error == null)
                const Center(child: Text('Pull down to run the health check.')),
            ],
          ),
        ),
      ),
    );
  }
}
