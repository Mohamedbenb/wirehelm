import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/customization_health.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

import 'fixtures/customization_report.dart';

void main() {
  test('panel and indicator require every SystemUI capability', () {
    final required = healthyCustomizationReport()['capabilities'] as List;
    expect(hasSystemUiCapabilities(healthyCustomizationReport()), isTrue);
    expect(hasSystemUiCapabilities({}), isFalse);
    for (final missing in required) {
      final available = required.where((id) => id != missing).toList();
      expect(hasSystemUiCapabilities({'capabilities': available}), isFalse,
          reason: 'Missing $missing');
    }
  });

  test('an intentional user disable is not presented as a crash recovery', () {
    final data = healthyCustomizationReport();
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
    final data = healthyCustomizationReport();
    (data['hook']['metrics'] as Map)['visibilityReason'] = 'statusBarHidden';
    (data['hook']['metrics'] as Map)['visible'] = false;
    expect(indicatorStatus(data), 'Status bar hidden by Android');
    expect(customizationChecks(data).where((c) => c.attention), isEmpty);
  });
  test(
    'a live hook bridge keeps customization healthy without manager service',
    () {
      final data = healthyCustomizationReport();
      data['xposed'] = {'connected': false, 'scope': <String>[]};
      final framework = customizationChecks(data)
          .firstWhere((check) => check.title == 'Framework');
      expect(framework.attention, false);
      expect(framework.detail, contains('hook bridge active'));
    },
  );
  test('blocked loaded hook is detected without granting compatibility', () {
    final data = healthyCustomizationReport();
    data['supported'] = false;
    data['canEnable'] = false;
    data['capabilities'] = <String>[];
    data['xposed'] = {'connected': false};
    (data['hook'] as Map).addAll(<String, Object>{
      'fresh': false,
      'currentProcess': true,
      'state': 'unsupported',
      'error': 'Android/SystemUI build not validated',
    });
    final checks = customizationChecks(data);
    final framework = checks.firstWhere((c) => c.title == 'Framework');
    expect(framework.detail, contains('SystemUI module loaded'));
    expect(framework.attention, false);
    expect(
      checks.firstWhere((c) => c.title == 'Device compatibility').attention,
      true,
    );
    expect(data['canEnable'], false);
    (data['hook'] as Map)['currentProcess'] = false;
    expect(systemUiHookDetected(healthSection(data, 'hook')), false);
    expect(
      customizationChecks(data)
          .firstWhere((c) => c.title == 'Framework')
          .attention,
      true,
    );
  });
  testWidgets('setup separates module presence from blocked firmware', (
    tester,
  ) async {
    final data = healthyCustomizationReport();
    data['vector'] = {'installed': true};
    data['kernelsu'] = {'installed': true};
    data['supported'] = false;
    data['canEnable'] = false;
    data['capabilities'] = <String>[];
    data['xposed'] = {'connected': false};
    (data['hook'] as Map).addAll(<String, Object>{
      'fresh': false,
      'currentProcess': true,
      'state': 'unsupported',
    });
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
          calls.add(call.method);
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
    await tester.ensureVisible(find.text('Setup assistant'));
    await tester.tap(find.text('Setup assistant'));
    await tester.pumpAndSettle();
    expect(find.text('2. Enable Wirehelm'), findsOneWidget);
    expect(find.text('Module detected in SystemUI'), findsOneWidget);
    expect(find.text('System UI is included'), findsOneWidget);
    expect(find.text('Open Vector modules'), findsNothing);
    expect(
      find.textContaining('SystemUI features remain blocked'),
      findsOneWidget,
    );
    expect(calls.where((method) => method.startsWith('apply')), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'detects clipping, expired safety coverage and delayed visible samples',
    () {
      final data = healthyCustomizationReport();
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
  test(
    'distinguishes carrier installation, database and active mount health',
    () {
      final data = healthyCustomizationReport();
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
    },
  );
  test('disabled portable backend waits for generation without a false database alarm', () {
    final data = healthyCustomizationReport();
    data['carrier'] = <String, dynamic>{
      'installed': true,
      'moduleState': 'disabled',
      'moduleVersion': '3.0.0',
      'configurationValid': false,
      'databaseCompatible': true,
    };
    final check = customizationChecks(data)
        .firstWhere((c) => c.title == 'Carrier database');
    expect(check.attention, false);
    expect(check.detail, contains('generates when enabled'));
    expect(
      customizationChecks(data).where((c) => c.title == 'Carrier override'),
      isEmpty,
    );
  });
  test('portable backend rejects an incompatible vendor database', () {
    final data = healthyCustomizationReport();
    data['carrier'] = <String, dynamic>{
      'installed': true,
      'moduleState': 'enabled',
      'configurationValid': false,
      'databaseCompatible': false,
      'active': false,
    };
    expect(
      customizationChecks(data)
          .firstWhere((c) => c.title == 'Carrier database')
          .attention,
      true,
    );
    expect(
      customizationChecks(data)
          .firstWhere((c) => c.title == 'Carrier override')
          .attention,
      true,
    );
  });
}
