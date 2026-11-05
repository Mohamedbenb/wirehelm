import 'dart:convert';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'linux_health.dart';

String normalizeWakeMac(String value) {
  final compact = value.trim().replaceAll(RegExp('[:-]'), '').toUpperCase();
  if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(compact) ||
      compact == '000000000000' ||
      compact == 'FFFFFFFFFFFF' ||
      (int.parse(compact.substring(0, 2), radix: 16) & 1) != 0) {
    throw const FormatException(
      'Enter the PC Ethernet adapter’s unicast MAC address.',
    );
  }
  return List.generate(6, (i) => compact.substring(i * 2, i * 2 + 2)).join(':');
}

int _ipv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    throw const FormatException('A LAN IPv4 address is required.');
  }
  var result = 0;
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      throw const FormatException('Invalid IPv4 address.');
    }
    result = (result << 8) | value;
  }
  return result;
}

/// Uses the Pi source interface's actual prefix, including non-/24 networks.
String wakeBroadcast(String cidr, String peerIp) {
  final parts = cidr.split('/');
  final prefix = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (prefix == null || prefix < 1 || prefix > 30) {
    throw const FormatException('No broadcast-capable LAN subnet was found.');
  }
  final source = _ipv4(parts[0]);
  final peer = _ipv4(peerIp);
  final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
  final network = source & mask;
  final broadcast = network | (0xffffffff ^ mask);
  if ((peer & mask) != network || peer == network || peer == broadcast) {
    throw const FormatException(
      'The PC is not in the Pi’s directly connected subnet. Check its saved LAN address.',
    );
  }
  return [24, 16, 8, 0].map((shift) => (broadcast >> shift) & 255).join('.');
}

String buildPeerProbe(String host, int port) {
  if (port < 1 || port > 65535) {
    throw const FormatException('Invalid SSH port.');
  }
  _ipv4(host);
  return '''if command -v nc >/dev/null 2>&1; then nc -z -w 2 '$host' $port >/dev/null 2>&1
else timeout 3 bash -c 'cat < /dev/null > /dev/tcp/\$1/\$2' _ '$host' $port >/dev/null 2>&1; fi
if [ \$? -eq 0 ]; then printf '__NC_PC_READY__'; fi''';
}

Future<bool> wakePcViaPi({
  required Device pi,
  required Device peer,
  required SshSession session,
  required String mac,
  required bool Function() cancelled,
  required void Function(String) onStatus,
  Duration waitLimit = const Duration(seconds: 60),
}) async {
  final address = normalizeWakeMac(mac);
  onStatus('Checking the Pi’s current LAN route…');
  final report = await fetchLinuxHealth(
    device: pi,
    session: session,
    peer: peer,
  );
  if (cancelled()) return false;
  if (!report.directLan) {
    throw StateError(
      'No direct LAN route to this PC. Check its saved LAN address.',
    );
  }
  final host = report.value('pc_ip');
  final broadcast = wakeBroadcast(report.value('pc_cidr'), host);
  if (report.value('pc_ssh') == 'reachable') {
    onStatus('The PC’s SSH port is already reachable from the Pi.');
    return true;
  }
  if (report.value('wol_tool') != 'installed') {
    throw StateError(
      'Install wakeonlan on the Pi first: sudo apt install wakeonlan',
    );
  }
  final output = utf8.decode(
    await session.run(
      "wakeonlan -i '$broadcast' -p 9 '$address' >/dev/null 2>&1 && printf '__NC_WAKE_SENT__'",
      timeout: const Duration(seconds: 8),
    ),
    allowMalformed: true,
  );
  if (!output.contains('__NC_WAKE_SENT__')) {
    throw StateError('The Pi could not send the wake packet.');
  }
  if (cancelled()) return false;
  onStatus('Wake packet sent to $broadcast. Waiting for the PC’s SSH port…');
  final clock = Stopwatch()..start();
  while (!cancelled() && clock.elapsed < waitLimit) {
    final reply = utf8.decode(
      await session.run(
        buildPeerProbe(host, peer.port),
        timeout: const Duration(seconds: 5),
      ),
      allowMalformed: true,
    );
    if (cancelled()) return false;
    if (reply.contains('__NC_PC_READY__')) {
      onStatus('PC reachable directly from the Pi. Ready to connect.');
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  if (!cancelled()) {
    onStatus(
      'Wake packet sent, but the PC’s SSH port did not respond within ${waitLimit.inSeconds} seconds. It may still be starting, or SSH may be blocked.',
    );
  }
  return false;
}
