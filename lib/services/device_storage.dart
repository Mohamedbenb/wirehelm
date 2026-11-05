import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

class DeviceStorage {
  static const _storageKey = 'devices';

  Future<List<Device>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_storageKey);

    if (raw == null) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;

    return decoded
        .map(
          (item) => Device.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<void> saveDevices(
    List<Device> devices,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      devices.map((device) => device.toJson()).toList(),
    );

    await prefs.setString(
      _storageKey,
      encoded,
    );
  }
}