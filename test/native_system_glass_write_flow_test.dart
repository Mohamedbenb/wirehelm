import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

void main() {
  testWidgets(
    'legacy glass settings do not expose glass controls or hide the edge panel',
    (tester) async {
      final config = <String, dynamic>{
        'systemGlassStyle': '{"nativeNotifications":{"enabled":true}}',
        'enabled': false,
        'edgePanelEnabled': true,
        'edgePanelSide': 'right',
        'edgePanelPosition': 28,
      };
      final data = <String, dynamic>{
        'device': 'Pixel 10',
        'config': config,
        'savedSetups': <dynamic>[],
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, (_) async => jsonEncode(data));
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LocalCustomization.channel, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: LocalCustomizationScreen()),
      );
      await tester.pumpAndSettle();
      for (final title in [
        'Liquid Glass Card',
        'Glass drawer studio',
        'Floating glass test',
        'SystemUI Laboratory',
      ]) {
        expect(find.text(title), findsNothing);
      }
      final link = find.text('Edge panel');
      await tester.scrollUntilVisible(link, 250);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('Enable edge panel'), findsOneWidget);
      expect(find.text('System glass'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
