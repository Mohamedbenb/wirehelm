import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../models/device.dart';
import '../services/known_host_storage.dart';
import '../transport/tsnet_client.dart';
import 'device_discovery.dart';

/// Discovers SSH endpoints on the active Wi-Fi subnet. Callers must still
/// verify the SSH host key before trusting a candidate.
class LanAddressRecovery {
  final Future<String?> Function(String method)? invoke;
  final Future<bool> Function(String host, int port)? probeSsh;

  LanAddressRecovery({this.invoke, this.probeSsh});

  Future<List<String>> sshCandidates({int port = 22, int limit = 8}) async {
    final info = await (invoke ?? _invoke)('lanInfo');
    if (info == null) return const [];
    final snapshot = jsonDecode(info) as Map<String, dynamic>;
    if (snapshot['wifi'] != true) {
      throw StateError('Connect this phone to the device\'s Wi-Fi network.');
    }
    final hosts = localScanHosts(snapshot);
    if (hosts.isEmpty) {
      throw StateError('No usable IPv4 Wi-Fi subnet is available.');
    }

    final found = <String>[];
    var next = 0;
    await Future.wait(
      List.generate(32, (_) async {
        while (next < hosts.length && found.length < limit) {
          final host = hosts[next++];
          try {
            if (await (probeSsh ?? _probeSsh)(host, port)) found.add(host);
          } catch (_) {
            // Most addresses have no SSH listener; continue the bounded scan.
          }
        }
      }),
    );
    return List.unmodifiable(found);
  }

  Future<bool> matchesTrustedHostKey({
    required String host,
    required Device device,
    required KnownHost knownHost,
  }) async {
    SSHSocket? socket;
    SSHClient? client;
    final checked = Completer<bool>();
    try {
      socket = await SSHSocket.connect(
        host,
        device.port,
        timeout: const Duration(milliseconds: 900),
      );
      client = SSHClient(
        socket,
        username: device.username,
        identities: const [],
        authTimeout: const Duration(seconds: 2),
        handshakeTimeout: const Duration(seconds: 2),
        onVerifyHostKey: (type, fingerprint) async {
          final same =
              type == knownHost.keyType &&
              String.fromCharCodes(fingerprint) == knownHost.fingerprint;
          if (!checked.isCompleted) checked.complete(same);
          return same;
        },
      );
      return await checked.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    } finally {
      client?.close();
      socket?.close();
    }
  }

  Future<String?> _invoke(String method) =>
      TsnetClient.channel.invokeMethod<String>(method);

  Future<bool> _probeSsh(String host, int port) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 350),
    );
    try {
      final banner = await socket.first.timeout(
        const Duration(milliseconds: 350),
      );
      return utf8.decode(banner, allowMalformed: true).startsWith('SSH-');
    } finally {
      socket.destroy();
    }
  }
}
