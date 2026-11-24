import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/services/wayland_access.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _VerifiedSession extends SshSession {
  _VerifiedSession(this.hostKeyIdentity, this.authenticatedUsername)
    : super(manageBackgroundKeepAlive: false);

  @override
  final String hostKeyIdentity;

  @override
  final String authenticatedUsername;

  @override
  String get deviceId => 'desktop';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'KDE approvals rotate separately and stay bound to the SSH account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const device = Device(
        id: 'desktop',
        name: 'PC',
        host: 'localhost',
        port: 22,
        username: 'test',
        shellStyle: 'linux',
        commands: [],
      );
      final session = _VerifiedSession('verified-key', 'test');
      final newHost = _VerifiedSession('new-key', 'test');
      final newUser = _VerifiedSession('verified-key', 'other-user');
      addTearDown(session.dispose);
      addTearDown(newHost.dispose);
      addTearDown(newUser.dispose);
      Future<WaylandAccess> keyboard([SshSession? connection]) =>
          WaylandAccess.read(
            device,
            connection ?? session,
            WaylandAccessMode.keyboard,
          );

      expect((await keyboard()).remember, isFalse);
      await (await keyboard()).setRemember(true);
      final pending = await keyboard();
      expect(pending.remember, isTrue);
      expect(pending.token, isNull);
      await pending.recordApproval('keyboard-token');
      final approved = await keyboard();
      expect(jsonDecode(utf8.decode(approved.startupMessage)), {
        'remember': true,
        'restoreToken': 'keyboard-token',
      });
      expect((await keyboard(newHost)).remember, isFalse);
      expect((await keyboard(newUser)).remember, isFalse);
      expect(
        (await WaylandAccess.read(
          device,
          session,
          WaylandAccessMode.desktop,
        )).remember,
        isFalse,
      );

      await approved.recordApproval('new-keyboard-token');
      final rotating = await keyboard();
      expect(rotating.token, 'new-keyboard-token');
      await rotating.recordApproval(null);
      final staleRequest = await keyboard();
      expect(staleRequest.remember, isTrue);
      expect(staleRequest.token, isNull);
      await staleRequest.setRemember(false);
      await staleRequest.recordApproval('late-reply');
      expect((await keyboard()).remember, isFalse);
    },
  );
}
