import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/transport/tsnet_client.dart';
import 'package:remote_control/transport/tsnet_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/tsnet');
  late TsnetClient client;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;

  setUp(() {
    client = TsnetClient(methodChannel: channel);
    calls = [];
    handler = (call) async => switch (call.method) {
      'status' => jsonEncode({
        'state': 'Running',
        'authUrl': '',
        'ips': ['100.64.0.1'],
      }),
      'dial' => 1,
      'write' => (call.arguments['data'] as Uint8List).length,
      _ => null,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android defaults to tsnet; direct transport is an explicit persisted choice', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await client.useTsnet(), isTrue);
    await client.setUseTsnet(false);
    expect(await client.useTsnet(), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await client.useTsnet(), isFalse);
  });

  test(
    'first connection waits through transient startup without opening settings',
    () async {
      final original = handler;
      handler = (call) async {
        if (call.method == 'status') {
          return jsonEncode({'state': 'NeedsLogin', 'authUrl': ''});
        }
        return original(call);
      };
      expect(await client.dial('pc', 22), 1);
      expect(calls.map((c) => c.method), ['start', 'status', 'wait', 'dial']);
    },
  );

  test(
    'login requirement prevents dialing and preserves the login URL',
    () async {
      handler = (call) async => call.method == 'status'
          ? jsonEncode({
              'state': 'NeedsLogin',
              'authUrl': 'https://login.tailscale.com/a/example',
            })
          : null;
      await expectLater(
        client.dial('pc', 22),
        throwsA(
          isA<TsnetLoginRequired>().having(
            (error) => error.status.authUrl,
            'auth URL',
            'https://login.tailscale.com/a/example',
          ),
        ),
      );
      expect(calls.where((call) => call.method == 'dial'), isEmpty);
    },
  );

  test(
    'writes preserve byte order, split large payloads and flush before close',
    () async {
      final socket = await TsnetSocket.connect('pc', 22, client: client);
      final payload = Uint8List.fromList(
        List.generate(70000, (index) => index % 256),
      );
      socket.sink.add(payload);
      socket.sink.add([255, 0, 128]);
      await socket.close();
      final writes = calls.where((call) => call.method == 'write').toList();
      expect(
        writes.map((call) => (call.arguments['data'] as Uint8List).length),
        [65536, 4464, 3],
      );
      expect(
        writes.expand((call) => call.arguments['data'] as Uint8List).toList(),
        [...payload, 255, 0, 128],
      );
      expect(calls.last.method, 'close');
      expect(() => socket.sink.add([1]), throwsStateError);
    },
  );

  test(
    'read timeout retries, binary output reaches SSH, EOF closes the handle',
    () async {
      var reads = 0;
      final original = handler;
      handler = (call) async {
        if (call.method != 'read') return original(call);
        reads++;
        if (reads == 1) throw PlatformException(code: 'TSNET_READ_TIMEOUT');
        if (reads == 2) return Uint8List.fromList([0, 255, 128]);
        return Uint8List(0);
      };
      final socket = await TsnetSocket.connect('pc', 22, client: client);
      expect(await socket.stream.toList(), [
        Uint8List.fromList([0, 255, 128]),
      ]);
      await socket.done;
      expect(reads, 3);
      expect(calls.where((call) => call.method == 'close'), hasLength(1));
    },
  );

  test('destroy closes native handle even while a read is pending', () async {
    final read = Completer<Uint8List>();
    final started = Completer<void>();
    final original = handler;
    handler = (call) async {
      if (call.method == 'read') {
        started.complete();
        return read.future;
      }
      if (call.method == 'close') {
        read.complete(Uint8List(0));
        return null;
      }
      return original(call);
    };
    final socket = await TsnetSocket.connect('pc', 22, client: client);
    final subscription = socket.stream.listen((_) {});
    await started.future;
    socket.destroy();
    await socket.done;
    await subscription.cancel();
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
  });
}
