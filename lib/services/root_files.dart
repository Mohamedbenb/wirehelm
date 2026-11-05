import 'dart:convert';

import 'package:flutter/services.dart';

class RootFiles {
  static const channel = MethodChannel('remote_control/root_files');
  static Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> args = const {},
  ]) async {
    final raw = await channel.invokeMethod<String>(operation, args);
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> lock() => channel.invokeMethod<void>('lock');
}
