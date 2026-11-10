import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/device_snapshot_screen.dart';

void main() {
  testWidgets('compares a saved baseline and skips unavailable sections', (
    tester,
  ) async {
    const channel = MethodChannel('remote_control/customization');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'deviceSnapshotBaseline':
          return '{}';
        case 'saveDeviceSnapshot':
          expect(call.arguments, {'includeModules': true});
          return jsonEncode({
            'capturedAt': 1000,
            'sections': {
              'Android': {'Build': 'old'},
              'Root modules': {'sample_module': 'Enabled'},
            },
            'unavailable': {},
          });
        case 'captureDeviceSnapshot':
          expect(call.arguments, {'includeModules': true});
          return jsonEncode({
            'capturedAt': 2000,
            'sections': {
              'Android': {'Build': 'new'},
            },
            'unavailable': {'Root modules': 'Module inventory unavailable.'},
          });
        default:
          fail('Unexpected method ${call.method}');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(home: DeviceSnapshotScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Include root modules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save snapshot'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Baseline saved'), findsOneWidget);
    await tester.tap(find.text('Compare now'));
    await tester.pumpAndSettle();
    expect(find.text('old → new'), findsOneWidget);
    expect(
      find.text('Current · Module inventory unavailable.'),
      findsOneWidget,
    );
    expect(find.text('sample_module'), findsNothing);
  });
}
