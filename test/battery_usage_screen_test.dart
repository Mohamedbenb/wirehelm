import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/battery_usage_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var enabled = false;
  var withSession = false;
  final calls = <String>[];
  setUp(() {
    enabled = false;
    withSession = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'batteryUsageConfigure') {
            enabled = (call.arguments as Map)['enabled'] == true;
          }
          return '{"enabled":$enabled,"running":$enabled,"estimates":false,"rootApproved":true,"selected":${withSession ? 1 : 0},"samples":[],"sessions":${withSession ? '[{"id":1,"start":1794550000000,"startLevel":90,"lastLevel":88,"durationMs":7200000,"screenOnMs":3600000,"screenOffMs":3600000,"lostPercent":2,"lostMah":100.0,"mahPerHour":50.0,"active":true,"features":{"Notification ring":120000},"configuration":{"Notification ring":"On"},"configurations":[]}]' : '[]'}}';
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, null),
  );
  testWidgets('explains unplug boundaries and enables native tracking', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: BatteryUsageScreen()));
    await t.pumpAndSettle();
    expect(find.text('Track battery sessions'), findsOneWidget);
    expect(find.textContaining('Starts on unplug'), findsOneWidget);
    await t.tap(find.byType(SwitchListTile).first);
    await t.pumpAndSettle();
    expect(enabled, true);
    expect(calls, contains('batteryUsageConfigure'));
    expect(t.takeException(), isNull);
  });
  testWidgets('shows session drain without assigning feature mAh', (t) async {
    withSession = true;
    await t.pumpWidget(const MaterialApp(home: BatteryUsageScreen()));
    await t.pumpAndSettle();
    expect(find.text('100.0 mAh'), findsOneWidget);
    expect(find.text('50.0 mAh/h'), findsOneWidget);
    await t.drag(find.byType(ListView), const Offset(0, -650));
    await t.pumpAndSettle();
    expect(find.text('Customization activity'), findsOneWidget);
    expect(find.text('Notification ring'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('read failure keeps the page usable', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          LocalCustomization.channel,
          (_) async =>
              throw PlatformException(code: 'FAILED', message: 'Not available'),
        );
    await t.pumpWidget(const MaterialApp(home: BatteryUsageScreen()));
    await t.pumpAndSettle();
    expect(find.textContaining('Not available'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });
}
