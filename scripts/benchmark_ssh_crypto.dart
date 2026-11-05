// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

void main() {
  final data = Uint8List(32768), output = Uint8List(32784), key = Uint8List(32);
  for (final gcm in [true, false]) {
    final clock = Stopwatch()..start();
    for (var i = 0; i < 160; i++) {
      if (gcm) {
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            true,
            AEADParameters(KeyParameter(key), 128, Uint8List(12), Uint8List(4)),
          );
        final written = cipher.processBytes(data, 0, data.length, output, 0);
        cipher.doFinal(output, written);
      } else {
        final cipher = CTRBlockCipher(16, CTRStreamCipher(AESEngine()))
          ..init(true, ParametersWithIV(KeyParameter(key), Uint8List(16)));
        for (var offset = 0; offset < data.length; offset += 16) {
          cipher.processBlock(data, offset, output, offset);
        }
        final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
        mac.process(output.sublist(0, 32768));
      }
    }
    print(
      '${gcm ? 'AES-256-GCM' : 'AES-256-CTR + SHA-256 MAC'}: ${(160 * data.length / 1048576 / (clock.elapsedMicroseconds / 1e6)).toStringAsFixed(2)} MiB/s',
    );
  }
}
