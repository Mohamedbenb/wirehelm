import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/plasma_display_screen.dart';
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
  double scale = 1.25;

  @override
  Future<Map<String, dynamic>> run(Map<String, Object?> request) async {
    requests.add(request);
    final action = request['action'];
    if (action == 'apply') scale = (request['scale'] as num).toDouble();
    if (action == 'restore') scale = 1.25;
    return {
      if (action == 'apply') ...{
        'restoreToken': 'test-token',
        'restoreMs': 15000,
      },
      'outputs': [
        {
          'id': 2,
          'name': 'HDMI-A-3',
          'enabled': true,
          'priority': 1,
          'scale': scale,
          'rotation': 1,
          'pos': {'x': 0, 'y': 0},
          'currentModeId': '28',
          'modes': [
            {
              'id': '28',
              'refreshRate': 60,
              'size': {'width': 1920, 'height': 1080},
            },
          ],
        },
      ],
    };
  }
}

void main() {
  Future<_Settings> applyScale(WidgetTester tester) async {
    final settings = _Settings();
    addTearDown(settings.session.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlasmaDisplayScreen(settings: settings)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('125%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('150%').hitTestable());
    await tester.pumpAndSettle();
    final apply = find.text('Apply display changes');
    await tester.scrollUntilVisible(apply, 180);
    await tester.pumpAndSettle();
    await tester.tap(apply.hitTestable());
    await tester.pumpAndSettle();
    expect(settings.scale, 1.5);
    expect(settings.requests.map((item) => item['action']), [
      'displays',
      'apply',
    ]);
    expect(find.byType(AlertDialog), findsNothing);
    return settings;
  }

  testWidgets(
    'applying is immediate and Restore returns the previous settings',
    (tester) async {
      final settings = await applyScale(tester);
      await tester.tap(find.text('Restore previous settings'));
      await tester.pumpAndSettle();
      expect(settings.requests.last, {
        'action': 'restore',
        'token': 'test-token',
      });
      expect(settings.scale, 1.25);
      expect(find.text('Restore previous settings'), findsNothing);
    },
  );

  testWidgets('restore disappears without making a request at expiry', (
    tester,
  ) async {
    final settings = await applyScale(tester);
    expect(find.text('Restore previous settings'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Restore previous settings'), findsNothing);
    expect(settings.requests.map((item) => item['action']), [
      'displays',
      'apply',
    ]);
    expect(settings.scale, 1.5);
  });
}
