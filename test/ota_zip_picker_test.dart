import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/ota_preparation_screen.dart';
import 'package:remote_control/ssh/ssh_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends SshSession {
  _Session() : super(manageBackgroundKeepAlive: false);

  final visited = <String>[];
  final stalled = Completer<Uint8List>();

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
    expect(command, 'python3 -');
    final match = RegExp(r'sys\.argv = \[str\(path\), "([^"]+)"\]')
        .firstMatch(utf8.decode(input!));
    final request = jsonDecode(utf8.decode(base64Decode(match![1]!))) as Map;
    if (request['action'] == 'list') return _reply({'jobs': []});
    expect(request['action'], 'browse');
    final path = request['path'] as String;
    visited.add(path);
    if (visited.length == 1) return stalled.future;
    return _reply({
      'path': path,
      'entries': path == '/C:/OTAs'
          ? [
              {'name': 'November', 'directory': true},
            ]
          : [
              {'name': 'frankel.ZIP', 'directory': false, 'bytes': 1024},
            ],
    });
  }

  Uint8List _reply(Map<String, dynamic> result) => Uint8List.fromList(
    utf8.encode(
      '__WIREHELM_DOWNLOAD__${jsonEncode({'ok': true, 'result': result})}',
    ),
  );
}

void main() {
  testWidgets('retry a stalled OTA folder and select a remote ZIP', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LocalCustomization.channel, (
      call,
    ) async {
      expect(call.method, 'otaDevice');
      return '{"device":"frankel","kernelSuVersion":"v3.3.1"}';
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalCustomization.channel, null),
    );
    final session = _Session();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OtaPreparationScreen(
          device: const Device(
            id: 'desktop',
            name: 'Desktop',
            host: 'localhost',
            port: 22,
            username: 'test',
            shellStyle: 'unix',
            commands: [],
          ),
          session: session,
          inputPath: '/C:/OTAs/old.zip',
          sourceSha256: 'a' * 64,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose OTA ZIP'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('The computer did not respond'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Choose ZIP file'), findsOneWidget);
    await tester.tap(find.text('November'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('frankel.ZIP'));
    await tester.pumpAndSettle();

    expect(session.visited, ['/C:/OTAs', '/C:/OTAs', '/C:/OTAs/November']);
    expect(find.text('/C:/OTAs/November/frankel.ZIP'), findsOneWidget);
    expect(find.text('a' * 64), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
