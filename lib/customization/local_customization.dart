import 'dart:convert';

import 'package:flutter/services.dart';

class LocalCustomization {
  static const channel = MethodChannel('remote_control/customization');
  static Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic>? arguments,
  ]) async {
    final raw = await channel.invokeMethod<String>(operation, arguments);
    return Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
  }
}
