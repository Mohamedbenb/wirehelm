import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/saved_setup_sheet.dart';

void main() {
  testWidgets(
    'feature save selects an existing stable ID and explains its scope',
    (tester) async {
      SetupChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<SetupChoice>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => SavedSetupSheet(
                      scope: 'network',
                      setups: const [
                        {
                          'id': 'first',
                          'name': 'Everyday',
                          'at': 1792800000000,
                        },
                        {'id': 'second', 'name': 'Travel', 'at': 1792800000000},
                      ],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Network indicator'), findsOneWidget);
      expect(
        find.textContaining('Update only network indicator'),
        findsOneWidget,
      );
      await tester.tap(find.text('Travel'));
      await tester.tap(find.text('Update selected setup'));
      await tester.pumpAndSettle();
      expect(result?.id, 'second');
      expect(result?.name, isNull);
    },
  );

  testWidgets(
    'new setup sheet stays usable above the keyboard on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SavedSetupSheet(setups: [])),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Minimal');
      await tester.pump();
      expect(
        tester.getBottomLeft(find.text('Save new setup')).dy,
        lessThan(460),
      );
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
