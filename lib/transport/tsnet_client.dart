import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TsnetStatus {
  final String state;
  final String authUrl;
  final List<String> ips;

  const TsnetStatus({
    required this.state,
    this.authUrl = '',
    this.ips = const [],
  });
  bool get isReady => state == 'Running';

  factory TsnetStatus.fromJson(Map<String, dynamic> json) => TsnetStatus(
    state: json['state'] as String? ?? 'Unknown',
    authUrl: json['authUrl'] as String? ?? '',
    ips: (json['ips'] as List? ?? []).cast<String>(),
  );
}

class TsnetLoginRequired implements Exception {
  final TsnetStatus status;
  const TsnetLoginRequired(this.status);
  @override
  String toString() =>
      'Tailscale ${status.state}. Open Settings → Tailscale to sign in or check node approval.';
}

class TsnetClient {
  static const channel = MethodChannel('remote_control/tsnet');
  static final instance = TsnetClient();
  final MethodChannel _channel;
  Future<void>? _starting;
  Future<void>? _ready;

  TsnetClient({MethodChannel? methodChannel})
    : _channel = methodChannel ?? channel;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> useTsnet() async {
    if (!supported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('remote_transport') != 'direct';
  }

  Future<void> setUseTsnet(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('remote_transport', enabled ? 'tsnet' : 'direct');
  }

  Future<void> start() {
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      _starting = null;
      rethrow;
    }
  }

  Future<TsnetStatus> status() async {
    await start();
    final text = await _channel.invokeMethod<String>('status');
    return TsnetStatus.fromJson(jsonDecode(text!) as Map<String, dynamic>);
  }

  Future<void> ensureReady() {
    return _ready ??= _ensureReady().whenComplete(() => _ready = null);
  }

  Future<void> _ensureReady() async {
    await start();
    final current = await status();
    if (current.isReady) return;
    if (current.authUrl.isNotEmpty || current.state == 'NeedsMachineAuth') {
      throw TsnetLoginRequired(current);
    }
    try {
      await _channel.invokeMethod<void>('wait', {'timeoutMs': 15000});
    } on PlatformException {
      final after = await status();
      if (!after.isReady) throw TsnetLoginRequired(after);
    }
  }

  Future<void> openLogin(String url) =>
      _channel.invokeMethod<void>('openLogin', {'url': url});

  Future<List<Map<String, dynamic>>> peers() async {
    await start();
    final text = await _channel.invokeMethod<String>('peers');
    return (jsonDecode(text!) as List)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
  }

  Future<int> dial(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await ensureReady();
    final id = await _channel.invokeMethod<int>('dial', {
      'host': host,
      'port': port,
      'timeoutMs': timeout.inMilliseconds,
    });
    return id!;
  }

  Future<Uint8List> read(int id) async =>
      (await _channel.invokeMethod<Uint8List>('read', {
        'id': id,
        'maxBytes': 65536,
        'timeoutMs': 1000,
      })) ??
      Uint8List(0);

  Future<void> write(int id, Uint8List data) async {
    final count = await _channel.invokeMethod<int>('write', {
      'id': id,
      'data': data,
      'timeoutMs': 10000,
    });
    if (count != data.length) throw StateError('Incomplete tsnet write');
  }

  Future<void> closeConnection(int id) =>
      _channel.invokeMethod<void>('close', {'id': id});

  Future<Map<String, dynamic>> debugRelayStatus() async {
    final raw = await _channel.invokeMethod<String>('debugStatus');
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startDebugRelay(String pc, {bool temporaryRoot = false}) async {
    await ensureReady();
    final raw = await _channel.invokeMethod<String>('startDebugRelay', {'pc': pc.trim(), 'temporaryRoot': temporaryRoot});
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setDebugRelayDuration(int minutes) async {
    final raw = await _channel.invokeMethod<String>('setDebugRelayDuration', {'minutes': minutes});
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  Future<void> stopDebugRelay() => _channel.invokeMethod<void>('stopDebugRelay');

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
    _starting = null;
  }
}
