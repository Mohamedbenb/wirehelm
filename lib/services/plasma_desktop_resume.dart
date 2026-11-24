import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'linux_desktop.dart';

const _authentication = MethodChannel('remote_control/desktop_unlock');

enum PlasmaDesktopPreparation { ready, displayUnconfirmed, cancelled }

// OpenSSH launches the account's login shell. Use sh on stdin to keep the
// script compatible with fish and keep both phases on the selected SSH host.
const _plasmaSessionScript =
    r'''
set -eu

result() { printf '__WIREHELM_PLASMA__ %s\n' "$*"; exit 0; }

wake_display() (
''' +
    linuxDesktopEnvironment +
    r'''
  [ -n "$WAYLAND_DISPLAY" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || exit 1
  export QT_QPA_PLATFORM=wayland
  display_on() {
    mode="$(timeout 2s kscreen-doctor --dpms show 2>/dev/null)" || return 1
    printf '%s\n' "$mode" | awk '
      /^dpms mode for screen .*: on$/ { on=1 }
      /^dpms mode for screen .*: off$/ { off=1 }
      END { exit !(on && !off) }'
  }
  if display_on; then exit 0; fi
  timeout 3s ''' +
    plasmaDisplayPowerOn +
    r''' >/dev/null 2>&1 || :
  display_on
)
ready() {
  if wake_display; then result ready; fi
  result display-unconfirmed
}

uid="$(id -u)"
display="$(loginctl show-user "$uid" -p Display --value 2>/dev/null)" || result sign-in
case "$display" in
  ''|*[!A-Za-z0-9]*) result sign-in ;;
esac

properties="$(loginctl show-session "$display" -p User -p Class -p Type -p Desktop -p Remote -p Active -p LockedHint 2>/dev/null)" || result sign-in
has() { printf '%s\n' "$properties" | grep -qxF "$1"; }
has "User=$uid" && has Class=user && has Remote=no || result sign-in
has Type=wayland && has Desktop=KDE || result unsupported
has Active=yes || result inactive

if [ "$#" -eq 0 ]; then
  if has LockedHint=yes; then result "locked $display"; fi
  if has LockedHint=no; then ready; fi
  result unknown
fi

[ "$display" = "$1" ] || result changed
if has LockedHint=no; then ready; fi
has LockedHint=yes || result unknown
loginctl --no-ask-password unlock-session "$display" >/dev/null 2>&1 || result unlock-failed
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  lock="$(loginctl show-session "$display" -p LockedHint --value 2>/dev/null)" || result changed
  if [ "$lock" = no ]; then ready; fi
  sleep 0.2
done
result unlock-failed
''';

Future<PlasmaDesktopPreparation> preparePlasmaDesktop({
  required Device device,
  required SshSession session,
  required bool Function() cancelled,
  void Function(String)? onStatus,
  Future<bool> Function(String)? authenticate,
}) async {
  final client = session.client;
  bool sameConnection() =>
      session.isConnected &&
      session.deviceId == device.id &&
      session.authenticatedUsername == device.username &&
      session.hostKeyIdentity != null &&
      identical(session.client, client);

  if (client == null || !sameConnection()) {
    throw StateError('Connect to the PC and verify its SSH host key first.');
  }

  Future<String> query([String? expectedSession]) async {
    final output = await session.run(
      expectedSession == null ? 'sh -s' : 'sh -s -- $expectedSession',
      input: utf8.encode(_plasmaSessionScript),
      timeout: const Duration(seconds: 14),
    );
    const prefix = '__WIREHELM_PLASMA__ ';
    for (final line in const LineSplitter().convert(
      utf8.decode(output, allowMalformed: true),
    )) {
      if (line.startsWith(prefix)) return line.substring(prefix.length);
    }
    return 'unknown';
  }

  onStatus?.call('Checking the PC’s Plasma session…');
  var status = await query();
  if (cancelled()) return PlasmaDesktopPreparation.cancelled;
  final locked = RegExp(r'^locked ([A-Za-z0-9]+)$').firstMatch(status);
  if (locked != null) {
    if (!sameConnection()) throw StateError('The PC connection changed.');
    onStatus?.call('Confirm on your phone to unlock the PC…');
    final approved = authenticate == null
        ? await _authentication.invokeMethod<bool>('authenticate', {
            'device': device.name,
          })
        : await authenticate(device.name);
    if (cancelled() || approved != true) {
      return PlasmaDesktopPreparation.cancelled;
    }
    if (!sameConnection()) throw StateError('The PC connection changed.');
    onStatus?.call('Unlocking the Plasma session…');
    status = await query(locked.group(1)!);
  }
  if (cancelled()) return PlasmaDesktopPreparation.cancelled;
  if (!sameConnection()) throw StateError('The PC connection changed.');
  if (status == 'ready') return PlasmaDesktopPreparation.ready;
  if (status == 'display-unconfirmed') {
    return PlasmaDesktopPreparation.displayUnconfirmed;
  }

  throw StateError(switch (status) {
    'sign-in' => 'Sign in to Plasma on the PC first.',
    'unsupported' => 'The PC needs an active KDE Plasma Wayland session.',
    'inactive' => 'Switch to the Plasma desktop session on the PC first.',
    'changed' => 'The Plasma session changed. Try opening the desktop again.',
    'unlock-failed' =>
      'Plasma did not unlock. Try Remote keyboard or unlock at the PC.',
    _ => 'Could not read the PC’s Plasma lock state.',
  });
}
