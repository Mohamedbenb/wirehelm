import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/smart_bulb_screen.dart';
import 'package:remote_control/services/smart_bulb.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _FakeBulb extends SmartBulb {
  _FakeBulb()
    : super(
        const Device(
          id: 'test',
          name: 'PC',
          host: '192.168.1.20',
          port: 22,
          username: 'user',
          commands: [],
        ),
        SshSession(),
      );

  final writes = <(String, int, int, int)>[];
  final completions = <Completer<SmartBulbState>>[];

  static SmartBulbState _state({String mode = 'white', int brightness = 100}) =>
      SmartBulbState({
        'on': true,
        'mode': mode,
        'whiteBrightness': brightness,
        'temperature': 90,
        'hue': 0,
        'saturation': 100,
        'colorBrightness': 100,
        'address': '192.168.1.119',
        'deviceId': 'test-bulb',
      });

  @override
  Future<SmartBulbState> read() async => _state();

  @override
  Future<SmartBulbState> white(int brightness, int temperature) =>
      _record(('white', brightness, temperature, 0));

  @override
  Future<SmartBulbState> color(int brightness, int hue, int saturation) =>
      _record(('colour', brightness, hue, saturation));

  Future<SmartBulbState> _record((String, int, int, int) write) {
    final reply = Completer<SmartBulbState>();
    writes.add(write);
    completions.add(reply);
    return reply.future;
  }

  void confirm(int index) {
    final write = writes[index];
    completions[index].complete(_state(mode: write.$1, brightness: write.$2));
  }
}

Future<void> _open(WidgetTester tester, _FakeBulb bulb) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: SmartBulbScreen(bulb: bulb)));
  await tester.pumpAndSettle();
}

Slider _brightness(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider).first);

void main() {
  testWidgets('sends during drag, coalesces, and flushes the final value', (
    tester,
  ) async {
    final bulb = _FakeBulb();
    await _open(tester, bulb);
    expect(find.text('Apply'), findsNothing);

    _brightness(tester).onChanged!(70);
    await tester.pump(const Duration(milliseconds: 150));
    expect(bulb.writes, [('white', 70, 90, 0)]);

    final currentSlider = _brightness(tester);
    currentSlider.onChanged!(52);
    currentSlider.onChanged!(70);
    await tester.pump();
    expect(_brightness(tester).value, 70);
    _brightness(tester).onChanged!(37);
    await tester.pump();
    _brightness(tester).onChangeEnd!(37);
    expect(bulb.writes, hasLength(1));

    bulb.confirm(0);
    await tester.pump();
    expect(_brightness(tester).value, 37);
    expect(bulb.writes.last, ('white', 37, 90, 0));

    bulb.confirm(1);
    await tester.pumpAndSettle();
    expect(bulb.writes, hasLength(2));
    expect(_brightness(tester).value, 37);
  });

  testWidgets('mode changes send immediately and recover after an error', (
    tester,
  ) async {
    final bulb = _FakeBulb();
    await _open(tester, bulb);

    await tester.tap(find.text('Color'));
    await tester.pump();
    expect(bulb.writes, [('colour', 100, 0, 100)]);

    await tester.tap(find.text('White'));
    await tester.pump();
    expect(bulb.writes, hasLength(1));

    bulb.completions.first.completeError(const SmartBulbException('Timeout'));
    await tester.pump();
    expect(bulb.writes.last, ('white', 100, 90, 0));
    bulb.confirm(1);
    await tester.pumpAndSettle();
    expect(find.text('Timeout'), findsNothing);
  });

  testWidgets('leaving the screen preserves the last queued setting', (
    tester,
  ) async {
    final bulb = _FakeBulb();
    await _open(tester, bulb);

    _brightness(tester).onChanged!(65);
    await tester.pump(const Duration(milliseconds: 150));
    _brightness(tester).onChanged!(29);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(bulb.writes, hasLength(1));

    bulb.confirm(0);
    await tester.pump();
    expect(bulb.writes.last, ('white', 29, 90, 0));
    bulb.confirm(1);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
