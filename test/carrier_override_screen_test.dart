import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

import 'fixtures/customization_report.dart';

void main() {
  testWidgets(
    'the carrier page refreshes compatibility and asks before enabling',
    (tester) async {
      final carrier = <String, dynamic>{
        'installed': true,
        'moduleState': 'disabled',
        'databaseCompatible': false,
      };
      final report = healthyCustomizationReport()..['carrier'] = carrier;
      var rootProbes = 0;
      var enableCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(LocalCustomization.channel, (
        call,
      ) async {
        if (call.method == 'probe' &&
            (call.arguments as Map?)?['requestRoot'] == true) {
          rootProbes++;
        }
        if (call.method == 'enableCarrier') {
          enableCalls++;
          carrier['rebootRequired'] = true;
        }
        return jsonEncode(report);
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          LocalCustomization.channel,
          null,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: LocalCustomizationScreen()),
      );
      await tester.pumpAndSettle();
      final entry = find.text('Carrier profile override');
      await tester.scrollUntilVisible(entry, 300);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(rootProbes, 1);
      expect(find.text('Installed · disabled'), findsOneWidget);

      final enable = find.widgetWithText(FilledButton, 'Enable override');
      await tester.ensureVisible(enable);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(enable).onPressed, isNull);
      carrier['databaseCompatible'] = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(rootProbes, 2);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(find.text('Enable carrier override?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(enableCalls, 0);

      await tester.tap(enable);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enable'));
      await tester.pumpAndSettle();
      expect(enableCalls, 1);
      expect(find.text('Change waiting for reboot'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
