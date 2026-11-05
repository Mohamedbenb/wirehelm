import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/customization_health.dart';
import 'package:remote_control/customization/network_indicator_preview.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

import 'dart:convert';

Map<String, dynamic> healthy() => {
  'device': 'Pixel 10',
  'android': '17',
  'sdk': 37,
  'supported': true,
  'canEnable': true,
  'safetyLeaseRemainingMs': 85000,
  'capabilities': [
    'device.validatedSystemUi',
    'xposed.remoteConfiguration',
    'xposed.systemuiHook',
    'root.recoveryWatchdog',
  ],
  'config': {
    'enabled': true,
    'revision': 4,
    'hideIdle': false,
    'showUpload': true,
    'showArrows': false,
    'layout': 'stacked',
    'units': 'bytes',
    'decimals': 1,
    'textSize': 12,
    'intervalMs': 1000,
  },
  'hook': {
    'fresh': true,
    'state': 'active',
    'version': '2',
    'pid': 42,
    'revision': 4,
    'ageMs': 500,
    'metrics': {
      'attached': true,
      'visible': true,
      'visibilityReason': 'showing',
      'sampleAgeMs': 20,
    },
  },
  'root': {
    'authorized': true,
    'moduleState': 'healthy',
    'systemUiRestarts': '0',
    'watchdogAgeSeconds': 2,
  },
  'xposed': {
    'connected': true,
    'name': 'Vector',
    'api': 102,
    'scope': ['com.android.systemui'],
  },
};

void main() {
  test('an intentional user disable is not presented as a crash recovery', () {
    final data = healthy();
    (data['config'] as Map).addAll(<String, Object>{
      'enabled': false,
      'emergencyDisabled': true,
      'recoveryReason': 'Disabled by user',
    });
    (data['root'] as Map)['quarantined'] = 'true';
    expect(indicatorStatus(data), 'Off');
    expect(customizationChecks(data).where((c) => c.attention), isEmpty);
  });
  test('normal fullscreen hiding is explained without raising a failure', () {
    final data = healthy();
    (data['hook']['metrics'] as Map)['visibilityReason'] = 'statusBarHidden';
    (data['hook']['metrics'] as Map)['visible'] = false;
    expect(indicatorStatus(data), 'Status bar hidden by Android');
    expect(customizationChecks(data).where((c) => c.attention), isEmpty);
  });
  test('a live hook bridge keeps customization healthy without manager service', () {
    final data = healthy();
    data['xposed'] = {
      'connected': false,
      'scope': <String>[],
    };
    final framework = customizationChecks(data).firstWhere(
      (check) => check.title == 'Framework',
    );
    expect(framework.attention, false);
    expect(framework.detail, contains('hook bridge active'));
  });
  test(
    'detects clipping, expired safety coverage and delayed visible samples',
    () {
      final data = healthy();
      data['safetyLeaseRemainingMs'] = 0;
      (data['hook']['metrics'] as Map).addAll(<String, Object>{
        'textClipped': true,
        'sampleAgeMs': 6000,
      });
      final issues = customizationChecks(data)
          .where((c) => c.attention)
          .map((c) => c.title);
      expect(
        issues,
        containsAll(['Text layout', 'Safety lease', 'Traffic sampling']),
      );
    },
  );
  test('distinguishes carrier installation, database and active mount health', () {
    final data = healthy();
    data['carrier'] = {
      'installed': true,
      'moduleState': 'enabled',
      'moduleVersion': '2.0.0',
      'configurationValid': true,
      'active': false,
      'rebootRequired': false,
      'supportedCarrierDetected': true,
    };
    final issues = customizationChecks(data)
        .where((c) => c.attention)
        .map((c) => c.title);
    expect(issues, contains('Carrier override'));
    expect(issues, isNot(contains('Carrier database')));
  });
  testWidgets('preview removes upload and stays usable at narrow widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final config = Map<String, dynamic>.from(healthy()['config']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: NetworkIndicatorPreview(config: config),
          ),
        ),
      ),
    );
    expect(find.text('3.2'), findsOneWidget);
    config['showUpload'] = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: NetworkIndicatorPreview(config: config),
          ),
        ),
      ),
    );
    expect(find.text('3.2'), findsNothing);
    expect(find.text('24.8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'upload toggle preserves idle preference and health opens as a dedicated screen',
    (tester) async {
      final data = healthy();
      Map<String, dynamic>? applied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, (
            MethodCall call,
          ) async {
            if (call.method == 'apply') {
              applied = Map<String, dynamic>.from(
                jsonDecode((call.arguments as Map)['config'] as String) as Map,
              );
              data['config'] = applied!;
            }
            return jsonEncode(data);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LocalCustomization.channel, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: LocalCustomizationScreen()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show upload speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show upload speed'));
      await tester.pumpAndSettle();
      expect(applied?['showUpload'], false);
      expect(applied?['hideIdle'], false);
      await tester.tap(find.byTooltip('Customization health'));
      await tester.pumpAndSettle();
      expect(find.text('Health checks'), findsOneWidget);
      expect(find.text('Checks passing'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
