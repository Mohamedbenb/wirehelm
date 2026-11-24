import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remote_control/customization/local_customization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/edge_actions_screen.dart';
import 'package:remote_control/services/edge_controls.dart';
import 'package:remote_control/widgets/edge_panel_control_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void mockPanelActions() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var raw = '{}';
  messenger.setMockMethodCallHandler(LocalCustomization.channel, (call) async {
    if (call.method == 'saveEdgeActions') {
      raw = (call.arguments as Map)['raw'] as String;
    }
    return jsonEncode({'raw': raw});
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(LocalCustomization.channel, null),
  );
}

void main() {
  testWidgets(
    'toolbar draft can enable clipboard without adding material fields',
    (t) async {
      mockPanelActions();
      String? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(c).push<String>(
                  MaterialPageRoute(builder: (_) => const EdgeActionsScreen()),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('Clipboard shelf'),
        matching: find.byType(ListTile),
      );
      await t.ensureVisible(tile);
      await t.tap(find.descendant(of: tile, matching: find.byType(Switch)));
      await t.tap(find.widgetWithText(TextButton, 'Save'));
      await t.pumpAndSettle();
      final value = jsonDecode(saved!) as Map;
      expect(value['hidden'], isNot(contains('clipboard')));
      expect(
        value.keys,
        unorderedEquals(['order', 'hidden', 'labels', 'iconSize', 'columns']),
      );
    },
  );
  testWidgets('back cancels an action draft', (t) async {
    mockPanelActions();
    String? saved;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(c).push<String>(
                MaterialPageRoute(builder: (_) => const EdgeActionsScreen()),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(saved, isNull);
  });
  testWidgets('direct action editor loads and saves only toolbar options', (
    t,
  ) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalCustomization.channel, (call) async {
          if (call.method == 'saveEdgeActions') {
            saved = (call.arguments as Map)['raw'] as String;
          }
          return jsonEncode({'raw': saved ?? '{}'});
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalCustomization.channel, null),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute(builder: (_) => const EdgeActionsScreen()),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Save'));
    await t.pumpAndSettle();
    expect(
      jsonDecode(saved!).keys,
      unorderedEquals(['order', 'hidden', 'labels', 'iconSize', 'columns']),
    );
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('control visibility and host selections are independent', (
    t,
  ) async {
    mockPanelActions();
    SharedPreferences.setMockInitialValues({
      'devices': jsonEncode([
        {
          'id': 'linux-host',
          'name': 'Living room PC',
          'host': 'linux.example',
          'port': 22,
          'username': 'me',
          'shellStyle': 'linux',
        },
        {
          'id': 'cachy-pc',
          'name': 'CachyOS PC',
          'host': 'plasma.example',
          'port': 22,
          'username': 'me',
          'shellStyle': 'linux',
          'desktopProfile': 'cachyos',
        },
        {
          'id': 'windows-host',
          'name': 'Windows PC',
          'host': 'windows.example',
          'port': 22,
          'username': 'me',
          'shellStyle': 'windows',
        },
      ]),
    });
    String? saved;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const EdgeActionsScreen()),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    final controls = find.text('Controls list');
    await t.scrollUntilVisible(
      controls,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(controls);
    await t.pumpAndSettle();
    final keyboardRow = find.widgetWithText(
      CheckboxListTile,
      'Remote keyboard',
    );
    await t.scrollUntilVisible(
      keyboardRow,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(t.widget<CheckboxListTile>(keyboardRow).value, isFalse);
    await t.tap(keyboardRow);
    await t.pumpAndSettle();
    expect(t.widget<CheckboxListTile>(keyboardRow).value, isTrue);
    final setting = find.text('Smart bulb on the Controls page');
    await t.scrollUntilVisible(
      setting,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(setting);
    await t.pumpAndSettle();
    expect(find.text('Windows PC'), findsNothing);
    await t.tap(find.text('Living room PC'));
    await t.pumpAndSettle();
    final pc = find.text('PC on the Controls page');
    await t.scrollUntilVisible(
      pc,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(pc);
    await t.pumpAndSettle();
    expect(find.text('Living room PC').hitTestable(), findsNothing);
    await t.tap(find.text('CachyOS PC'));
    await t.pumpAndSettle();
    final keyboardHost = find.text('Remote keyboard on the Controls page');
    await t.scrollUntilVisible(
      keyboardHost,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(keyboardHost);
    await t.pumpAndSettle();
    await t.tap(find.text('Windows PC'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Save'));
    await t.pumpAndSettle();
    final value = jsonDecode(saved!) as Map;
    expect(value['bulbDevice'], 'linux-host');
    expect(value['pcDevice'], 'cachy-pc');
    expect(value['keyboardDevice'], 'windows-host');
    expect(value['controls'], ['bulb', 'power', 'text', 'keyboard']);
    expect(value['hidden'], ['clipboard']);
    expect(value['order'], edgeActionLabels.keys.toList());
  });

  testWidgets('a control page updates the saved panel list', (t) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final shown = List<String>.of(defaultEdgeControls);
    final writes = <Object?>[];
    messenger.setMockMethodCallHandler(LocalCustomization.channel, (
      call,
    ) async {
      if (call.method == 'setEdgeControlVisibility') {
        final args = call.arguments as Map;
        writes.add(args);
        if (args['shown'] == true) {
          shown.add(args['control'] as String);
        } else {
          shown.remove(args['control']);
        }
      }
      return jsonEncode({
        'raw': jsonEncode({'controls': shown, 'keyboardDevice': 'saved-host'}),
      });
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LocalCustomization.channel, null),
    );
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EdgePanelControlToggle(
            control: EdgePanelControl.keyboard,
            deviceId: 'different-host',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final toggle = find.widgetWithText(SwitchListTile, 'Show in Edge panel');
    expect(t.widget<SwitchListTile>(toggle).value, isFalse);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      find.text('The panel uses a different host selected in Panel actions.'),
      findsOneWidget,
    );
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(toggle).value, isFalse);
    expect(writes, [
      {'control': 'keyboard', 'device': 'different-host', 'shown': true},
      {'control': 'keyboard', 'device': 'different-host', 'shown': false},
    ]);
  });

  testWidgets('bulb worker requires an already verified SSH host', (t) async {
    SharedPreferences.setMockInitialValues({
      'devices': jsonEncode([
        {
          'id': 'linux-host',
          'name': 'Living room PC',
          'host': 'linux.example',
          'port': 22,
          'username': 'me',
          'shellStyle': 'linux',
        },
      ]),
    });
    const channel = MethodChannel('remote_control/edge_controls');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ready');
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      channel.setMethodCallHandler(null);
    });
    await attachEdgeControls();

    Future<String?> read(String device, [String method = 'read']) async {
      const codec = StandardMethodCodec();
      final result = Completer<ByteData?>();
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, {'device': device})),
        result.complete,
      );
      final response = codec.decodeEnvelope((await result.future)!) as Map;
      return response['error'] as String?;
    }

    expect(await read('linux-host'), contains('verify it first'));
    expect(await read('missing-host'), contains('Choose a bulb host'));
    expect(await read('linux-host', 'pcRead'), contains('Choose a CachyOS PC'));
    expect(
      await read('linux-host', 'keyboardRead'),
      contains('verify it first'),
    );
  });
}
