import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/screens/clipboard_shelf_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<dynamic, dynamic>>[];
  var enabled = false;
  var screenshots = true;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('remote_control/clipboard_shelf_events'),
          (_) async => null,
        );
    calls.clear();
    enabled = false;
    screenshots = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
          final args = Map<dynamic, dynamic>.from(call.arguments as Map? ?? {});
          calls.add({...args, 'method': call.method});
          if (args['op'] == 'configure') {
            enabled = jsonDecode(args['config'] as String)['enabled'] == true;
            screenshots =
                jsonDecode(args['config'] as String)['screenshots'] != false;
          }
          return jsonEncode({
            'policy': {
              'enabled': enabled,
              'limit': 100,
              'days': 7,
              'images': true,
              'screenshots': screenshots,
              'excluded': [],
            },
            'observerAt': 1,
            'observerVersion': 195,
            'entries': [
              {
                'id': 1,
                'kind': 'text',
                'text': 'Sample shelf text',
                'source': 'com.example.app',
                'app': 'Example',
                'at': 1794560000000,
                'pinned': true,
              },
            ],
          });
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, null),
  );
  testWidgets('capture is explicit and saved clips can be copied', (t) async {
    await t.pumpWidget(const MaterialApp(home: ClipboardShelfScreen()));
    await t.pumpAndSettle();
    expect(find.text('Save copied items'), findsOneWidget);
    expect(enabled, false);
    await t.tap(find.byType(SwitchListTile).first);
    await t.pumpAndSettle();
    expect(enabled, true);
    await t.ensureVisible(find.text('Sample shelf text'));
    await t.tap(find.text('Sample shelf text'));
    await t.pumpAndSettle();
    expect(calls.any((c) => c['op'] == 'copy' && c['id'] == 1), true);
  });
  testWidgets(
    'search reaches native full-text lookup and clearing preserves pins by default',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: ClipboardShelfScreen()));
      await t.pumpAndSettle();
      final search = find.byType(TextField).first;
      await t.ensureVisible(search);
      await t.enterText(search, 'needle');
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(calls.last['query'], 'needle');
      await t.tap(find.byTooltip('Clear history'));
      await t.pumpAndSettle();
      expect(find.text('Include pinned clips'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await t.pumpAndSettle();
      expect(calls.last['op'], 'clear');
      expect(calls.last['includePins'], false);
    },
  );
  testWidgets('automatic screenshots can be disabled independently', (t) async {
    await t.pumpWidget(const MaterialApp(home: ClipboardShelfScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('History and privacy'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Automatically copy screenshots'));
    await t.tap(find.text('Automatically copy screenshots'));
    await t.pumpAndSettle();
    expect(screenshots, false);
  });
  testWidgets(
    'PC sending requires a selected connected target before reading a clip',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: ClipboardShelfScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Send to PC'));
      await t.tap(find.text('Send to PC'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Send to PC clipboard'), findsOneWidget);
      expect(
        find.text('No saved computers. Add one in Devices.'),
        findsOneWidget,
      );
      expect(calls.any((c) => c['op'] == 'detail'), false);
      final c = t.element(find.text('Send to PC clipboard'));
      Navigator.of(c).pop();
      await t.pumpAndSettle();
    },
  );
  testWidgets('shelf menu offers explicit Edge panel quick add', (t) async {
    await t.pumpWidget(const MaterialApp(home: ClipboardShelfScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Shelf options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add to Edge panel'));
    await t.pumpAndSettle();
    expect(calls.any((c) => c['method'] == 'addClipboardEdgeShortcut'), true);
  });
}
