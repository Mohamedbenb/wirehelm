import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/device.dart';
import '../ssh/ssh_session_manager.dart';

class DeviceLifecycleController
    with WidgetsBindingObserver {
  final List<Device> Function()
      devicesProvider;

  final bool Function()
      reconnectBlocked;

  final Future<void> Function(
    Device device,
  ) reconnectDevice;

  bool _active = false;
  bool _handlingResume = false;

  DeviceLifecycleController({
    required this.devicesProvider,
    required this.reconnectBlocked,
    required this.reconnectDevice,
  });

  void start() {
    if (_active) {
      return;
    }

    _active = true;

    WidgetsBinding.instance
        .addObserver(
      this,
    );

    sshSessions.setAppActive(
      true,
    );
  }

  void stop() {
    if (!_active) {
      return;
    }

    _active = false;

    WidgetsBinding.instance
        .removeObserver(
      this,
    );
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    switch (state) {
      case AppLifecycleState.resumed:
        sshSessions.setAppActive(
          true,
        );

        unawaited(
          _handleAppResumed(),
        );

        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        sshSessions.setAppActive(
          false,
        );

        break;
    }
  }

  Future<void> checkNow() async {
    await _handleAppResumed();
  }

  Future<void> _handleAppResumed() async {
    if (!_active ||
        _handlingResume ||
        reconnectBlocked()) {
      return;
    }

    _handlingResume = true;

    try {
      //
      // First verify every currently
      // connected SSH transport.
      //
      await sshSessions
          .healthCheckAll();

      if (!_active ||
          reconnectBlocked()) {
        return;
      }

      //
      // Build a stable snapshot because
      // reconnecting may indirectly cause UI
      // updates while this loop is running.
      //
      final devices =
          List<Device>.from(
        devicesProvider(),
      );

      //
      // A session that lost its transport
      // unexpectedly keeps lastDeviceId.
      //
      // Explicit disconnect clears it.
      //
      // Therefore only sessions with a
      // reconnect target are considered here.
      //
      final reconnectIds =
          <String>[];

      for (final deviceId
          in sshSessions.deviceIds) {
        final session =
            sshSessions
                .existingSession(
          deviceId,
        );

        if (session == null ||
            session.isConnected ||
            session.lastDeviceId ==
                null) {
          continue;
        }

        reconnectIds.add(
          deviceId,
        );
      }

      //
      // Reconnect sequentially.
      //
      // This is deliberate for now:
      // DevicesScreen currently serializes
      // connection attempts, and there is no
      // benefit in opening several auth/host-key
      // dialogs simultaneously.
      //
      for (final deviceId
          in reconnectIds) {
        if (!_active ||
            reconnectBlocked()) {
          return;
        }

        Device? targetDevice;

        for (final device
            in devices) {
          if (device.id ==
              deviceId) {
            targetDevice =
                device;
            break;
          }
        }

        if (targetDevice == null) {
          continue;
        }

        await reconnectDevice(
          targetDevice,
        );
      }
    } finally {
      _handlingResume =
          false;
    }
  }
}