import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

void main() {
  testWidgets(
    'named saves and restores use saved setup IDs, not legacy rollback',
    (tester) async {
      final calls = <MethodCall>[];
      final data = <String, dynamic>{
        'device': 'Pixel 10',
        'config': <String, dynamic>{},
        'savedSetups': <dynamic>[],
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
            calls.add(call);
            if (call.method == 'saveSetup')
              data['savedSetups'] = [
                {
                  'id': 'known-id',
                  'name': (call.arguments as Map)['name'],
                  'at': 1792800000000,
                },
              ];
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
      await tester.tap(find.text('Save setup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Known good');
      await tester.pump();
      await tester.tap(find.text('Save new setup'));
      await tester.pumpAndSettle();
      expect(
        (calls.firstWhere((c) => c.method == 'saveSetup').arguments
            as Map)['name'],
        'Known good',
      );
      await tester.tap(find.text('Restore setup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Known good'));
      await tester.tap(find.text('Restore selected setup'));
      await tester.pumpAndSettle();
      expect(
        (calls.firstWhere((c) => c.method == 'restoreSetup').arguments
            as Map)['id'],
        'known-id',
      );
      expect(calls.any((c) => c.method == 'rollback'), false);
      await Scrollable.ensureVisible(
        tester.element(find.text('Network speed')),
        alignment: .2,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Update only network indicator'),
        findsOneWidget,
      );
      await tester.tap(find.text('Update selected setup'));
      await tester.pumpAndSettle();
      final update =
          calls.firstWhere((c) => c.method == 'updateSetup').arguments as Map;
      expect(update['id'], 'known-id');
      expect(update['scope'], 'network');
      await tester.tap(find.byTooltip('Restore feature settings'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Restore only network indicator'),
        findsOneWidget,
      );
      await tester.tap(find.text('Restore network indicator'));
      await tester.pumpAndSettle();
      final restores = calls.where((c) => c.method == 'restoreSetup').toList();
      expect((restores.first.arguments as Map)['scope'], 'all');
      expect((restores.last.arguments as Map)['scope'], 'network');
      expect((restores.last.arguments as Map)['id'], 'known-id');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
