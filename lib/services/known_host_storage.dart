import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class KnownHost {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  const KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  String get endpoint => '$host:$port';

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'keyType': keyType,
      'fingerprint': fingerprint,
    };
  }

  factory KnownHost.fromJson(
    Map<String, dynamic> json,
  ) {
    return KnownHost(
      host: json['host'] as String,
      port: json['port'] as int,
      keyType: json['keyType'] as String,
      fingerprint:
          json['fingerprint'] as String,
    );
  }
}

class KnownHostStorage {
  static const String _storageKey =
      'ssh_known_hosts';

  String _endpoint(
    String host,
    int port,
  ) {
    return '$host:$port';
  }

  Future<List<KnownHost>>
      loadKnownHosts() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final raw =
        prefs.getString(_storageKey);

    if (raw == null ||
        raw.isEmpty) {
      return [];
    }

    final decoded =
        jsonDecode(raw)
            as List<dynamic>;

    return decoded
        .map(
          (item) =>
              KnownHost.fromJson(
            Map<String, dynamic>.from(
              item,
            ),
          ),
        )
        .toList();
  }

  Future<KnownHost?> getKnownHost({
    required String host,
    required int port,
  }) async {
    final endpoint =
        _endpoint(host, port);

    final knownHosts =
        await loadKnownHosts();

    for (final item
        in knownHosts) {
      if (item.endpoint ==
          endpoint) {
        return item;
      }
    }

    return null;
  }

  Future<void> trustHost({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final endpoint =
        _endpoint(host, port);

    final knownHosts =
        await loadKnownHosts();

    final updated = knownHosts
        .where(
          (item) =>
              item.endpoint !=
              endpoint,
        )
        .toList();

    updated.add(
      KnownHost(
        host: host,
        port: port,
        keyType: keyType,
        fingerprint:
            fingerprint,
      ),
    );

    await prefs.setString(
      _storageKey,
      jsonEncode(
        updated
            .map(
              (item) =>
                  item.toJson(),
            )
            .toList(),
      ),
    );
  }

  Future<void> forgetHost({
    required String host,
    required int port,
  }) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final endpoint =
        _endpoint(host, port);

    final knownHosts =
        await loadKnownHosts();

    final updated = knownHosts
        .where(
          (item) =>
              item.endpoint !=
              endpoint,
        )
        .toList();

    await prefs.setString(
      _storageKey,
      jsonEncode(
        updated
            .map(
              (item) =>
                  item.toJson(),
            )
            .toList(),
      ),
    );
  }
}