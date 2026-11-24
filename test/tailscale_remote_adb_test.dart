import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/tailscale_screen.dart';
import 'package:remote_control/transport/tsnet_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const previousPc = '100.64.0.10';
  const activePc = '100.64.0.11';
  late Map<String, Object?> relay;
  late List<String> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    relay = {'enabled': false, 'preferredPC': previousPc};
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TsnetClient.channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'status':
              return jsonEncode({
                'state': 'Running',
                'ips': ['100.64.0.20'],
              });
            case 'debugStatus':
              return jsonEncode(relay);
            case 'stopDebugRelay':
              relay = {'enabled': false, 'preferredPC': activePc};
              return null;
            case 'peers':
              return jsonEncode([
                {
                  'os': 'windows',
                  'online': true,
                  'ips': ['100.64.0.25'],
                },
              ]);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TsnetClient.channel, null);
  });

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(540, 1460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: TailscaleScreen(key: UniqueKey())),
    );
    await tester.pumpAndSettle();
  }

  TextField pcField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets(
    'prefills saved PC without starting a session or overriding a draft',
    (tester) async {
      await openScreen(tester);
      expect(pcField(tester).controller!.text, previousPc);
      expect(pcField(tester).enabled, isTrue);
      expect(find.text('Start remote ADB'), findsOneWidget);
      expect(calls, isNot(contains('startDebugRelay')));

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Refresh Tailscale status'));
      await tester.pumpAndSettle();

      expect(pcField(tester).controller!.text, isEmpty);
      expect(calls, isNot(contains('peers')));
      expect(calls, isNot(contains('startDebugRelay')));
      await tester.pumpWidget(const SizedBox.shrink());
      await TsnetClient.instance.stop();
    },
  );

  testWidgets(
    'shows the active PC and prefills it after stopping and reopening',
    (tester) async {
      relay = {
        'enabled': true,
        'allowedPC': activePc,
        'preferredPC': previousPc,
      };
      await openScreen(tester);
      expect(pcField(tester).controller!.text, activePc);
      expect(pcField(tester).enabled, isFalse);

      await tester.tap(find.text('Stop / restore'));
      await tester.pumpAndSettle();
      expect(pcField(tester).controller!.text, activePc);
      expect(pcField(tester).enabled, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await openScreen(tester);
      expect(pcField(tester).controller!.text, activePc);
      expect(find.text('Start remote ADB'), findsOneWidget);
      expect(calls, isNot(contains('startDebugRelay')));
      await tester.pumpWidget(const SizedBox.shrink());
      await TsnetClient.instance.stop();
    },
  );
}
