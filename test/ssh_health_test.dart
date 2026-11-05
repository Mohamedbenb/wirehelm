import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class Client implements SSHClient {
  final ended = Completer<void>();
  bool closed = false;
  bool fail = false;
  @override
  bool get isClosed => closed;
  @override
  Future<void> get done => ended.future;
  @override
  Future<void> ping() async {
    if (fail) throw StateError('Missed ping');
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Socket implements SSHSocket {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('isolated missed probes recover; repeated misses disconnect', () async {
    final session = SshSession(manageBackgroundKeepAlive: false);
    final client = Client();
    session.attach(client: client, socket: Socket(), deviceId: 'pc');
    client.fail = true;
    expect(await session.healthCheck(), true);
    expect(await session.healthCheck(), true);
    client.fail = false;
    expect(await session.healthCheck(), true);
    client.fail = true;
    expect(await session.healthCheck(), true);
    expect(await session.healthCheck(), true);
    expect(await session.healthCheck(), false);
    session.dispose();
  });
  test('old transport closure cannot disconnect its replacement', () async {
    final session = SshSession(manageBackgroundKeepAlive: false);
    final old = Client();
    session.attach(client: old, socket: Socket(), deviceId: 'pc');
    final next = Client();
    session.attach(client: next, socket: Socket(), deviceId: 'pc');
    await Future<void>.delayed(Duration.zero);
    expect(session.isConnected, true);
    await next.close();
    await Future<void>.delayed(Duration.zero);
    expect(session.isConnected, false);
    session.dispose();
  });
}
