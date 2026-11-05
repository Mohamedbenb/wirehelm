import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final backgroundKeepAlive =
    BackgroundKeepAlive();

class BackgroundKeepAlive {
  static const MethodChannel _channel =
      MethodChannel(
    'remote_control/background_keep_alive',
  );

  Future<void> start() async {
    if (defaultTargetPlatform !=
        TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'start',
      );
    } catch (e) {
      debugPrint(
        'Could not start background '
        'keep-alive service: $e',
      );
    }
  }

  Future<void> stop() async {
    if (defaultTargetPlatform !=
        TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'stop',
      );
    } catch (e) {
      debugPrint(
        'Could not stop background '
        'keep-alive service: $e',
      );
    }
  }

  Future<bool> isRunning() async {
    if (defaultTargetPlatform !=
        TargetPlatform.android) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            'isRunning',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}