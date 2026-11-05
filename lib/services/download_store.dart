import 'package:flutter/services.dart';

import 'dart:typed_data' show BytesBuilder;

class DownloadStore {
  static const _channel = MethodChannel('remote_control/downloads');
  static Future<void> save(
    String name,
    Stream<Uint8List> bytes, {
    void Function(int)? onProgress,
  }) async {
    final id = await _channel.invokeMethod<String>('begin', {'name': name});
    var received = 0;
    final buffer = BytesBuilder(copy: false);
    final clock = Stopwatch()..start();
    var lastProgress = -100;
    Future<void> pendingWrite = Future<void>.value();
    Future<void> flush() async {
      if (buffer.isEmpty) return;
      final chunk = buffer.takeBytes();
      await pendingWrite;
      pendingWrite = _channel
          .invokeMethod<void>('append', {'id': id, 'bytes': chunk})
          .then((_) {
            received += chunk.length;
            if (clock.elapsedMilliseconds - lastProgress >= 100) {
              onProgress?.call(received);
              lastProgress = clock.elapsedMilliseconds;
            }
          });
      pendingWrite.ignore();
    }

    try {
      await for (final chunk in bytes) {
        buffer.add(chunk);
        if (buffer.length >= 512 * 1024) await flush();
      }
      await flush();
      await pendingWrite;
      await _channel.invokeMethod<void>('finish', {'id': id});
      onProgress?.call(received);
    } catch (_) {
      await _channel.invokeMethod<void>('cancel', {'id': id});
      rethrow;
    }
  }
}
