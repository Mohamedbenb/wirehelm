import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/devices/identity_installer.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _FishSession extends SshSession {
  _FishSession(this.home) : super(manageBackgroundKeepAlive: false);

  final String home;

  @override
  bool get isConnected => true;

  @override
  String get deviceId => 'desktop';

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    final process = await Process.start(
      'fish',
      ['--no-config', '-c', command],
      environment: {'HOME': home},
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      process.stdin.add(input!);
      await process.stdin.close();
      final exit = await process.exitCode.timeout(timeout!);
      expect(exit, 0, reason: await stderr);
      return utf8.encode(await stdout);
    } finally {
      process.kill();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Linux Install identity works through fish and avoids duplicate keys',
    () async {
      if (!Platform.isLinux) {
        markTestSkipped('Linux fish test');
        return;
      }
      try {
        await Process.run('fish', ['--version']);
      } on ProcessException {
        markTestSkipped('fish is unavailable');
        return;
      }
      final home = await Directory.systemTemp.createTemp('wirehelm identity ');
      addTearDown(() => home.delete(recursive: true));
      final sshDir = await Directory('${home.path}/.ssh').create();
      final authorized = File('${sshDir.path}/authorized_keys');
      const previous = 'ssh-ed25519 AAAAEXISTING previous';
      await authorized.writeAsString(previous);
      const publicKey = r"ssh-ed25519 AAAATEST user's phone ($name)";
      const device = Device(
        id: 'desktop',
        name: 'PC',
        host: 'localhost',
        port: 22,
        username: 'test',
        shellStyle: 'linux',
        commands: [],
      );
      final session = _FishSession(home.path);
      addTearDown(session.dispose);
      final installer = IdentityInstaller();

      final first = await installer.install(
        device: device,
        publicKey: publicKey,
        session: session,
      );
      final second = await installer.install(
        device: device,
        publicKey: publicKey,
        session: session,
      );
      expect(first.alreadyInstalled, isFalse);
      expect(second.alreadyInstalled, isTrue);
      expect(first.target, authorized.path);
      expect(await authorized.readAsString(), '$previous\n$publicKey\n');
      expect((await sshDir.stat()).mode & 0x1ff, 0x1c0);
      expect((await authorized.stat()).mode & 0x1ff, 0x180);
    },
  );
}
