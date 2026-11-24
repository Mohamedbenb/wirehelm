import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/local_customization_screen.dart';

void main() {
  testWidgets('sets and clears a foreground app rule independently', (
    tester,
  ) async {
    const browser = 'com.example.browser';
    const notes = 'com.example.notes';
    const wirehelm = 'com.example.remote_control';
    const defaults = 'com.example.favorites';
    var config = <String, dynamic>{
      'edgePanelEnabled': true,
      'edgePanelApps': defaults,
      'edgePanelAppRules': jsonEncode({browser: browser}),
    };
    final writes = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(LocalCustomization.channel, (
      call,
    ) async {
      if (call.method == 'launcherApps') {
        expect(call.arguments, {'includeSelf': true, 'edgeShortcuts': true});
        return jsonEncode({
          'apps': [
            {'package': browser, 'label': 'Browser'},
            {'package': notes, 'label': 'Notes'},
            {'package': wirehelm, 'label': 'Wirehelm'},
          ],
        });
      }
      if (call.method == 'applyVisual') {
        config = jsonDecode(
          (call.arguments as Map)['config'] as String,
        ) as Map<String, dynamic>;
        writes.add(config);
      }
      return jsonEncode({'device': 'Pixel 10', 'config': config});
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalCustomization.channel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(home: LocalCustomizationScreen()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('UI features'), 250);
    await tester.tap(find.text('UI features'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edge panel'));
    await tester.pumpAndSettle();
    final rules = find.text('App-specific shortcuts');
    await tester.ensureVisible(rules);
    await tester.tap(rules);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser'));
    await tester.pumpAndSettle();
    expect(find.text('Shortcuts for Browser'), findsOneWidget);
    expect(find.text('Browser'), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Shortcuts on this panel'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Notes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wirehelm');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Wirehelm'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Wirehelm'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(jsonDecode(writes.single['edgePanelAppRules'] as String), {
      browser: '$notes,$wirehelm',
    });
    expect(writes.single['edgePanelApps'], defaults);

    await tester.tap(rules);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Notes'), findsOneWidget);
    await tester.tap(find.text('Use Favorites'));
    await tester.pumpAndSettle();
    expect(writes.last['edgePanelAppRules'], '{}');
    expect(writes.last['edgePanelApps'], defaults);
    await tester.pumpWidget(const SizedBox());
  });
}
