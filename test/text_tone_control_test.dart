import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/text_tone_control.dart';

void main() {
  testWidgets(
    'manual tone has endpoints, intermediate live writes and default restore',
    (tester) async {
      int value = -1;
      final calls = <List<Object>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => TextToneControl(
                value: value,
                onChanged: (v, t) {
                  calls.add([v, t]);
                  set(() => value = v);
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.text('Custom text colour'));
      await tester.pump();
      expect(value, 0);
      await tester.tap(find.text('White'));
      await tester.pump();
      expect(value, 100);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(50);
      await tester.pump();
      expect(value, 50);
      expect(calls.last, [50, true]);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(50);
      expect(calls.last, [50, false]);
      await tester.tap(find.text('Black'));
      await tester.pump();
      expect(value, 0);
      await tester.tap(find.text('Custom text colour'));
      await tester.pump();
      expect(value, -1);
      expect(find.byType(Slider), findsNothing);
    },
  );
}
