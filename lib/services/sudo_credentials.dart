final sudoCredentials =
    SudoCredentials();

class SudoCredentials {
  final Map<String, String>
      _passwords = {};

  String? passwordFor(
    String deviceId,
  ) {
    return _passwords[deviceId];
  }

  void remember({
    required String deviceId,
    required String password,
  }) {
    _passwords[deviceId] =
        password;
  }

  void clearDevice(
    String deviceId,
  ) {
    _passwords.remove(
      deviceId,
    );
  }

  void clearAll() {
    _passwords.clear();
  }
}