import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/background_keep_alive.dart';
import 'ssh_session.dart';

final sshSessions =
    SshSessionManager();

class SshSessionManager
    extends ChangeNotifier {
  final Map<String, SshSession>
      _sessions = {};

  final Map<String, VoidCallback>
      _sessionListeners = {};

  bool _appActive = true;

  Future<void> _keepAliveSync =
      Future<void>.value();

  Iterable<String>
      get deviceIds =>
          _sessions.keys;

  Iterable<String>
      get connectedDeviceIds =>
          _sessions.entries
              .where(
                (entry) =>
                    entry.value
                        .isConnected,
              )
              .map(
                (entry) =>
                    entry.key,
              );

  bool get hasConnections =>
      _sessions.values.any(
        (session) =>
            session.isConnected,
      );

  int get connectionCount =>
      _sessions.values
          .where(
            (session) =>
                session.isConnected,
          )
          .length;

  //
  // Keep the Android foreground service alive
  // when:
  //
  // 1. at least one SSH session is connected
  //
  // OR
  //
  // 2. a session was unexpectedly lost and
  //    still has a reconnect target.
  //
  // Explicit disconnect() clears lastDeviceId,
  // so it will no longer keep the service alive.
  //
  bool get _needsBackgroundKeepAlive =>
      _sessions.values.any(
        (session) =>
            session.isConnected ||
            session.lastDeviceId !=
                null,
      );

  bool contains(
    String deviceId,
  ) {
    return _sessions.containsKey(
      deviceId,
    );
  }

  SshSession? existingSession(
    String deviceId,
  ) {
    return _sessions[
        deviceId];
  }

  SshSession sessionFor(
    String deviceId,
  ) {
    final existing =
        _sessions[
            deviceId];

    if (existing != null) {
      return existing;
    }

    //
    // Per-device sessions do NOT control the
    // Android foreground service themselves.
    //
    // The manager owns that globally.
    //
    final session =
        SshSession(
      manageBackgroundKeepAlive:
          false,
    );

    session.setAppActive(
      _appActive,
    );

    void listener() {
      _handleSessionChanged();
    }

    session.addListener(
      listener,
    );

    _sessions[
        deviceId] =
        session;

    _sessionListeners[
        deviceId] =
        listener;

    notifyListeners();

    _scheduleKeepAliveSync();

    return session;
  }

  bool isConnected(
    String deviceId,
  ) {
    return _sessions[
            deviceId]
        ?.isConnected ??
        false;
  }

  Future<bool> healthCheck(
    String deviceId,
  ) async {
    final session =
        _sessions[
            deviceId];

    if (session == null) {
      return false;
    }

    return session.healthCheck();
  }

  Future<void> healthCheckAll() async {
    final sessions =
        List<SshSession>.from(
      _sessions.values,
    );

    await Future.wait(
      sessions.map(
        (session) =>
            session.healthCheck(),
      ),
    );

    _scheduleKeepAliveSync();
  }

  void setAppActive(
    bool active,
  ) {
    _appActive = active;

    for (final session
        in _sessions.values) {
      session.setAppActive(
        active,
      );
    }
  }

  void disconnect(
    String deviceId,
  ) {
    final session =
        _sessions[
            deviceId];

    if (session == null) {
      return;
    }

    session.disconnect();

    _scheduleKeepAliveSync();

    notifyListeners();
  }

  void disconnectAll() {
    for (final session
        in _sessions.values) {
      session.disconnect();
    }

    _scheduleKeepAliveSync();

    notifyListeners();
  }

  void remove(
    String deviceId,
  ) {
    final session =
        _sessions.remove(
      deviceId,
    );

    final listener =
        _sessionListeners.remove(
      deviceId,
    );

    if (session == null) {
      return;
    }

    if (listener != null) {
      session.removeListener(
        listener,
      );
    }

    session.dispose();

    _scheduleKeepAliveSync();

    notifyListeners();
  }

  void removeDisconnected() {
    final ids =
        _sessions.entries
            .where(
              (entry) =>
                  !entry.value
                      .isConnected &&
                  entry.value
                          .lastDeviceId ==
                      null,
            )
            .map(
              (entry) =>
                  entry.key,
            )
            .toList();

    for (final id in ids) {
      remove(
        id,
      );
    }
  }

  void _handleSessionChanged() {
    //
    // Any individual session changing state
    // may affect:
    //
    // - device connection indicators
    // - total connection count
    // - foreground keep-alive requirements
    //
    _scheduleKeepAliveSync();

    notifyListeners();
  }

  void _scheduleKeepAliveSync() {
    //
    // Serialize start/stop operations so a rapid:
    //
    // connect A
    // connect B
    // disconnect A
    //
    // cannot race Android service start/stop calls.
    //
    _keepAliveSync =
        _keepAliveSync
            .then(
      (_) async {
        //
        // Re-evaluate at execution time rather
        // than capturing an old state.
        //
        if (_needsBackgroundKeepAlive) {
          await backgroundKeepAlive.start();
        } else {
          await backgroundKeepAlive.stop();
        }
      },
    ).catchError(
      (Object error) {
        //
        // Foreground-service failures should not
        // destroy the SSH manager state.
        //
        // A later connection-state change will
        // schedule another synchronization.
        //
        if (kDebugMode) {
          debugPrint(
            'Background keep-alive sync failed: '
            '$error',
          );
        }
      },
    );
  }

  @override
  void dispose() {
    for (final entry
        in _sessions.entries) {
      final listener =
          _sessionListeners[
              entry.key];

      if (listener != null) {
        entry.value
            .removeListener(
          listener,
        );
      }

      entry.value.dispose();
    }

    _sessions.clear();
    _sessionListeners.clear();

    //
    // No manager-owned SSH session remains.
    //
    unawaited(
      backgroundKeepAlive.stop(),
    );

    super.dispose();
  }
}