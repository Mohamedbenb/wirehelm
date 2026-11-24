import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/remote_command.dart';
import '../ssh/ssh_session.dart';
import '../utils/sudo_command.dart';
import 'linux_desktop.dart';

enum PlasmaPowerAction {
  lock('Lock', Icons.lock_outlined, 'lock'),
  sleep('Sleep', Icons.bedtime_outlined, 'suspend'),
  lockAndSleep('Lock & sleep', Icons.nights_stay_outlined, 'suspend'),
  restart('Restart', Icons.restart_alt, 'reboot'),
  shutDown('Shut down', Icons.power_settings_new, 'poweroff');

  const PlasmaPowerAction(this.label, this.icon, this.operation);
  final String label;
  final IconData icon;
  final String operation;
}

const _lockPlasma = r'''
owner="${SUDO_UID:-$(id -u)}"
session="$(loginctl show-user "$owner" -p Display --value 2>/dev/null)" || session=''
case "$session" in
  ''|*[!A-Za-z0-9]*) printf '%s\n' 'Sign in to Plasma on the PC first.'; exit 1 ;;
esac
state="$(loginctl show-session "$session" -p User -p Type -p Desktop -p Active)"
if ! printf '%s\n' "$state" | grep -qxF "User=$owner" ||
   ! printf '%s\n' "$state" | grep -qxF Desktop=KDE ||
   ! printf '%s\n' "$state" | grep -qxF Active=yes; then
  printf '%s\n' 'Switch to the Plasma desktop session on the PC first.'; exit 1
fi
loginctl --no-ask-password lock-session "$session" || exit 1
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$(loginctl show-session "$session" -p LockedHint --value)" = yes ]; then break; fi
  sleep 0.2
done
if [ "$(loginctl show-session "$session" -p LockedHint --value)" != yes ]; then
  printf '%s\n' 'Plasma could not confirm the lock.'; exit 1
fi
''';

Future<bool> requestPlasmaPower(
  BuildContext context, {
  required Device device,
  required SshSession session,
  required PlasmaPowerAction action,
}) async {
  final client = session.client;
  bool connected() =>
      client != null &&
      identical(client, session.client) &&
      session.isConnected &&
      session.deviceId == device.id;
  if (!connected()) throw StateError('Connect to ${device.name} first.');
  if (action != PlasmaPowerAction.lock) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action.label),
        content: Text(switch (action) {
          PlasmaPowerAction.lockAndSleep =>
            'Lock the Plasma session and put ${device.name} to sleep?',
          PlasmaPowerAction.sleep => 'Put ${device.name} to sleep?',
          PlasmaPowerAction.restart =>
            'Restart ${device.name}? Save any open work first.',
          _ => 'Shut down ${device.name}? Save any open work first.',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
  }
  if (!connected()) throw StateError('The PC connection changed.');
  final script = _plasmaPowerScript(action);
  var message = await _sendPowerScript(session, script);
  if (message.contains(_powerAccepted)) return true;
  if (action != PlasmaPowerAction.lock && _needsPowerAuthorization(message)) {
    if (!context.mounted) return false;
    if (!connected()) throw StateError('The PC connection changed.');
    final response = await runCommandWithPrivileges(
      context: context,
      command: RemoteCommand(
        id: 'plasma_power',
        name: action.label,
        category: 'Power',
        icon: 'power',
        command: script,
        requiresSudo: true,
      ),
      commandText: script,
      session: session,
      timeout: const Duration(seconds: 12),
    );
    if (response == null) return false;
    message = _decodePowerReply(response);
    if (message.contains(_powerAccepted)) return true;
  }
  throw StateError(
    message.isEmpty ? 'The PC did not acknowledge the request.' : message,
  );
}

const _powerAccepted = '__WIREHELM_POWER_ACCEPTED__';

String _plasmaPowerScript(PlasmaPowerAction action) {
  final lock =
      action == PlasmaPowerAction.lock ||
          action == PlasmaPowerAction.lockAndSleep
      ? _lockPlasma
      : '';
  final operation = action == PlasmaPowerAction.lock
      ? ''
      : 'LC_ALL=C systemctl --no-ask-password --no-block ${action.operation} || exit 1\n';
  return "$lock${operation}printf '%s\\n' '$_powerAccepted'";
}

String _decodePowerReply(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true).trim();

Future<String> _sendPowerScript(SshSession session, String script) async =>
    _decodePowerReply(
      await session.run(
        'sh -c ${desktopShellQuote(script)}',
        timeout: const Duration(seconds: 10),
      ),
    );

bool _needsPowerAuthorization(String message) => RegExp(
  'authentication required|access denied|permission denied',
  caseSensitive: false,
).hasMatch(message);

/// Executes an action already confirmed by the caller using existing host permissions.
Future<void> sendConfirmedPlasmaPower({
  required Device device,
  required SshSession session,
  required PlasmaPowerAction action,
}) async {
  if (session.client == null ||
      !session.isConnected ||
      session.deviceId != device.id) {
    throw StateError('Connect to the PC first.');
  }
  final message = await _sendPowerScript(session, _plasmaPowerScript(action));
  if (message.contains(_powerAccepted)) return;
  throw StateError(
    _needsPowerAuthorization(message)
        ? 'The PC requires authorization. Use Power in Wirehelm.'
        : 'The PC did not acknowledge the action.',
  );
}
