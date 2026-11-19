import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/background_keep_alive.dart';
import 'package:remote_control/ssh/ssh_session_manager.dart';

import 'ssh_health_test.dart' show Client, Socket;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_control/background_keep_alive');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'beginWork' ? 42 : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('work exception releases its shutdown protection', () async {
    await expectLater(
      backgroundKeepAlive.protect('transfer', () async {
        throw StateError('failure');
      }),
      throwsStateError,
    );
    expect(calls, ['beginWork', 'endWork']);
  });
  test('work remains protected while asynchronous action is pending', () async {
    final pending = Completer<int>();
    final run = backgroundKeepAlive.protect('transfer', () => pending.future);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['beginWork']);
    pending.complete(3);
    expect(await run, 3);
    expect(calls, ['beginWork', 'endWork']);
  });
  test(
    'disconnected reconnect target does not retain SSH keep alive',
    () async {
      final manager = SshSessionManager();
      final session = manager.sessionFor('pc');
      final client = Client();
      session.attach(client: client, socket: Socket(), deviceId: 'pc');
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, 'start');
      client.ended.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.lastDeviceId, 'pc');
      expect(calls.last, 'stop');
      manager.dispose();
    },
  );
}
