import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

enum WaylandAccessMode {
  keyboard('keyboard'),
  desktop('live desktop');

  const WaylandAccessMode(this.label);
  final String label;
}

/// Saves a KDE restore token for one verified SSH account and portal scope.
class WaylandAccess {
  static const _storage = FlutterSecureStorage();
  static const _awaitingApproval = '';

  static String? _storageKey(
    Device device,
    SshSession session,
    WaylandAccessMode mode,
  ) {
    final host = session.hostKeyIdentity;
    final username = session.authenticatedUsername;
    if (session.deviceId != device.id || host == null || username == null) {
      return null;
    }
    final binding = jsonEncode([device.id, host, username]);
    return 'wayland_${mode.name}_${base64UrlEncode(utf8.encode(binding))}';
  }

  static Future<WaylandAccess> read(
    Device device,
    SshSession session,
    WaylandAccessMode mode,
  ) async {
    final key = _storageKey(device, session, mode);
    final saved = key == null ? null : await _storage.read(key: key);
    return WaylandAccess._(key, saved);
  }

  const WaylandAccess._(this._key, this._saved);

  final String? _key;
  final String? _saved;

  bool get available => _key != null;
  bool get remember => _saved != null;
  String? get token => _validToken(_saved);

  static String? _validToken(Object? value) {
    if (value is! String || value.isEmpty || value.length > 512) return null;
    return value.codeUnits.every((unit) => unit >= 32 && unit < 127)
        ? value
        : null;
  }

  Uint8List get startupMessage => utf8.encode(
    '${jsonEncode({'remember': remember, 'restoreToken': token})}\n',
  );

  Future<void> setRemember(bool enabled) async {
    final key = _key;
    if (key == null) throw StateError('Connect to the PC through SSH first.');
    if (enabled) {
      await _storage.write(key: key, value: _awaitingApproval);
    } else {
      await _storage.delete(key: key);
    }
  }

  Future<void> recordApproval(Object? restoreToken) async {
    final key = _key;
    if (key == null || !remember) return;
    final latest = await _storage.read(key: key);
    if (latest != _saved) return;
    await _storage.write(
      key: key,
      value: _validToken(restoreToken) ?? _awaitingApproval,
    );
  }
}
