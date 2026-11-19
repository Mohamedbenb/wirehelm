import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/edge_actions_screen.dart';

void main() {
  testWidgets(
    'toolbar draft can enable clipboard without adding material fields',
    (t) async {
      String? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(c).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const EdgeActionsScreen(initialRaw: '{}'),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('Clipboard shelf'),
        matching: find.byType(ListTile),
      );
      await t.ensureVisible(tile);
      await t.tap(find.descendant(of: tile, matching: find.byType(Switch)));
      await t.tap(find.widgetWithText(TextButton, 'Save'));
      await t.pumpAndSettle();
      final value = jsonDecode(saved!) as Map;
      expect(value['hidden'], isNot(contains('clipboard')));
      expect(
        value.keys,
        unorderedEquals(['order', 'hidden', 'labels', 'iconSize', 'columns']),
      );
    },
  );
  testWidgets('back cancels an action draft', (t) async {
    String? saved;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(c).push<String>(
                MaterialPageRoute(
                  builder: (_) => const EdgeActionsScreen(initialRaw: '{}'),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(saved, isNull);
  });
  testWidgets('direct action editor loads and saves only toolbar options', (
    t,
  ) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
          if (call.method == 'saveEdgeActions') {
            saved = (call.arguments as Map)['raw'] as String;
          }
          return jsonEncode({'raw': saved ?? '{}'});
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, null),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute(builder: (_) => const EdgeActionsScreen()),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Save'));
    await t.pumpAndSettle();
    expect(
      jsonDecode(saved!).keys,
      unorderedEquals(['order', 'hidden', 'labels', 'iconSize', 'columns']),
    );
    expect(find.text('Open'), findsOneWidget);
  });
}
