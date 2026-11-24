import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/edge_controls.dart';
import 'package:remote_control/ssh/ssh_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client implements SSHClient {
  final closed = Completer<void>();

  @override
  bool get isClosed => closed.isCompleted;

  @override
  Future<void> get done => closed.future;

  @override
  Future<void> close() async {
    if (!closed.isCompleted) closed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements SSHSocket {
  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const shared = MethodChannel('remote_control/shared_edge_controls');
  const codec = StandardMethodCodec();
  late List<MethodCall> callbacks;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    callbacks = [];
    SharedPreferences.setMockInitialValues({
      'devices': jsonEncode([
        {
          'id': 'pc',
          'name': 'CachyOS PC',
          'host': 'desktop.example',
          'port': 22,
          'username': 'owner',
          'shellStyle': 'linux',
          'desktopProfile': 'cachyos',
        },
      ]),
      'ssh_known_hosts': jsonEncode([
        {
          'host': 'desktop.example',
          'port': 22,
          'keyType': 'ssh-ed25519',
          'fingerprint': String.fromCharCodes([1, 2, 3]),
        },
      ]),
    });
    messenger.setMockMethodCallHandler(shared, (call) async {
      callbacks.add(call);
      if (call.method == 'canRun') return true;
      return null;
    });
    attachSharedEdgeControls();
  });

  tearDown(() {
    sshSessions.remove('pc');
    shared.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(shared, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<Object?> call(String method, [String id = 'pc']) async {
    final response = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      shared.name,
      codec.encodeMethodCall(
        MethodCall(method, {
          'device': id,
          'owner': 'panel',
          'request': 'request',
        }),
      ),
      response.complete,
    );
    return codec.decodeEnvelope((await response.future)!);
  }

  _Client connect({
    String key = 'ssh-ed25519:AQID',
    String endpoint = 'desktop.example:22',
    String user = 'owner',
  }) {
    final client = _Client();
    sshSessions
        .sessionFor('pc')
        .attach(
          client: client,
          socket: _Socket(),
          deviceId: 'pc',
          hostKeyIdentity: key,
          configuredEndpoint: endpoint,
          authenticatedUsername: user,
        );
    return client;
  }

  test(
    'borrows the selected connection and leaves it open on panel exit',
    () async {
      final client = connect();
      expect(await call('pcRead'), {'deviceName': 'CachyOS PC', 'ready': true});
      expect(callbacks.last.method, 'canRun');
      expect(callbacks.last.arguments, 'request');
      expect(await call('closeOwner'), isNull);
      expect(client.isClosed, isFalse);
      expect(sshSessions.isConnected('pc'), isTrue);
    },
  );

  test('asks for a fallback if the selected device has no session', () async {
    connect();
    expect(await call('keyboardRead', 'different-pc'), {'noSession': true});
    expect(await call('pcRead'), containsPair('ready', true));
    sshSessions.disconnect('pc');
    expect(await call('pcRead'), {'noSession': true});
  });

  test('does not borrow an endpoint, account, or host key mismatch', () async {
    connect(endpoint: 'desktop.example:2222');
    expect(await call('pcRead'), {'noSession': true});
    connect(user: 'different');
    expect(await call('pcRead'), {'noSession': true});
    connect(key: 'ssh-ed25519:BAUG');
    expect(await call('pcRead'), {'noSession': true});
    expect(callbacks.map((call) => call.method), ['ready']);
  });
}
