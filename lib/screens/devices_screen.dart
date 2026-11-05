import 'package:flutter/material.dart';

import 'add_device_screen.dart';
import 'discover_devices_screen.dart';
import 'controls_screen.dart';
import '../models/device.dart';
import '../services/app_settings.dart';
import '../services/device_storage.dart';
import '../services/device_discovery.dart';
import 'settings_screen.dart';
import '../widgets/app_update_banner.dart';

import '../ssh/ssh_session_manager.dart';

import '../devices/delete_device_dialog.dart';
import '../devices/device_card.dart';
import '../devices/device_connection_service.dart';
import '../devices/device_lifecycle_controller.dart';
import '../devices/host_key_dialogs.dart';
import '../devices/install_identity_dialog.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _discoverySnapshot = DiscoverySnapshot();
  final DeviceStorage _deviceStorage = DeviceStorage();

  final DeviceConnectionService _connectionService = DeviceConnectionService();

  final HostKeyDialogs _hostKeyDialogs = HostKeyDialogs();

  late final DeviceLifecycleController _lifecycleController;

  List<Device> _devices = [];

  bool _loading = true;

  //
  // Connection/reconnection state is tracked per device.
  //
  // One device reconnecting must never block another
  // connected device from being opened or used.
  //
  final Set<String> _connectingDeviceIds = <String>{};

  String? _error;

  bool _isConnecting(String deviceId) {
    return _connectingDeviceIds.contains(deviceId);
  }

  @override
  void initState() {
    super.initState();

    _lifecycleController = DeviceLifecycleController(
      devicesProvider: () => _devices,

      //
      // Reconnects are no longer globally blocked by
      // another device connecting. _connectDevice()
      // prevents duplicate attempts for the same device.
      //
      reconnectBlocked: () => _loading,

      reconnectDevice: (device) async {
        await _connectDevice(device, openControls: false, reconnecting: true);
      },
    );

    _lifecycleController.start();

    _loadDevices();

    //
    // Verify any manager-owned sessions that
    // may already exist.
    //
    sshSessions.healthCheckAll();
  }

  @override
  void dispose() {
    _lifecycleController.stop();

    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final saved = await _deviceStorage.loadDevices();

      if (!mounted) {
        return;
      }

      setState(() {
        _devices = saved;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _error = e.toString();
      });
    }
  }

  Future<void> _saveDevices() async {
    await _deviceStorage.saveDevices(_devices);
  }

  Future<void> _discoverDevices() async {
    final device = await Navigator.of(context).push<Device>(
      MaterialPageRoute(
        builder: (_) => DiscoverDevicesScreen(
          savedDevices: _devices,
          snapshot: _discoverySnapshot,
        ),
      ),
    );
    if (device == null || !mounted) return;
    setState(() => _devices = [..._devices, device]);
    await _saveDevices();
  }

  Future<void> _chooseAddDevice() async {
    final discover = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.radar),
                title: const Text('Discover devices'),
                subtitle: const Text('Find devices on LAN and Tailscale'),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add manually'),
                subtitle: const Text('Enter a host and SSH account'),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || discover == null) return;
    if (discover) {
      await _discoverDevices();
    } else {
      await _addDevice();
    }
  }

  Future<void> _addDevice() async {
    final device = await Navigator.of(
      context,
    ).push<Device>(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));

    if (device == null) {
      return;
    }

    setState(() {
      _devices = [..._devices, device];
    });

    await _saveDevices();
  }

  Future<void> _editDevice(Device device) async {
    final updated = await Navigator.of(context).push<Device>(
      MaterialPageRoute(builder: (_) => AddDeviceScreen(device: device)),
    );

    if (updated == null) {
      return;
    }

    //
    // Editing a device can change:
    //
    // - hostname
    // - IP
    // - port
    // - username
    // - authentication
    // - shell type
    //
    // Therefore only THIS device's existing
    // SSH session and terminal are discarded.
    //
    // Other devices remain connected.
    //
    sshSessions.remove(device.id);

    _connectingDeviceIds.remove(device.id);

    final index = _devices.indexWhere((item) => item.id == device.id);

    if (index == -1) {
      return;
    }

    setState(() {
      final copy = [..._devices];

      copy[index] = updated;

      _devices = copy;
    });

    await _saveDevices();
  }

  Future<void> _deleteDevice(Device device) async {
    final confirmed = await showDeleteDeviceDialog(
      context: context,

      device: device,
    );

    if (!confirmed || !mounted) {
      return;
    }

    //
    // Remove only this device's SSH session.
    //
    // Any PC/Pi/other sessions continue.
    //
    sshSessions.remove(device.id);

    _connectingDeviceIds.remove(device.id);

    setState(() {
      _devices = _devices.where((item) => item.id != device.id).toList();
    });

    await _saveDevices();
  }

  Future<void> _disconnectDevice(Device device) async {
    final session = sshSessions.existingSession(device.id);

    if (session == null || !session.isConnected) {
      return;
    }

    //
    // Explicit disconnect:
    //
    // - closes only this device
    // - destroys its persistent terminal
    // - clears terminal scrollback
    // - leaves all other SSH sessions alive
    //
    session.disconnect();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateDevice(Device updatedDevice) async {
    final index = _devices.indexWhere(
      (device) => device.id == updatedDevice.id,
    );

    if (index == -1) {
      return;
    }

    setState(() {
      final copy = [..._devices];

      copy[index] = updatedDevice;

      _devices = copy;
    });

    await _saveDevices();
  }

  Future<void> _openDevice(Device device) async {
    //
    // Only this device is blocked while it is already
    // connecting/reconnecting. Other devices remain usable.
    //
    if (_isConnecting(device.id)) {
      return;
    }

    setState(() {
      _error = null;
    });

    // Open immediately; ControlsScreen owns the first connection attempt and
    // can render its progress instead of blocking navigation on an SSH probe.
    await _showControls(device);
  }

  Future<void> _connectDevice(
    Device device, {
    bool openControls = true,
    bool reconnecting = false,
    bool reportFailure = false,
  }) async {
    final savedIndex = _devices.indexWhere((item) => item.id == device.id);
    if (savedIndex >= 0) device = _devices[savedIndex];
    if (!mounted || _isConnecting(device.id)) {
      return;
    }

    setState(() {
      _connectingDeviceIds.add(device.id);

      _error = null;
    });

    final session = sshSessions.sessionFor(device.id);

    try {
      await _connectionService.connect(
        device,

        targetSession: session,

        onLocalHostFound: (host) => _updateLocalHost(device.id, host),

        verifyHostKey: (targetDevice, keyType, fingerprint) {
          return _hostKeyDialogs.verifyHostKey(
            context: context,

            device: targetDevice,

            keyType: keyType,

            fingerprintBytes: fingerprint,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _connectingDeviceIds.remove(device.id);
      });

      if (openControls) {
        await _showControls(device);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectingDeviceIds.remove(device.id);

        _error = reconnecting
            ? 'Reconnect failed for ${device.name}: $e'
            : 'Connection failed for ${device.name}: $e';
      });
      if (reportFailure) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error!)));
      }
    }
  }

  Future<void> _showControls(Device device) async {
    final session = sshSessions.sessionFor(device.id);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ControlsScreen(
          device: device,

          session: session,

          autoConnectOnOpen: true,

          peerDevices: _devices.where((item) => item.id != device.id).toList(),
          onOpenPeer: (peer) => _showControls(
            _devices.firstWhere(
              (item) => item.id == peer.id,
              orElse: () => peer,
            ),
          ),

          onConnect: () =>
              _connectDevice(device, openControls: false, reportFailure: true),

          onFindOnLan: () => _findLocalHost(device),

          onDeviceUpdated: _updateDevice,
        ),
      ),
    );

    //
    // The controls page may itself have
    // disconnected this device.
    //
    // Don't health-check a deliberately
    // disconnected session.
    //
    if (session.isConnected) {
      await session.healthCheck();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<String?> _findLocalHost(Device device) async {
    final host = await _connectionService.discoverLocalHost(device);
    if (host != null) await _updateLocalHost(device.id, host);
    return host;
  }

  Future<void> _updateLocalHost(String deviceId, String host) async {
    final index = _devices.indexWhere((item) => item.id == deviceId);
    if (index < 0) return;
    final updated = _devices[index].copyWith(localHost: host);
    final copy = [..._devices]..[index] = updated;
    if (mounted) setState(() => _devices = copy);
    await _deviceStorage.saveDevices(copy);
  }

  Future<void> _installIdentity(Device device) async {
    final session = sshSessions.existingSession(device.id);

    final connected =
        session != null && session.isConnected && session.deviceId == device.id;

    if (!connected) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to the device first.')),
      );

      return;
    }

    final result = await showDialog<InstallIdentityDialogResult>(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return InstallIdentityDialog(device: device, session: session);
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final message = result.alreadyInstalled
        ? '${result.identity.name} is already installed.'
        : '${result.identity.name} installed successfully.';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$message\n'
            '${result.target}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),

        actions: [
          IconButton(
            tooltip: 'Settings',

            icon: const Icon(Icons.settings),

            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),

      //
      // Adding/editing another device is unrelated
      // to a reconnect attempt already running.
      //
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseAddDevice,
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
      ),

      body: AnimatedBuilder(
        animation: Listenable.merge([sshSessions, appSettings]),

        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_devices.isEmpty) {
            return const Center(child: Text('No devices yet'));
          }

          return Column(
            children: [
              const AppUpdateBanner(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),

                  itemCount: _devices.length,

                  itemBuilder: (context, index) {
                    final device = _devices[index];

                    final connected = sshSessions.isConnected(device.id);

                    //
                    // Connection state belongs to this
                    // device only.
                    //
                    final connecting = _isConnecting(device.id);

                    return DeviceCard(
                      device: device,

                      connected: connected,

                      connecting: connecting,

                      //
                      // Only the device currently attempting
                      // a connection is disabled.
                      //
                      // Another already-connected device remains
                      // fully tappable while this happens.
                      //
                      interactionDisabled: connecting,

                      showConnectionEndpoint:
                          appSettings.showConnectionEndpoint,

                      installIdentityEnabled: connected && !connecting,

                      onOpen: () {
                        _openDevice(device);
                      },

                      onEdit: () {
                        _editDevice(device);
                      },

                      onInstallIdentity: () {
                        _installIdentity(device);
                      },

                      onDisconnect: () {
                        _disconnectDevice(device);
                      },

                      onDelete: () {
                        _deleteDevice(device);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),

      bottomNavigationBar: _error == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),

                child: Text(
                  _error!,

                  textAlign: TextAlign.center,

                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
    );
  }
}
