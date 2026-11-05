import 'package:flutter/services.dart';

class UploadStore {
  static const channel = MethodChannel('remote_control/uploads');
  static Future<Map<String, dynamic>?> pick() =>
      channel.invokeMapMethod<String, dynamic>('pick');
  static Future<void> open(String uri) =>
      channel.invokeMethod<void>('open', {'uri': uri});
  static Stream<Uint8List> read(bool Function() cancelled) async* {
    while (true) {
      if (cancelled()) throw StateError('Upload cancelled.');
      final bytes = await channel
          .invokeMethod<Uint8List>('read')
          .timeout(const Duration(seconds: 30));
      if (cancelled()) throw StateError('Upload cancelled.');
      if (bytes == null || bytes.isEmpty) break;
      yield bytes;
    }
  }

  static Future<void> close() => channel.invokeMethod<void>('close');
}
