import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ssh_identity.dart';

class IdentityStorage {
  static const _metadataKey = 'ssh_identities';

  // Your old single-key storage location.
  static const _legacyPrivateKey = 'ssh_private_key';

  static const _secureStorage =
      FlutterSecureStorage();

  String _privateKeyName(String identityId) {
    return 'ssh_identity_private_$identityId';
  }

  Future<List<SshIdentity>> loadIdentities() async {
    final prefs =
        await SharedPreferences.getInstance();

    final raw =
        prefs.getString(_metadataKey);

    if (raw != null) {
      final decoded =
          jsonDecode(raw) as List<dynamic>;

      return decoded
          .map(
            (item) => SshIdentity.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }

    //
    // No new identity database yet.
    // Attempt to migrate the old working key.
    //
    return _migrateLegacyIdentity();
  }

  Future<List<SshIdentity>>
      _migrateLegacyIdentity() async {
    final oldPrivateKey =
        await _secureStorage.read(
      key: _legacyPrivateKey,
    );

    if (oldPrivateKey == null) {
      return [];
    }

    final keys =
        SSHKeyPair.fromPem(oldPrivateKey);

    if (keys.isEmpty) {
      return [];
    }

    final publicEncoded =
        keys.first.toPublicKey().encode();

    final publicKey =
        'ssh-ed25519 '
        '${base64Encode(publicEncoded)} '
        'remote-control-app';

    const identityId = 'legacy_default';

    final identity = SshIdentity(
      id: identityId,
      name: 'Default',
      publicKey: publicKey,
    );

    //
    // Copy the private key into the new storage format.
    //
    await _secureStorage.write(
      key: _privateKeyName(identityId),
      value: oldPrivateKey,
    );

    await saveIdentities([
      identity,
    ]);

    return [
      identity,
    ];
  }

  Future<void> saveIdentities(
    List<SshIdentity> identities,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      identities
          .map(
            (identity) =>
                identity.toJson(),
          )
          .toList(),
    );

    await prefs.setString(
      _metadataKey,
      encoded,
    );
  }

  Future<void> savePrivateKey({
    required String identityId,
    required String privateKeyPem,
  }) async {
    await _secureStorage.write(
      key: _privateKeyName(identityId),
      value: privateKeyPem,
    );
  }

  Future<String?> loadPrivateKey(
    String identityId,
  ) {
    return _secureStorage.read(
      key: _privateKeyName(identityId),
    );
  }

  Future<void> deleteIdentity(
    String identityId,
  ) async {
    final identities =
        await loadIdentities();

    final updated = identities
        .where(
          (identity) =>
              identity.id != identityId,
        )
        .toList();

    await saveIdentities(updated);

    await _secureStorage.delete(
      key: _privateKeyName(identityId),
    );
  }
}