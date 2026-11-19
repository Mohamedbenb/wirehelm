import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/carrier_selection_dialog.dart';

void main() {
  testWidgets('search preserves selections and ignores stale results', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    final fresh = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: CarrierSelectionDialog(
          selected: {'60502'},
          load: (query) => query.isEmpty ? old.future : fresh.future,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'orange');
    await tester.pump(const Duration(milliseconds: 310));
    fresh.complete({
      'items': [
        {'mccmnc': '60501', 'name': 'Orange'},
      ],
      'selected': [
        {'mccmnc': '60502', 'name': 'Telecom'},
      ],
    });
    await tester.pump();
    old.complete({
      'items': [
        {'mccmnc': '11111', 'name': 'Stale'},
      ],
    });
    await tester.pump();
    expect(find.text('Stale'), findsNothing);
    expect(find.text('Telecom (60502)'), findsOneWidget);
    expect(find.text('Orange'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(find.textContaining('2/32 selected'), findsOneWidget);
  });
  testWidgets('empty selection cannot be saved', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CarrierSelectionDialog(
          selected: {},
          load: (_) async => {'items': []},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
