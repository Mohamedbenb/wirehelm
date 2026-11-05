import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/remote_keyboard_screen.dart';
import 'package:remote_control/ssh/ssh_session.dart';

const _device = Device(
  id: 'pc',
  name: 'Desktop',
  host: 'host',
  port: 22,
  username: 'user',
  shellStyle: 'windows',
  commands: [],
);

class _Session extends SshSession {
  final commands = <String>[];
  Completer<Uint8List>? pending;

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
    commands.add(command);
    if (pending != null) return pending!.future;
    return Uint8List.fromList(utf8.encode('Keys sent'));
  }
}

void main() {
  testWidgets('acknowledgement leaves a newly typed draft intact', (
    tester,
  ) async {
    final session = _Session()..pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteKeyboardScreen(device: _device, session: session),
      ),
    );
    await tester.enterText(find.byType(TextField), 'First draft');
    await tester.pump();
    await tester.tap(find.text('Send text'));
    await tester.pump();
    expect(session.commands, hasLength(1));
    await tester.enterText(find.byType(TextField), 'Next draft');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send text'))
          .onPressed,
      isNull,
    );
    session.pending!.complete(Uint8List.fromList(utf8.encode('Keys sent')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Next draft',
    );
    expect(find.text('Text sent.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'keyboard pads and composer remain usable with the phone keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _Session();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 26),
              viewPadding: const EdgeInsets.only(bottom: 26),
              viewInsets: const EdgeInsets.only(bottom: 260),
            ),
            child: child!,
          ),
          home: RemoteKeyboardScreen(device: _device, session: session),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Draft only');
      // ListView may dispose the off-screen composer while shortcuts are visible.
      final draftController = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await tester.pumpAndSettle();
      expect(session.commands, isEmpty);
      await tester.ensureVisible(find.text('Send text'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(find.widgetWithText(FilledButton, 'Send text'))
            .dy,
        lessThanOrEqualTo(380),
      );
      await tester.ensureVisible(find.text('Shortcuts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shortcuts'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Switch app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch app'));
      await tester.pumpAndSettle();
      expect(session.commands, hasLength(1));
      expect(draftController.text, 'Draft only');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'restoring sent text protects a new draft and help is available',
    (tester) async {
      final session = _Session();
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteKeyboardScreen(device: _device, session: session),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Original');
      await tester.pump();
      await tester.tap(find.text('Send text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New draft');
      await tester.tap(find.text('Restore last sent text'));
      await tester.pumpAndSettle();
      expect(find.text('Replace this draft?'), findsOneWidget);
      await tester.tap(find.text('Keep draft'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'New draft',
      );
      await tester.tap(find.byTooltip('Keyboard help'));
      await tester.pumpAndSettle();
      expect(find.text('Using the remote keyboard'), findsOneWidget);
      expect(
        find.textContaining('Wayland is not supported yet'),
        findsOneWidget,
      );
      expect(session.commands, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
