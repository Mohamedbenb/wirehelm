import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialStorage {
  static const FlutterSecureStorage _storage =
      FlutterSecureStorage();

  String _passwordKey(String passwordId) {
    return 'ssh_password_$passwordId';
  }

  Future<void> savePassword({
    required String passwordId,
    required String password,
  }) async {
    await _storage.write(
      key: _passwordKey(passwordId),
      value: password,
    );
  }

  Future<String?> loadPassword(
    String passwordId,
  ) {
    return _storage.read(
      key: _passwordKey(passwordId),
    );
  }

  Future<void> deletePassword(
    String passwordId,
  ) {
    return _storage.delete(
      key: _passwordKey(passwordId),
    );
  }
}