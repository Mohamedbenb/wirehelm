import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/terminal_screen.dart';
import 'package:remote_control/ssh/persistent_terminal.dart';
import 'package:remote_control/ssh/ssh_session.dart';

import 'persistent_terminal_test.dart' show Shell;

class TerminalSession extends SshSession {
  final PersistentTerminal persistent;
  TerminalSession(this.persistent) : super(manageBackgroundKeepAlive: false);
  @override
  bool get isConnected => true;
  @override
  String? get deviceId => 'pc';
  @override
  PersistentTerminal terminalFor({required bool isWindows}) => persistent;
}

const device = Device(
  id: 'pc',
  name: 'Desktop',
  host: 'host',
  port: 22,
  username: 'test',
  shellStyle: 'windows',
  commands: [],
);

void main() {
  testWidgets(
    'toolbar fits navigation and keyboard insets; modifiers encode once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shell = Shell();
      final persistent = PersistentTerminal(
        isWindows: false,
        openShell: () async => shell,
      );
      await tester.runAsync(() => persistent.start());
      final session = TerminalSession(persistent);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              padding: EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: TerminalScreen(device: device, session: session),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.deleteDetection, true);
      expect(view.readOnly, false);
      await tester.tap(find.text('ALT'));
      await tester.tap(find.text('TAB'));
      final reference = Terminal();
      String? expected;
      reference.onOutput = (value) => expected = value;
      reference.keyInput(TerminalKey.tab, alt: true);
      expect(utf8.decode(shell.writes.last), expected);
      expect(
        tester.getBottomLeft(find.text('PGDN')).dy,
        lessThan(800 - 300 - 34),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('terminal-extra-keys')))
            .height,
        72,
      );
      for (final key in [
        'ESC',
        'TAB',
        'CTRL',
        'ALT',
        '↑',
        '↓',
        '←',
        '→',
        'HOME',
        'END',
        'PGUP',
        'PGDN',
      ]) {
        final bounds = tester.getRect(find.text(key));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(360));
      }
      expect(find.byTooltip('Show/hide keyboard'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => persistent.dispose());
      session.dispose();
    },
  );
}
