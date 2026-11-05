import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/main.dart';

void main() {
  testWidgets(
    'App starts',
    (tester) async {
      await tester.pumpWidget(
        const RemoteControlApp(),
      );

      expect(
        find.text('Remote Control'),
        findsNothing,
      );
    },
  );
}