import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remote_control/services/app_update.dart';
import 'package:remote_control/widgets/app_update_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'known update survives offline navigation and clears after installation',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'apk_update_source': 'pc',
        'apk_update_manifest_pc:${AppUpdate.defaultWindowsPath}':
            '{"version":"1.1.1","build":23}',
      });
      var installed = 22;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AppUpdate.channel,
        (call) async => {'version': '1.1.0', 'build': installed},
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AppUpdate.channel,
          null,
        ),
      );
      Widget page() =>
          const MaterialApp(home: Scaffold(body: AppUpdateBanner()));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1.1.1 (build 23) is available'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1.1.1 (build 23) is available'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      installed = 23;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
