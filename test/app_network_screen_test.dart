import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/app_network_screen.dart';

void main() {
  testWidgets('shows the block only after native readback', (tester) async {
    const channel = MethodChannel('remote_control/app_network');
    final reply = Completer<List<Map<String, Object>>>();
    List<Map<String, Object>> rows(bool blocked) => [
      {
        'name': 'com.example.sample',
        'label': 'Sample',
        'saved': blocked,
        'blocked': blocked,
        'external': false,
      },
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'list') return rows(false);
      expect(call.method, 'setBlocked');
      expect(call.arguments, {
        'package': 'com.example.sample',
        'blocked': true,
      });
      return reply.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: AppNetworkScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No Wirehelm block'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.textContaining('Status unverified'), findsOneWidget);
    expect(find.textContaining('Network blocked'), findsNothing);
    reply.complete(rows(true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network blocked'), findsOneWidget);
  });

  testWidgets('allows a timed exception and restores the block on demand', (
    tester,
  ) async {
    const channel = MethodChannel('remote_control/app_network');
    const package = 'com.example.sample';
    List<Map<String, Object>> rows({int seconds = 0}) => [
      {
        'name': package,
        'label': 'Sample',
        'saved': true,
        'blocked': seconds == 0,
        'external': false,
        'canSchedule': true,
        'temporarySeconds': seconds,
      },
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'list') return rows();
      if (call.method == 'allowTemporarily') {
        expect(call.arguments, {'package': package});
        return rows(seconds: 300);
      }
      expect(call.method, 'setBlocked');
      expect(call.arguments, {'package': package, 'blocked': true});
      return rows();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: AppNetworkScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow for 5 minutes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporarily allowed · 5:00'), findsOneWidget);
    await tester.tap(find.text('Block now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network blocked'), findsOneWidget);
    expect(find.text('Block now'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
