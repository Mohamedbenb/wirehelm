import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/remote_keyboard_screen.dart';
import 'package:remote_control/screens/remote_media_screen.dart';
import 'package:remote_control/ssh/ssh_session.dart';

const device = Device(
  id: 'pc',
  name: 'PC',
  host: 'host',
  port: 22,
  username: 'user',
  shellStyle: 'windows',
  commands: [],
);

class Session extends SshSession {
  bool fail = false;
  @override
  bool get isConnected => true;
  @override
  String get deviceId => 'pc';
  @override
  Future<Uint8List> runCommand(
    String command, {
    String executionMode = 'standard',
    Duration? timeout,
  }) async {
    if (fail) throw StateError('Send failed');
    return Uint8List.fromList(utf8.encode('Keys sent'));
  }

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async => Uint8List.fromList(utf8.encode('ffmpeg is not recognized'));
}

void main() {
  testWidgets(
    'media controls stay above navigation inset while content scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
            ),
            child: child!,
          ),
          home: RemoteMediaScreen(device: device, session: session),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester.getBottomRight(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(position.dy, lessThanOrEqualTo(766));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.widgetWithText(FilledButton, 'Start')),
        position,
      );
      expect(find.textContaining('Select remote inputs'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
    },
  );
  testWidgets('successful text clears, restores, and failed text remains', (
    tester,
  ) async {
    final session = Session();
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteKeyboardScreen(device: device, session: session),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.text('Send text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.ensureVisible(find.text('Restore last sent text'));
    await tester.tap(find.text('Restore last sent text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello',
    );
    session.fail = true;
    await tester.tap(find.text('Send text'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello',
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('missing FFmpeg shows guidance instead of Off-only dropdowns', (
    tester,
  ) async {
    final session = Session();
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteMediaScreen(device: device, session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FFmpeg unavailable'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
    expect(find.byType(DropdownButtonFormField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
  });
}
