import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/plasma_text_size_screen.dart';
import 'package:remote_control/services/plasma_settings.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _Settings extends PlasmaSettings {
  _Settings()
    : super(
        const Device(
          id: 'desktop',
          name: 'PC',
          host: 'localhost',
          port: 22,
          username: 'user',
          shellStyle: 'linux',
          desktopProfile: 'cachyos',
          commands: [],
        ),
        SshSession(manageBackgroundKeepAlive: false),
      );

  final requests = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> run(Map<String, Object?> request) async {
    requests.add(request);
    return {
      'family': 'Noto Sans',
      'size': 14,
      'sizesMatch': request.containsKey('size'),
    };
  }
}

void main() {
  testWidgets(
    'Apply updates mixed font roles at the current General font size',
    (tester) async {
      final settings = _Settings();
      addTearDown(settings.session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: PlasmaTextSizeScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Apply text size');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(settings.requests, [
        {'action': 'text'},
        {'action': 'text', 'size': 14.0},
      ]);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    },
  );
}
