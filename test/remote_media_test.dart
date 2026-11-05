import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_media.dart';

void main() {
  test('FFmpeg 9 input logging prefix still detects installed FFmpeg', () {
    final result = parseMediaInventory(
      '[in#0 @ 123] "HD Pro Webcam C920" (video)\n[in#0 @ 123] "Microphone" (audio)',
      true,
    );
    expect(result.ffmpeg, true);
    expect(result.inputs.length, 2);
  });
  test(
    'Windows capture enumeration distinguishes inputs and ignores aliases',
    () {
      final result = parseMediaInventory(
        '[dshow @ 123] "USB Camera" (video)\n[dshow @ 123] Alternative name "@device_pnp_abc"\n[dshow @ 123] "Microphone" (audio)',
        true,
      );
      expect(result.ffmpeg, true);
      expect(result.inputs.length, 2);
      expect(result.inputs.first.camera, true);
      expect(result.inputs.last.camera, false);
      expect(
        parseMediaInventory('ffmpeg is not recognized', true).ffmpeg,
        false,
      );
    },
  );
  test('Linux camera nodes and ALSA capture IDs are preserved', () {
    final result = parseMediaInventory(
      '__FFMPEG__\n__CAM__\t/dev/video0\tUSB Camera\ncard 2: USB [USB Audio], device 1: USB Audio [USB Audio]',
      false,
    );
    expect(result.inputs.map((i) => i.id), ['/dev/video0', 'plughw:2,1']);
    expect(
      mediaCaptureCommand(result.inputs.last, false),
      contains('-ac 1 -ar 16000'),
    );
  });
  test(
    'JPEG parsing handles marker boundaries and several frames per packet',
    () {
      final frames = JpegFrames();
      expect(frames.add([0, 255]), isEmpty);
      expect(frames.add([216, 1, 255]), isEmpty);
      final result = frames.add([217, 255, 216, 2, 255, 217]);
      expect(result, [
        [255, 216, 1, 255, 217],
        [255, 216, 2, 255, 217],
      ]);
    },
  );
  test('device names are quoted and unsafe Windows expansion rejected', () {
    expect(mediaQuote("Camera's input", false), contains("'\"'\"'"));
    expect(() => mediaQuote('%PATH%', true), throwsArgumentError);
    expect(
      mediaCaptureCommand(const MediaInput('USB Camera', 'Camera', true), true),
      contains('"video=USB Camera"'),
    );
  });
}
