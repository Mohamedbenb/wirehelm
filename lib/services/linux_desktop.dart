import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'wayland_access.dart';

/// Recover the signed-in user's desktop environment from an SSH shell.
const linuxDesktopEnvironment = r'''
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
desktop_env=$(systemctl --user show-environment 2>/dev/null || true)
desktop_var() { printf '%s\n' "$desktop_env" | sed -n "s/^$1=//p" | head -n 1; }
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-$(desktop_var WAYLAND_DISPLAY)}"
export DISPLAY="${DISPLAY:-$(desktop_var DISPLAY)}"
export XAUTHORITY="${XAUTHORITY:-$(desktop_var XAUTHORITY)}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-$(desktop_var XDG_CURRENT_DESKTOP)}"
if [ -z "$WAYLAND_DISPLAY" ]; then
  for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$socket" ] || continue
    if [ -n "$WAYLAND_DISPLAY" ]; then
      echo 'Multiple Wayland displays found. Connect as the active desktop user.' >&2
      exit 1
    fi
    WAYLAND_DISPLAY="${socket##*/}"
  done
fi
''';

const plasmaDisplayPowerOn = 'kscreen-doctor --dpms on';

String desktopShellQuote(String value) =>
    "'${value.replaceAll("'", "'\"'\"'")}'";

Future<bool> usesWayland(SshSession session) async {
  const probe =
      linuxDesktopEnvironment +
      r'''
if [ -n "$WAYLAND_DISPLAY" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  printf '__WH_WAYLAND__\n'
else
  printf '__WH_X11__\n'
fi
''';
  final bytes = await session.run(
    'sh -c ${desktopShellQuote(probe)}',
    timeout: const Duration(seconds: 8),
  );
  final result = utf8.decode(bytes, allowMalformed: true).trim();
  if (result == '__WH_WAYLAND__') return true;
  if (result == '__WH_X11__') return false;
  throw StateError(
    result.isEmpty ? 'Could not detect a desktop session.' : result,
  );
}

Future<String> waylandWorkerCommand({
  required String mode,
  List<int> args = const [],
}) async {
  final source = await rootBundle.loadString('assets/desktop/wayland.py');
  final encoded = base64Encode(utf8.encode(source));
  final runner =
      "import base64; exec(compile(base64.b64decode('$encoded'), 'wirehelm-wayland', 'exec'))";
  final script =
      "${linuxDesktopEnvironment}python3 -c 'import gi' >/dev/null 2>&1 || "
      "{ echo 'Install python-gobject on the PC first.' >&2; exit 1; }\n"
      'exec python3 -u -c ${desktopShellQuote(runner)} ${desktopShellQuote(mode)} ${args.join(' ')}';
  return 'sh -c ${desktopShellQuote(script)}';
}

/// One portal grant is reused for the lifetime of the keyboard screen.
class WaylandKeyboard {
  SSHClient? _client;
  SSHSession? _channel;
  StreamIterator<String>? _lines;
  StreamSubscription<Uint8List>? _stderr;
  String _diagnostic = '';
  bool _closed = false;

  bool isActiveFor(SshSession session) =>
      _channel != null && identical(_client, session.client);

  Future<void> send(
    Device device,
    SshSession session,
    Map<String, Object> event, {
    void Function(bool restoring)? onPermission,
    Future<bool> Function()? canSend,
  }) async {
    if (_closed) throw StateError('The remote keyboard was closed.');
    try {
      if (_channel != null && !isActiveFor(session)) await _reset();
      if (_channel == null) {
        final client = session.client;
        if (client == null) throw StateError('Connect to this device first.');
        final access = await WaylandAccess.read(
          device,
          session,
          WaylandAccessMode.keyboard,
        );
        final command = await waylandWorkerCommand(mode: 'keyboard');
        final channel = await client.execute(command);
        if (_closed || !identical(client, session.client)) {
          channel.close();
          throw StateError('The desktop connection changed.');
        }
        _client = client;
        _channel = channel;
        _diagnostic = '';
        _stderr = channel.stderr.listen((bytes) {
          _diagnostic = utf8.decode(bytes, allowMalformed: true).trim();
        });
        _lines = StreamIterator(
          channel.stdout
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        onPermission?.call(access.token != null);
        channel.stdin.add(access.startupMessage);
        final ready = await _read(const Duration(seconds: 95));
        if (ready['ready'] != true) {
          throw StateError('The PC did not confirm keyboard access.');
        }
        await access.recordApproval(ready['restoreToken']);
        if (_closed || !isActiveFor(session)) {
          throw StateError('The desktop connection changed.');
        }
      }
      if (canSend != null && !await canSend()) {
        throw StateError('The keyboard page is closed.');
      }
      _channel!.stdin.add(utf8.encode('${jsonEncode(event)}\n'));
      final response = await _read(const Duration(seconds: 30));
      if (response['ok'] != true) {
        throw StateError(
          response['error'] ?? 'The PC did not confirm the input.',
        );
      }
    } catch (_) {
      await _reset();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _read(Duration timeout) async {
    final lines = _lines!;
    if (!await lines.moveNext().timeout(timeout)) {
      throw StateError(
        _diagnostic.isEmpty
            ? 'The KDE keyboard session ended. Tap a key to reconnect.'
            : _diagnostic,
      );
    }
    return jsonDecode(lines.current) as Map<String, dynamic>;
  }

  Future<void> _reset() async {
    final channel = _channel;
    final lines = _lines;
    final stderr = _stderr;
    _client = null;
    _channel = null;
    _lines = null;
    _stderr = null;
    channel?.kill(SSHSignal.TERM);
    channel?.close();
    await lines?.cancel();
    await stderr?.cancel();
  }

  Future<void> closeSession() => _reset();

  void dispose() {
    _closed = true;
    unawaited(_reset());
  }
}
