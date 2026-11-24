import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'linux_desktop.dart';

class SmartBulbException implements Exception {
  const SmartBulbException(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class SmartBulbState {
  SmartBulbState(Map<String, dynamic> data)
    : on = data['on'] as bool,
      mode = data['mode'] as String,
      whiteBrightness = data['whiteBrightness'] as int,
      temperature = data['temperature'] as int,
      hue = data['hue'] as int,
      saturation = data['saturation'] as int,
      colorBrightness = data['colorBrightness'] as int,
      address = data['address'] as String,
      deviceId = data['deviceId'] as String;

  final bool on;
  final String mode, address, deviceId;
  final int whiteBrightness, temperature, hue, saturation, colorBrightness;
}

class SmartBulb {
  const SmartBulb(this.device, this.session);

  final Device device;
  final SshSession session;

  Future<SmartBulbState> read() => _state({'action': 'status'});

  Future<SmartBulbState> power(bool on) =>
      _state({'action': 'power', 'on': on});

  Future<SmartBulbState> white(int brightness, int temperature) => _state({
    'action': 'white',
    'brightness': brightness,
    'temperature': temperature,
  });

  Future<SmartBulbState> color(int brightness, int hue, int saturation) =>
      _state({
        'action': 'color',
        'brightness': brightness,
        'hue': hue,
        'saturation': saturation,
      });

  Future<SmartBulbState> configure({
    required String address,
    required String deviceId,
    required String localKey,
  }) => _state({
    'action': 'configure',
    'address': address,
    'device_id': deviceId,
    'local_key': localKey,
  });

  Future<void> install() async {
    await _run({'action': 'install'}, installing: true);
  }

  Future<SmartBulbState> _state(Map<String, Object> request) async =>
      SmartBulbState(await _run(request));

  Future<Map<String, dynamic>> _run(
    Map<String, Object> request, {
    bool installing = false,
  }) async {
    final client = session.client;
    if (client == null ||
        !session.isConnected ||
        session.deviceId != device.id) {
      throw SmartBulbException('Connect to ${device.name} first.');
    }

    final script = await rootBundle.loadString(
      'assets/automation/smart_bulb.py',
    );
    final source = base64Encode(utf8.encode(script));
    const bootstrap =
        "import base64,sys;exec(compile(base64.b64decode(sys.argv[1]),'wirehelm-bulb','exec'))";
    final interpreter = installing
        ? 'python=python3\n'
        : r'''
python="${XDG_DATA_HOME:-$HOME/.local/share}/wirehelm/smart-bulb/venv/bin/python"
[ -x "$python" ] || python=python3
''';
    final worker =
        '${interpreter}exec "\$python" -c ${desktopShellQuote(bootstrap)} ${desktopShellQuote(source)}';
    if (!identical(client, session.client) || session.deviceId != device.id) {
      throw const SmartBulbException('The connection changed. Try again.');
    }

    final response = await session.run(
      'sh -c ${desktopShellQuote(worker)}',
      input: utf8.encode('${jsonEncode(request)}\n'),
      timeout: Duration(seconds: installing ? 140 : 28),
    );
    const marker = '__WIREHELM_BULB__ ';
    for (final line in const LineSplitter().convert(
      utf8.decode(response, allowMalformed: true),
    )) {
      if (!line.startsWith(marker)) continue;
      final result = jsonDecode(line.substring(marker.length));
      if (result is! Map<String, dynamic>) break;
      final error = result['error'];
      if (error is String) {
        throw SmartBulbException(error, result['code'] as String?);
      }
      return result;
    }
    throw const SmartBulbException(
      'The SSH host did not respond. Check that Python 3 is available.',
    );
  }
}
