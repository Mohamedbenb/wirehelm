import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:remote_control/customization/network_indicator_preview.dart';
import 'package:remote_control/screens/local_customization_screen.dart';
import 'package:remote_control/screens/network_speed_screen.dart';

import 'fixtures/customization_report.dart';

void main() {
  testWidgets('Network speed recovers while its page is visible', (
    tester,
  ) async {
    final data = healthyCustomizationReport();
    final config = data['config'] as Map;
    final hook = data['hook'] as Map;
    config['enabled'] = false;
    hook['fresh'] = false;
    data['canEnable'] = false;
    data['blockers'] = ['Waiting for a fresh SystemUI report'];
    final capabilities = data['capabilities'] as List;
    capabilities.remove('xposed.systemuiHook');
    data['xposed'] = {'connected': false};

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var applyCalls = 0;
    messenger.setMockMethodCallHandler(LocalCustomization.channel, (
      call,
    ) async {
      if (call.method == 'apply') {
        applyCalls++;
        expect(
          jsonDecode((call.arguments as Map)['config'] as String)['enabled'],
          true,
        );
        if (applyCalls == 1) {
          throw PlatformException(
            code: 'CUSTOMIZATION_FAILED',
            message: 'Root access denied',
          );
        }
        config['enabled'] = true;
      }
      return jsonEncode(data);
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalCustomization.channel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(home: LocalCustomizationScreen()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('UI features'));
    await tester.tap(find.text('UI features'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Network speed'));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Show in status bar');
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
    expect(find.text('Waiting for a fresh SystemUI report'), findsOneWidget);

    hook['fresh'] = true;
    hook['state'] = 'disabled';
    data['canEnable'] = true;
    data['blockers'] = <String>[];
    capabilities.add('xposed.systemuiHook');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.textContaining('Root access denied'), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(applyCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'upload toggle preserves idle preference and health opens as a dedicated screen',
    (tester) async {
      final data = healthyCustomizationReport();
      Map<String, dynamic>? applied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, (
            MethodCall call,
          ) async {
            if (call.method == 'applyVisual') {
              applied = Map<String, dynamic>.from(
                jsonDecode((call.arguments as Map)['config'] as String) as Map,
              );
              data['config'] = applied!;
            }
            return jsonEncode(data);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LocalCustomization.channel, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: LocalCustomizationScreen()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('UI features'));
      await tester.tap(find.text('UI features'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Network speed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Traffic and visibility'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Traffic and visibility'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show upload speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show upload speed'));
      await tester.pumpAndSettle();
      expect(applied?['showUpload'], false);
      expect(applied?['hideIdle'], false);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Customization health'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customization health'));
      await tester.pumpAndSettle();
      expect(find.text('Health checks'), findsOneWidget);
      expect(find.text('Checks passing'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'size changes are delivered during a drag with the preview pinned',
    (tester) async {
      final changes = <(String, Object)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkSpeedScreen(
              report: healthyCustomizationReport(),
              busy: false,
              error: null,
              onEnabledChanged: (_) => fail('Resizing changed activation'),
              onSettingChanged: (key, value) => changes.add((key, value)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.byType(NetworkIndicatorPreview);
      final previewTop = tester.getTopLeft(preview);
      final layout = find.text('Position and sizing');
      await tester.scrollUntilVisible(layout.hitTestable(), 180);
      await tester.pumpAndSettle();
      await tester.tap(layout);
      await tester.pumpAndSettle();
      final firstSlider = find.byType(Slider).first;
      await tester.ensureVisible(firstSlider);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(preview), previewTop);
      final gesture = await tester.startGesture(tester.getCenter(firstSlider));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(changes, isNotEmpty);
      expect(
        changes.map((change) => change.$1),
        everyElement('stackedTextSize'),
      );
      await gesture.up();
    },
  );
}
