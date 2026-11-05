import 'dart:typed_data';

import 'package:dartssh2/src/utils/chunk_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fragmented transfers retain bounded storage for partial packets', () {
    final buffer = ChunkBuffer();
    final receive = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 7);
    const packetSize = 32820;
    var peakCapacity = 0;

    // Native reads and encrypted SSH packets do not share a boundary. This
    // leaves a partial packet across reads throughout a full APK transfer.
    for (var i = 0; i < 672; i++) {
      buffer.add(receive);
      final capacity = buffer.data.buffer.lengthInBytes;
      if (capacity > peakCapacity) peakCapacity = capacity;
      buffer.skip((buffer.length ~/ packetSize) * packetSize);
      expect(buffer.length, lessThan(packetSize));
    }

    expect(peakCapacity, lessThanOrEqualTo(128 * 1024));
    expect(buffer.data, everyElement(7));
  });

  test('compaction and growth preserve exposed views and byte order', () {
    final buffer = ChunkBuffer();
    final initial = Uint8List.fromList(
      List.generate(8192, (i) => (i * 17) % 256),
    );
    buffer.add(initial);
    final exposed = buffer.view(512, 128);
    final snapshot = Uint8List.fromList(exposed);
    final tail = Uint8List.fromList(initial.sublist(8192 - 16));
    buffer.skip(8192 - 16);

    final appended = Uint8List(4096)..fillRange(0, 4096, 200);
    buffer.add(appended);
    // The existing capacity is enough after compaction, but its storage
    // must be replaced because callers can still hold views into it.
    expect(buffer.data.buffer.lengthInBytes, 8192);
    expect(identical(buffer.data.buffer, exposed.buffer), isFalse);
    expect(exposed, snapshot);
    expect(buffer.consume(16), tail);
    expect(buffer.data, appended);

    final larger = Uint8List(8192)..fillRange(0, 8192, 100);
    buffer.add(larger);
    expect(exposed, snapshot);
    expect(buffer.consume(4096), appended);
    expect(buffer.consume(), larger);
    expect(buffer.isEmpty, isTrue);
  });

  test('a nearly full sliding buffer grows once to retain append space', () {
    final buffer = ChunkBuffer();
    buffer.add(Uint8List(4096));
    buffer.skip(1);
    final byte = Uint8List(1);
    buffer.add(byte);
    expect(buffer.data.buffer.lengthInBytes, 8192);

    for (var i = 0; i < 8192; i++) {
      buffer.skip(1);
      buffer.add(byte);
      expect(buffer.length, 4096);
      expect(buffer.data.buffer.lengthInBytes, 8192);
    }
  });
}
