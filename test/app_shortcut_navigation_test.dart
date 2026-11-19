import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/app_shortcut_navigation.dart';

void main() {
  Widget app(AppShortcutNavigation n, {String initial = '/'}) => MaterialApp(
    navigatorKey: n.key,
    navigatorObservers: [n.observer],
    initialRoute: initial,
    home: const Scaffold(body: Text('Home destination')),
    routes: {
      clipboardShelfRoute: (_) =>
          const Scaffold(body: Text('Shelf destination')),
      edgeActionsRoute: (_) =>
          const Scaffold(body: Text('Actions destination')),
    },
  );
  testWidgets('cold shortcut route opens shelf with normal back navigation', (
    t,
  ) async {
    final n = AppShortcutNavigation();
    await t.pumpWidget(app(n, initial: clipboardShelfRoute));
    await t.pumpAndSettle();
    expect(find.text('Shelf destination'), findsOneWidget);
    n.key.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('Home destination'), findsOneWidget);
  });
  testWidgets(
    'warm shortcut reuses current shelf instead of stacking duplicates',
    (t) async {
      final n = AppShortcutNavigation();
      n.attach();
      addTearDown(n.detach);
      await t.pumpWidget(app(n));
      await t.pumpAndSettle();
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          const MethodCall('pushRoute', clipboardShelfRoute),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(
          const MethodCall('pushRoute', clipboardShelfRoute),
        ),
        (_) {},
      );
      await t.pumpAndSettle();
      n.key.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('Home destination'), findsOneWidget);
      expect(
        await n.didPushRouteInformation(
          RouteInformation(uri: Uri(path: '/unknown')),
        ),
        false,
      );
    },
  );
}
