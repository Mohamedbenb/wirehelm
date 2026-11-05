import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/device.dart';
import '../services/credential_storage.dart';
import '../services/identity_storage.dart';
import '../services/known_host_storage.dart';
import '../services/lan_address_recovery.dart';
import '../ssh/ssh_session.dart';
import '../transport/tsnet_client.dart';
import '../transport/tsnet_socket.dart';

typedef HostKeyVerifier = Future<bool> Function(
  Device device,
  String keyType,
  Uint8List fingerprint,
);

class DeviceConnectionService {
  static const _algorithms = SSHAlgorithms(
    cipher: [
      SSHCipherType.aes256ctr,
      SSHCipherType.aes128ctr,
      SSHCipherType.aes256gcm,
      SSHCipherType.aes128gcm,
      SSHCipherType.chacha20poly1305,
    ],
  );
  final IdentityStorage _identityStorage;
  final CredentialStorage _credentialStorage;
  final KnownHostStorage _knownHostStorage;
  final LanAddressRecovery _lanRecovery;
  static final Map<String, DateTime> _lastLanSearch = {};

  DeviceConnectionService({
    IdentityStorage? identityStorage,
    CredentialStorage? credentialStorage,
    KnownHostStorage? knownHostStorage,
    LanAddressRecovery? lanRecovery,
  }) : _identityStorage = identityStorage ?? IdentityStorage(),
       _credentialStorage = credentialStorage ?? CredentialStorage(),
       _knownHostStorage = knownHostStorage ?? KnownHostStorage(),
       _lanRecovery = lanRecovery ?? LanAddressRecovery();

  /// Finds a saved device on the active Wi-Fi LAN and verifies its existing
  /// SSH host key before returning a replacement address.
  Future<String?> discoverLocalHost(Device device) async {
    final known = await _knownHostStorage.getKnownHost(
      host: device.host,
      port: device.port,
    );
    if (known == null) {
      throw StateError(
        'Connect to this device once before LAN discovery so its SSH identity can be verified.',
      );
    }
    final candidates = await _lanRecovery.sshCandidates(port: device.port);
    for (final candidate in candidates) {
      if (candidate == device.localHost || candidate == device.host) continue;
      if (await _lanRecovery.matchesTrustedHostKey(
        host: candidate,
        device: device,
        knownHost: known,
      )) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> connect(
    Device device, {
    required HostKeyVerifier verifyHostKey,

    //
    // Migration support:
    //
    // null
    //   -> use the existing global
    //      singleton exactly as before.
    //
    // supplied
    //   -> attach this device to its own
    //      SshSession instance.
    //
    SshSession? targetSession,
    Future<void> Function(String host)? onLocalHostFound,
  }) async {
    final session = targetSession ?? sshSession;
    final connectClock = Stopwatch()..start();
    SSHSocket? socket;
    SSHClient? client;
    String? route, connectedHost;
    final trustedHost = await _knownHostStorage.getKnownHost(
      host: device.host,
      port: device.port,
    );

    Future<void> connectAndAuthenticate(
      String host, {
      required bool local,
      required bool requireKnownKey,
    }) async {
      SSHSocket? attemptSocket;
      SSHClient? attemptClient;
      try {
        if (local) {
          attemptSocket = await SSHSocket.connect(
            host,
            device.port,
            timeout: const Duration(seconds: 2),
          );
        } else {
          final tsnet = await TsnetClient.instance.useTsnet();
          attemptSocket = tsnet
              ? await TsnetSocket.connect(host, device.port)
              : await SSHSocket.connect(
                  host,
                  device.port,
                  timeout: const Duration(seconds: 10),
                );
          route = tsnet ? 'Tailscale' : 'Direct';
        }
        final HostKeyVerifier verifier = requireKnownKey
            ? (
                Device targetDevice,
                String keyType,
                Uint8List fingerprint,
              ) async =>
                  trustedHost != null &&
                  keyType == trustedHost.keyType &&
                  String.fromCharCodes(fingerprint) == trustedHost.fingerprint
            : (Device targetDevice, String keyType, Uint8List fingerprint) =>
                  verifyHostKey(targetDevice, keyType, fingerprint);
        attemptClient = device.authType == 'password'
            ? await _createPasswordClient(
                socket: attemptSocket,
                device: device,
                verifyHostKey: verifier,
              )
            : await _createKeyClient(
                socket: attemptSocket,
                device: device,
                verifyHostKey: verifier,
              );
        await attemptClient.authenticated;
        socket = attemptSocket;
        client = attemptClient;
        route = local ? 'LAN' : route;
        connectedHost = host;
      } catch (_) {
        attemptClient?.close();
        attemptSocket?.close();
        rethrow;
      }
    }

    try {
      final savedLocalHost = device.localHost.trim();
      Object? localFailure;
      if (savedLocalHost.isNotEmpty) {
        try {
          await connectAndAuthenticate(
            savedLocalHost,
            local: true,
            requireKnownKey: false,
          );
        } catch (error) {
          localFailure = error;
        }
      }

      if (client == null && savedLocalHost.isNotEmpty && trustedHost != null) {
        final now = DateTime.now();
        final last = _lastLanSearch[device.id];
        if (last == null ||
            now.difference(last) >= const Duration(seconds: 45)) {
          _lastLanSearch[device.id] = now;
          List<String> candidates;
          try {
            candidates = await _lanRecovery.sshCandidates(port: device.port);
          } catch (_) {
            candidates = const [];
          }
          for (final candidate in candidates) {
            if (candidate == savedLocalHost || candidate == device.host) {
              continue;
            }
            try {
              await connectAndAuthenticate(
                candidate,
                local: true,
                requireKnownKey: true,
              );
              break;
            } catch (_) {
              // Continue until the known SSH host key authenticates.
            }
          }
        }
      }

      if (client == null) {
        try {
          await connectAndAuthenticate(
            device.host.trim(),
            local: false,
            requireKnownKey: false,
          );
        } catch (_) {
          if (localFailure != null) {
            Error.throwWithStackTrace(localFailure, StackTrace.current);
          }
          rethrow;
        }
      }

      final connectedSocket = socket!;
      final connectedClient = client!;

      session.attach(
        client: connectedClient,
        socket: connectedSocket,
        deviceId: device.id,
        route: route,
        host: connectedHost,
      );
      session.connectionDuration = connectClock.elapsed;
      if (route == 'LAN' && connectedHost != savedLocalHost) {
        try {
          await onLocalHostFound?.call(connectedHost!);
        } catch (_) {
          // Persistence trouble should not tear down a working SSH session.
        }
      }
    } catch (_) {
      //
      // Once attached successfully,
      // SshSession owns these resources.
      //
      // If anything fails before attach,
      // clean them up here.
      //
      try {
        client?.close();
      } catch (_) {}

      try {
        socket?.close();
      } catch (_) {}

      rethrow;
    }
  }

  Future<SSHClient> _createPasswordClient({
    required SSHSocket socket,
    required Device device,
    required HostKeyVerifier verifyHostKey,
  }) async {
    final passwordId = device.passwordId;

    if (passwordId == null || passwordId.isEmpty) {
      throw Exception(
        'No password is configured '
        'for this device.',
      );
    }

    final password = await _credentialStorage.loadPassword(passwordId);

    if (password == null || password.isEmpty) {
      throw Exception(
        'The saved password could '
        'not be found.',
      );
    }

    return SSHClient(
      socket,
      algorithms: _algorithms,
      username: device.username,

      onPasswordRequest: () => password,

      onVerifyHostKey: (keyType, fingerprint) {
        return verifyHostKey(device, keyType, fingerprint);
      },

      authTimeout: const Duration(seconds: 15),
    );
  }

  Future<SSHClient> _createKeyClient({
    required SSHSocket socket,
    required Device device,
    required HostKeyVerifier verifyHostKey,
  }) async {
    final identities = await _identityStorage.loadIdentities();

    if (identities.isEmpty) {
      throw Exception(
        'No SSH identities are '
        'available.',
      );
    }

    //
    // Backward compatibility:
    //
    // Older saved devices may not have
    // an identityId because the app used
    // to support only one key.
    //
    var identityId = device.identityId;

    if (identityId == null || identityId.isEmpty) {
      identityId = identities.first.id;
    }

    var identityFound = false;

    for (final identity in identities) {
      if (identity.id == identityId) {
        identityFound = true;
        break;
      }
    }

    if (!identityFound) {
      throw Exception(
        'The selected SSH identity '
        'could not be found.',
      );
    }

    final privateKey = await _identityStorage.loadPrivateKey(identityId);

    if (privateKey == null || privateKey.trim().isEmpty) {
      throw Exception(
        'The private key for the '
        'selected identity could '
        'not be found.',
      );
    }

    final keyPairs = SSHKeyPair.fromPem(privateKey);

    if (keyPairs.isEmpty) {
      throw Exception(
        'The selected SSH private '
        'key is invalid.',
      );
    }

    return SSHClient(
      socket,
      username: device.username,

      identities: keyPairs,
      algorithms: _algorithms,

      onVerifyHostKey: (keyType, fingerprint) {
        return verifyHostKey(device, keyType, fingerprint);
      },

      authTimeout: const Duration(seconds: 15),
    );
  }
}
