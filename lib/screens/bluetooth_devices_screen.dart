import 'dart:async';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/bluetooth_devices.dart';
import '../ssh/ssh_session.dart';

class BluetoothDevicesScreen extends StatefulWidget {
  final Device device;
  final SshSession session;

  const BluetoothDevicesScreen({
    super.key,
    required this.device,
    required this.session,
  });

  @override
  State<BluetoothDevicesScreen> createState() => _BluetoothDevicesScreenState();
}

class _BluetoothDevicesScreenState extends State<BluetoothDevicesScreen> {
  BluetoothSnapshot? _snapshot;
  String? _error;
  String? _busyDevice;
  bool _loading = false;
  bool _scanning = false;
  bool _volumeBusy = false;
  int? _pendingVolume;
  Timer? _stateTimer;

  bool get _windows => widget.device.shellStyle == 'windows';

  @override
  void initState() {
    super.initState();
    _load();
    _stateTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshState(),
    );
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshState() async {
    if (!mounted ||
        _loading ||
        _scanning ||
        _busyDevice != null ||
        _volumeBusy ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      _loading = true;
      final update = await BluetoothDevicesService.load(
        widget.device,
        widget.session,
        fast: true,
      );
      if (mounted) {
        setState(() => _snapshot = _mergeSnapshot(_snapshot, update));
      }
    } catch (_) {
      // Keep manual refresh available when the transport is temporarily unavailable.
    } finally {
      _loading = false;
    }
  }

  Future<String?> _pairingPrompt(
    String kind,
    String code, {
    bool headphones = false,
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            kind == 'confirm'
                ? 'Confirm pairing code'
                : kind == 'display'
                ? 'Enter this code on the device'
                : 'Bluetooth pairing code',
          ),
          content: kind == 'confirm' || kind == 'display'
              ? Text(
                  'Code: ${code.padLeft(6, '0')}\n${kind == 'confirm' ? 'Does this match the code on the other device?' : 'Enter the code on the Bluetooth device, then continue.'}',
                )
              : TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: kind == 'pin' ? 16 : 6,
                  decoration: const InputDecoration(
                    labelText: 'PIN supplied by the device manufacturer',
                  ),
                ),
          actions: [
            if (kind == 'pin' && headphones)
              TextButton(
                onPressed: () => Navigator.pop(context, '0000'),
                child: const Text('Use headphone PIN 0000'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                kind == 'confirm' || kind == 'display'
                    ? 'yes'
                    : controller.text.trim(),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _load() async {
    if (_loading || _scanning) return;
    setState(() {
      _loading = true;
      _scanning = false;
      _error = null;
    });
    try {
      if (_windows) {
        final basic = await BluetoothDevicesService.load(
          widget.device,
          widget.session,
          fast: true,
        );
        if (!mounted) return;
        setState(() => _snapshot = _mergeSnapshot(_snapshot, basic));
      }
      final snapshot = await BluetoothDevicesService.load(
        widget.device,
        widget.session,
      );
      if (mounted) {
        setState(() {
          _snapshot = _mergeSnapshot(_snapshot, snapshot);
          _pendingVolume = snapshot.outputVolume;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _scanning = false;
        });
      }
    }
  }

  Future<void> _scan() async {
    if (_loading || _scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await for (final update in BluetoothDevicesService.scan(
        widget.device,
        widget.session,
      )) {
        if (!mounted) return;
        setState(() {
          _snapshot = _mergeSnapshot(_snapshot, update);
          _pendingVolume = _snapshot?.outputVolume;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  BluetoothSnapshot _mergeSnapshot(
    BluetoothSnapshot? previous,
    BluetoothSnapshot update,
  ) {
    final devices = <String, BluetoothDeviceInfo>{
      for (final device in previous?.devices ?? const <BluetoothDeviceInfo>[])
        if (!_windows ||
            (!device.paired &&
                !device.connected &&
                device.seenAt != null &&
                DateTime.now().difference(device.seenAt!) <
                    const Duration(seconds: 30)))
          device.id: device,
    };
    for (final device in update.devices) {
      final old = previous?.devices.where((d) => d.id == device.id).firstOrNull;
      devices[device.id] = BluetoothDeviceInfo(
        id: device.id,
        name: device.name,
        kind: device.kind,
        paired: device.paired,
        trusted: device.trusted,
        connected: device.connected,
        signal: device.signal ?? old?.signal,
        battery: device.battery ?? old?.battery,
        seenAt: device.seenAt ?? old?.seenAt,
      );
    }
    return BluetoothSnapshot(
      available: update.available,
      adapter: update.adapter.isNotEmpty
          ? update.adapter
          : previous?.adapter ?? '',
      powered: update.powered ?? previous?.powered,
      outputVolume: update.outputVolume ?? previous?.outputVolume,
      outputName: update.outputName ?? previous?.outputName,
      devices: devices.values.toList(),
    );
  }

  Future<void> _perform(BluetoothDeviceInfo device, String action) async {
    if (action == 'forget' || action == 'repair') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == 'repair'
                ? 'Repair connection?'
                : 'Forget Bluetooth device?',
          ),
          content: Text(
            action == 'repair'
                ? 'This removes the saved pairing for ${device.name}, then pairs and connects it again. Put the device in pairing mode before continuing.'
                : 'This removes the pairing for ${device.name}. You can pair it again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action == 'repair' ? 'Repair' : 'Forget'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busyDevice = device.id;
      _error = null;
    });
    try {
      final result = await BluetoothDevicesService.perform(
        widget.device,
        widget.session,
        action: action,
        id: device.id,
        audioDevice:
            device.kind.toLowerCase().contains('audio') ||
            device.kind.toLowerCase().contains('headset'),
        pairingPrompt: (kind, code) => _pairingPrompt(
          kind,
          code,
          headphones:
              device.kind.toLowerCase().contains('audio') ||
              device.kind.toLowerCase().contains('headset'),
        ),
      );
      if (!mounted) return;
      final openedSettings =
          result.contains('__RC_BT_ACTION__SETTINGS') ||
          result.contains('__RC_BT_ACTION__PAIR_SETTINGS');
      if (openedSettings) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (action) {
              'disconnect' => 'Bluetooth settings opened. Disconnect there; pairing stays saved.',
              'pair' => 'Bluetooth settings opened. Put the headphones in pairing mode and finish pairing there; no PIN guessing needed.',
              _ => 'Opened Bluetooth settings on the remote device.',
            }),
          ),
        );
      }
      final deadline = DateTime.now().add(
        Duration(seconds: action == 'connect' || action == 'repair' ? 15 : 5),
      );
      bool verified = openedSettings;
      do {
        final update = await BluetoothDevicesService.load(
          widget.device,
          widget.session,
          fast: true,
        );
        if (!mounted) return;
        setState(() => _snapshot = _mergeSnapshot(_snapshot, update));
        final target = update.devices
            .where((item) => item.id.toUpperCase() == device.id.toUpperCase())
            .firstOrNull;
        verified =
            openedSettings ||
            switch (action) {
              'pair' => target?.paired == true,
              'forget' => target == null || !target.paired,
              'connect' => target?.connected == true,
              'repair' => target?.paired == true && target?.connected == true,
              'disconnect' => target != null && !target.connected,
              'trust' => target?.trusted == true,
              'untrust' => target != null && !target.trusted,
              _ => false,
            };
        if (verified) {
          if (action == 'forget') setState(() => _snapshot = update);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } while (DateTime.now().isBefore(deadline));
      if (!verified) {
        throw StateError(
          'The device has not confirmed the change. Refresh its status and retry.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
      // Repair may have removed the old pairing before failing. Refresh the
      // authoritative state so Pair is available immediately for recovery.
      if (action == 'repair' && mounted) {
        try {
          final update = await BluetoothDevicesService.load(
            widget.device,
            widget.session,
            fast: true,
          );
          if (mounted) setState(() => _snapshot = update);
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  Future<void> _setVolume(int value) async {
    if (_volumeBusy) return;
    setState(() {
      _volumeBusy = true;
      _pendingVolume = value;
      _error = null;
    });
    try {
      await BluetoothDevicesService.setVolume(
        widget.device,
        widget.session,
        value,
      );
      if (mounted && _snapshot != null) {
        setState(() {
          _snapshot = BluetoothSnapshot(
            available: _snapshot!.available,
            adapter: _snapshot!.adapter,
            powered: _snapshot!.powered,
            devices: _snapshot!.devices,
            outputVolume: value,
            outputName: _snapshot!.outputName,
          );
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _volumeBusy = false);
    }
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  String _deviceState(BluetoothDeviceInfo device) {
    if (device.connected) {
      return device.paired ? 'Paired \u00b7 Connected' : 'Connected';
    }
    if (device.paired) {
      return 'Paired \u00b7 Disconnected${!_windows && device.trusted ? ' \u00b7 Trusted' : ''}';
    }
    return _windows ? 'Found during scan' : 'Available nearby';
  }

  Widget _deviceCard(BluetoothDeviceInfo device) {
    final busy = _busyDevice == device.id;
    final icon = switch (device.kind.toLowerCase()) {
      final kind when kind.contains('audio') || kind.contains('headset') =>
        Icons.headphones_outlined,
      final kind when kind.contains('phone') => Icons.smartphone,
      final kind when kind.contains('computer') => Icons.computer,
      final kind when kind.contains('keyboard') => Icons.keyboard_outlined,
      final kind when kind.contains('mouse') => Icons.mouse_outlined,
      _ => Icons.bluetooth,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        device.kind,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_windows && device.paired)
                  PopupMenuButton<String>(
                    tooltip: 'Device options',
                    enabled: !busy,
                    onSelected: (action) => _perform(device, action),
                    itemBuilder: (_) => [
                      if (!device.connected)
                        const PopupMenuItem(
                          value: 'repair',
                          child: Text('Repair connection'),
                        ),
                      const PopupMenuItem(
                        value: 'forget',
                        child: Text('Unpair'),
                      ),
                    ],
                  ),
                if (busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(device.id, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(_deviceState(device)),
                if (device.signal != null) Text('Signal ${device.signal} dBm'),
                if (device.battery != null) Text('Battery ${device.battery}%'),
                if (device.battery == null && device.paired)
                  const Text('Battery not reported'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (device.canPair)
                  _actionButton(
                    label: 'Pair',
                    icon: Icons.add_link,
                    onPressed: busy ? null : () => _perform(device, 'pair'),
                  ),
                if (device.paired && !_windows)
                  _actionButton(
                    label: device.trusted ? 'Untrust' : 'Trust',
                    icon: device.trusted
                        ? Icons.verified_user
                        : Icons.shield_outlined,
                    onPressed: busy
                        ? null
                        : () => _perform(
                            device,
                            device.trusted ? 'untrust' : 'trust',
                          ),
                  ),
                if (device.paired && !_windows)
                  _actionButton(
                    label: device.connected ? 'Disconnect' : 'Connect',
                    icon: device.connected ? Icons.link_off : Icons.link,
                    onPressed: busy
                        ? null
                        : () => _perform(
                            device,
                            device.connected ? 'disconnect' : 'connect',
                          ),
                  ),
                if (device.canConnect && _windows)
                  _actionButton(
                    label: 'Connect',
                    icon: Icons.link,
                    onPressed: busy ? null : () => _perform(device, 'connect'),
                  ),
                if (device.canDisconnect && _windows)
                  _actionButton(
                    label: 'Disconnect',
                    icon: Icons.link_off,
                    onPressed: busy
                        ? null
                        : () => _perform(device, 'disconnect'),
                  ),
                if (device.paired && !_windows)
                  _actionButton(
                    label: 'Forget',
                    icon: Icons.link_off,
                    onPressed: busy ? null : () => _perform(device, 'forget'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth devices'),
        actions: [
          IconButton(
            tooltip: 'Scan for devices',
            onPressed: _loading || _scanning ? null : _scan,
            icon: const Icon(Icons.bluetooth_searching),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _scanning ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(
                    snapshot?.powered == true
                        ? Icons.bluetooth_connected
                        : snapshot?.available == true
                        ? Icons.bluetooth
                        : Icons.bluetooth_disabled,
                  ),
                  title: Text(
                    snapshot?.adapter.isNotEmpty == true
                        ? snapshot!.adapter
                        : 'Bluetooth status',
                  ),
                  subtitle: Text(
                    snapshot == null
                        ? (_loading
                              ? 'Loading Bluetooth status…'
                              : 'Bluetooth status unavailable. Refresh to retry.')
                        : snapshot.available
                        ? snapshot.powered == null
                              ? 'Radio detected · power state managed by Windows'
                              : snapshot.powered!
                              ? 'Radio is on'
                              : 'Radio is off'
                        : 'Bluetooth radio not detected',
                  ),
                  trailing:
                      snapshot == null ||
                          !snapshot.available ||
                          snapshot.powered == null
                      ? null
                      : Text(snapshot.powered! ? 'ON' : 'OFF'),
                ),
              ),
              if (snapshot?.outputVolume != null) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.volume_up_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                snapshot?.outputName ?? 'System audio output',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            if (_volumeBusy)
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Text(
                                '${_pendingVolume ?? snapshot!.outputVolume}%',
                              ),
                          ],
                        ),
                        Slider(
                          min: 0,
                          max: 100,
                          divisions: 100,
                          value: (_pendingVolume ?? snapshot!.outputVolume!)
                              .toDouble()
                              .clamp(0, 100),
                          onChanged: _volumeBusy
                              ? null
                              : (value) => setState(
                                  () => _pendingVolume = value.round(),
                                ),
                          onChangeEnd: _volumeBusy
                              ? null
                              : (value) => _setVolume(value.round()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_error!),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _windows ? 'Devices' : 'Nearby and paired devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text('${snapshot?.devices.length ?? 0}'),
                ],
              ),
              const SizedBox(height: 12),
              if (_scanning) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                const Text('Scanning nearby devices…'),
              ] else if (_loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (snapshot?.devices.isEmpty == true && !_scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No Bluetooth devices found. Put the device you want to pair into pairing mode, then scan again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_windows) ...[
                for (final group in [
                  ('Connected', (BluetoothDeviceInfo d) => d.connected),
                  (
                    'Paired',
                    (BluetoothDeviceInfo d) => d.paired && !d.connected,
                  ),
                  (
                    'Found during scan',
                    (BluetoothDeviceInfo d) => !d.paired && !d.connected,
                  ),
                ])
                  if (snapshot?.devices.any(group.$2) == true) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        group.$1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final device in snapshot!.devices.where(group.$2))
                      _deviceCard(device),
                  ],
              ] else
                for (final device in snapshot?.devices ?? const [])
                  _deviceCard(device),
              const SizedBox(height: 4),
              Text(
                _windows
                    ? 'Disconnect ends the active Bluetooth connection while keeping pairing saved. Some devices may reconnect automatically. BLE-only devices may also need Windows Settings. Battery data appears only when the device and driver report a valid level.'
                    : 'Battery and signal details depend on what each device reports. Put headphones in pairing mode; pairing uses the Pi’s no-PIN flow for devices that support it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _scanning ? null : _scan,
        icon: const Icon(Icons.bluetooth_searching),
        label: Text(_scanning ? 'Scanning…' : 'Scan'),
      ),
    );
  }
}
