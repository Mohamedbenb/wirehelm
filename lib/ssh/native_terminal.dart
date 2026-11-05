import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

bool get nativeTerminalSupported => Platform.isAndroid;

/// A persistent native emulator, independent of whether its view is visible.
class NativeTerminal {
  static const channel = MethodChannel('remote_control/native_terminal');
  static final _sessions = <int, NativeTerminal>{};
  static int _nextId = 0;
  final int id = ++_nextId;
  void Function(String data, bool protocol)? onOutput;
  void Function(int, int, int, int)? onResize;
  Future<void> Function()? onPasteRequest;
  bool _disposed = false;

  NativeTerminal() {
    _sessions[id] = this;
    channel.setMethodCallHandler((call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final session = _sessions[args['id']];
      if (session == null) return;
      switch (call.method) {
        case 'output':
          session.onOutput?.call(
            utf8.decode(args['data'] as List<int>, allowMalformed: true),
            args['protocol'] == true,
          );
        case 'resize':
          session.onResize?.call(
            args['width'] as int,
            args['height'] as int,
            args['pixelWidth'] as int,
            args['pixelHeight'] as int,
          );
        case 'copy':
          await Clipboard.setData(ClipboardData(text: args['text'] as String));
        case 'pasteRequest':
          await session.onPasteRequest?.call();
      }
    });
    send('create');
  }

  void send(String method, [Map<String, dynamic> args = const {}]) {
    if (_disposed) return;
    unawaited(channel.invokeMethod<void>(method, {'id': id, ...args}));
  }

  Future<String> text({bool all = false}) async =>
      await channel.invokeMethod<String>('text', {'id': id, 'all': all}) ?? '';

  void dispose() {
    send('dispose');
    _disposed = true;
    _sessions.remove(id);
  }
}
