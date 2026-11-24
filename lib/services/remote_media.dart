import 'dart:convert';
import 'dart:typed_data';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'linux_desktop.dart';

class MediaInput {
  final String id, name;
  final bool camera;
  final bool pulse;
  const MediaInput(this.id, this.name, this.camera, {this.pulse = false});
}

class MediaInventory {
  final bool windows, ffmpeg;
  final List<MediaInput> inputs;
  const MediaInventory(this.windows, this.ffmpeg, this.inputs);
}

String mediaQuote(String value, bool windows) {
  if (windows) {
    if (RegExp(r'["\r\n%]').hasMatch(value)) {
      throw ArgumentError('Unsupported device name');
    }
    return '"$value"';
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<MediaInventory> discoverMedia(Device device, SshSession session) async {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device first.');
  }
  var windows = device.shellStyle == 'windows';
  if (device.shellStyle == 'auto') {
    final output = utf8.decode(
      await session.run('uname -s', timeout: const Duration(seconds: 8)),
      allowMalformed: true,
    );
    windows = !output.contains('Linux');
  }
  const linuxProbe =
      linuxDesktopEnvironment +
      r'''
command -v ffmpeg >/dev/null && echo __FFMPEG__
for p in /sys/class/video4linux/video*; do
 [ -e "$p" ] || continue
 printf '__CAM__\t/dev/%s\t%s\n' "${p##*/}" "$(cat "$p/name")"
done
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
  pactl list short sources | awk '{ printf "__PULSE__\t%s\n", $2 }'
else
  arecord -l 2>/dev/null
fi
''';
  final output = utf8.decode(
    await session.run(
      windows
          ? 'ffmpeg -version && ffmpeg -hide_banner -list_devices true -f dshow -i dummy'
          : 'sh -c ${desktopShellQuote(linuxProbe)}',
      timeout: const Duration(seconds: 15),
    ),
    allowMalformed: true,
  );
  return parseMediaInventory(output, windows);
}

MediaInventory parseMediaInventory(String output, bool windows) {
  final inputs = <MediaInput>[];
  if (windows) {
    for (final m in RegExp(
      r'"([^"]+)"\s+\((video|audio)\)',
    ).allMatches(output)) {
      inputs.add(MediaInput(m[1]!, m[1]!, m[2] == 'video'));
    }
  } else {
    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith('__CAM__\t')) {
        final parts = line.split('\t');
        if (parts.length >= 3) inputs.add(MediaInput(parts[1], parts[2], true));
      }
      if (line.startsWith('__PULSE__\t')) {
        final id = line.substring('__PULSE__\t'.length);
        if (id.isNotEmpty) {
          final name = id.endsWith('.monitor') ? 'Desktop audio · $id' : id;
          inputs.add(MediaInput(id, name, false, pulse: true));
        }
      }
      final m = RegExp(r'^card (\d+):.*?\[(.*?)\], device (\d+):\s*(.*)')
          .firstMatch(line);
      if (m != null) {
        inputs.add(
          MediaInput('plughw:${m[1]},${m[3]}', '${m[2]} · ${m[4]}', false),
        );
      }
    }
  }
  return MediaInventory(
    windows,
    windows
        ? output.contains('ffmpeg version ') ||
              output.contains('[dshow') ||
              inputs.isNotEmpty
        : output.contains('__FFMPEG__'),
    inputs,
  );
}

String mediaCaptureCommand(MediaInput input, bool windows) {
  final source = windows
      ? '-f dshow -i ${mediaQuote('${input.camera ? 'video' : 'audio'}=${input.id}', true)}'
      : '-f ${input.camera
            ? 'v4l2'
            : input.pulse
            ? 'pulse'
            : 'alsa'} -i ${mediaQuote(input.id, false)}';
  final command =
      'ffmpeg -hide_banner -loglevel error $source -t 600 ${input.camera ? '-an -vf scale=640:-2,fps=10 -c:v mjpeg -q:v 6 -f image2pipe' : '-vn -ac 1 -ar 16000 -c:a pcm_s16le -f s16le'} pipe:1';
  return input.pulse
      ? 'sh -c ${desktopShellQuote('${linuxDesktopEnvironment}exec $command')}'
      : command;
}

// JPEG markers may straddle SSH packets. Bound memory if a capture is corrupt.
class JpegFrames {
  final List<int> _buffer = [];
  List<Uint8List> add(List<int> bytes) {
    _buffer.addAll(bytes);
    final frames = <Uint8List>[];
    while (true) {
      var start = -1, end = -1;
      for (var i = 0; i + 1 < _buffer.length; i++) {
        if (start < 0 && _buffer[i] == 255 && _buffer[i + 1] == 216) start = i;
        if (start >= 0 && _buffer[i] == 255 && _buffer[i + 1] == 217) {
          end = i + 2;
          break;
        }
      }
      if (end < 0) break;
      frames.add(Uint8List.fromList(_buffer.sublist(start, end)));
      _buffer.removeRange(0, end);
    }
    if (_buffer.length > 4 * 1024 * 1024) {
      _buffer.clear();
      throw StateError('Camera frame exceeded 4 MB.');
    }
    return frames;
  }
}
