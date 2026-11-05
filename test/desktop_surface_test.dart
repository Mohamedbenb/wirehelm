import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/widgets/desktop_surface.dart';

void main() {
  for (final viewport in [const Size(393, 700), const Size(900, 393)]) {
    testWidgets('clicks align with the image in $viewport', (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1280, 720), Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(1280, 720);
      picture.dispose();
      addTearDown(image.dispose);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final events = <(double, double, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopSurface(
              image: image,
              enabled: true,
              mode: DesktopInputMode.touch,
              onPointer: (x, y, action, button, delta, deltaX, deltaY) =>
                  events.add((x, y, action)),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(RawImage));
      await tester.tapAt(rect.center);
      expect(events.single.$1, closeTo(0.5, 0.0001));
      expect(events.single.$2, closeTo(0.5, 0.0001));
      expect(events.single.$3, 'click');
      events.clear();
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * 0.9, rect.height * 0.1),
      );
      expect(events.single.$1, closeTo(0.9, 0.001));
      expect(events.single.$2, closeTo(0.1, 0.001));
      events.clear();
      await tester.tapAt(const Offset(1, 1));
      expect(events, isEmpty, reason: 'Letterboxing must not send clicks');
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.center + const Offset(40, 20));
      await gesture.moveTo(const Offset(-20, -20));
      await gesture.up();
      expect(events.first.$3, 'down');
      expect(events.last, (0.0, 0.0, 'up'));
      expect(events.where((e) => e.$3 == 'click'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('trackpad taps click in place and swipes move relatively', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1280, 720), Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, 720);
    picture.dispose();
    addTearDown(image.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final events = <(double, double, String, double, double)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSurface(
            image: image,
            enabled: true,
            mode: DesktopInputMode.pointer,
            onPointer: (x, y, action, button, delta, deltaX, deltaY) =>
                events.add((x, y, action, deltaX, deltaY)),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(RawImage));
    final tap = await tester.startGesture(rect.center);
    await tap.moveBy(const Offset(4, 3));
    await tap.up();
    expect(events.single.$3, 'clickAtCursor');
    events.clear();
    await tester.pump(const Duration(milliseconds: 500));
    final secondTap = await tester.startGesture(
      rect.center + const Offset(80, 20),
    );
    await secondTap.up();
    expect(events.map((event) => event.$3), ['downAtCursor', 'upAtCursor']);
    events.clear();
    await tester.pump(const Duration(milliseconds: 500));

    final swipe = await tester.startGesture(rect.center + const Offset(80, 0));
    await swipe.moveBy(const Offset(100, -50));
    await swipe.up();
    final relative = events.where((event) => event.$3 == 'relative');
    expect(relative, isNotEmpty);
    expect(
      relative.fold<double>(0, (sum, event) => sum + event.$4),
      closeTo(100 / rect.width * 2.75, 0.01),
      reason: 'High sensitivity is 2.75×',
    );
    expect(
      relative.fold<double>(0, (sum, event) => sum + event.$5),
      closeTo(-50 / rect.height * 2.75, 0.01),
    );
    expect(events.any((event) => event.$3 == 'clickAtCursor'), isFalse);
    expect(events.any((event) => event.$3 == 'downAtCursor'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('double-tap and hold starts a relative drag', (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1280, 720), Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, 720);
    picture.dispose();
    addTearDown(image.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSurface(
            image: image,
            enabled: true,
            mode: DesktopInputMode.pointer,
            onPointer: (x, y, action, button, delta, deltaX, deltaY) =>
                actions.add(action),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(RawImage));
    final firstTap = await tester.startGesture(rect.center);
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 100));

    final secondTap = await tester.startGesture(rect.center);
    await secondTap.moveBy(const Offset(80, 24));
    await secondTap.up();
    expect(actions.first, 'clickAtCursor');
    expect(actions, contains('downAtCursor'));
    expect(actions, contains('relative'));
    expect(actions.last, 'upAtCursor');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a regular double tap still sends two mouse clicks', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1280, 720), Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, 720);
    picture.dispose();
    addTearDown(image.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final events = <(String, double, double)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSurface(
            image: image,
            enabled: true,
            mode: DesktopInputMode.pointer,
            onPointer: (x, y, action, button, delta, deltaX, deltaY) =>
                events.add((action, x, y)),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(RawImage));
    final firstTap = await tester.startGesture(rect.center);
    await firstTap.up();
    await tester.pump(const Duration(milliseconds: 100));
    final secondTap = await tester.startGesture(rect.center);
    await secondTap.up();
    expect(events, [
      ('clickAtCursor', 0.5, 0.5),
      ('downAtCursor', 0.5, 0.5),
      ('upAtCursor', 0.5, 0.5),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
