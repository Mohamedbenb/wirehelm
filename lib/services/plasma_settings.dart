import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'linux_desktop.dart';

class PlasmaSettings {
  const PlasmaSettings(this.device, this.session);

  final Device device;
  final SshSession session;

  Future<Map<String, dynamic>> run(Map<String, Object?> request) async {
    final client = session.client;
    if (client == null ||
        !session.isConnected ||
        session.deviceId != device.id) {
      throw StateError('Connect to ${device.name} first.');
    }
    final script = await rootBundle.loadString(
      'assets/desktop/plasma_settings.py',
    );
    final source = base64Encode(utf8.encode(script));
    const bootstrap =
        "import base64,sys;exec(compile(base64.b64decode(sys.argv[1]),'wirehelm-plasma','exec'))";
    final worker =
        linuxDesktopEnvironment +
        r'''
if [ -z "$WAYLAND_DISPLAY" ] || [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  printf '%s\n' '__WIREHELM_SETTINGS__ {"error":"Sign in to KDE Plasma Wayland on the PC first."}'
  exit 1
fi
export QT_QPA_PLATFORM=wayland
''' +
        'exec python3 -c ${desktopShellQuote(bootstrap)} ${desktopShellQuote(source)}';
    if (!identical(client, session.client)) {
      throw StateError('The PC connection changed.');
    }
    final response = await session.run(
      'sh -c ${desktopShellQuote(worker)}',
      input: utf8.encode('${jsonEncode(request)}\n'),
      timeout: const Duration(seconds: 22),
    );
    const marker = '__WIREHELM_SETTINGS__ ';
    for (final line in const LineSplitter().convert(
      utf8.decode(response, allowMalformed: true),
    )) {
      if (line.startsWith(marker)) {
        final decoded =
            jsonDecode(line.substring(marker.length)) as Map<String, dynamic>;
        final error = decoded['error'];
        if (error is String) throw StateError(error);
        return decoded;
      }
    }
    throw StateError(
      'Plasma did not return its settings. Check the SSH session.',
    );
  }
}

class PlasmaDisplay {
  PlasmaDisplay(Map<String, dynamic> output)
    : id = output['id'] as int,
      name = output['name'] as String,
      enabled = output['enabled'] as bool,
      primary = output['priority'] == 1,
      scale = (output['scale'] as num).toDouble(),
      rotation = output['rotation'] as int,
      x = output['pos']['x'] as int,
      y = output['pos']['y'] as int,
      mirrorId = (output['replicationSource'] as int?) ?? 0,
      currentMode = output['currentModeId'] as String?,
      modes = [
        for (final mode in output['modes'] as List)
          (id: mode['id'] as String, label: formatMode(mode)),
      ];

  final int id, rotation, x, y, mirrorId;
  final String name;
  final String? currentMode;
  final bool enabled, primary;
  final double scale;
  final List<({String id, String label})> modes;

  static String formatMode(Map<String, dynamic> mode) {
    final size = mode['size'] as Map<String, dynamic>;
    final refresh = (mode['refreshRate'] as num)
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return '${size['width']} × ${size['height']} · $refresh Hz';
  }

  static List<PlasmaDisplay> fromResponse(Map<String, dynamic> response) => [
    for (final output in response['outputs'] as List)
      PlasmaDisplay(output as Map<String, dynamic>),
  ];
}
