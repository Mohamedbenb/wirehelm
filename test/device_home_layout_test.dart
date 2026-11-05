import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/commands/default_commands.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/controls_screen.dart';
import 'package:remote_control/screens/device_information_screen.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class OfflineSession extends SshSession {
  @override
  bool get isConnected => false;

  @override
  String? get deviceId => 'test-device';

  @override
  Future<bool> healthCheck() async => false;
}

class StaleSession extends SshSession {
  @override
  bool get isConnected => true;

  @override
  String? get deviceId => 'different-device';

  @override
  Future<bool> healthCheck() async => false;
}

void main() {
  testWidgets('device home uses a two-column tools grid with one media entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = OfflineSession();
    await tester.pumpWidget(
      MaterialApp(
        home: ControlsScreen(
          device: const Device(
            id: 'test-device',
            name: 'Desktop',
            host: '192.168.1.20',
            port: 22,
            username: 'user',
            shellStyle: 'windows',
            commands: windowsDefaultCommands,
          ),
          session: session,
          onDeviceUpdated: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Camera & microphone'), findsOneWidget);
    expect(find.text('Bluetooth devices'), findsOneWidget);
    expect(find.text('Remote keyboard'), findsOneWidget);
    expect(find.text('Find on LAN'), findsOneWidget);
    expect(find.text('Network & connected devices'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Terminal')).dx,
      lessThan(tester.getTopLeft(find.text('Remote keyboard')).dx),
    );
    expect(find.byTooltip('Device menu'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Control panel'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Control panel'));
    await tester.pumpAndSettle();
    expect(find.text('Network & devices'), findsOneWidget);
    expect(find.text('Remote keyboard'), findsNothing);
    expect(find.text('Windows text size'), findsNothing);
    expect(find.text('Camera & microphone'), findsNothing);
    await tester.scrollUntilVisible(find.text('Power controls'), 180);
    await tester.pumpAndSettle();
    expect(find.text('Power controls'), findsOneWidget);
    expect(find.text('Device information'), findsNothing);
    final lockCard = find
        .ancestor(of: find.text('Lock'), matching: find.byType(Card))
        .first;
    final shutdownCard = find
        .ancestor(of: find.text('Shutdown'), matching: find.byType(Card))
        .first;
    expect(
      identical(tester.element(lockCard), tester.element(shutdownCard)),
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Power controls'), findsNothing);
    expect(find.text('Remote keyboard'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Windows text size'), 180);
    expect(find.text('Windows text size'), findsOneWidget);

    expect(tester.takeException(), isNull);
    session.dispose();
  });

  testWidgets('opening a device can auto-connect once from its home', (
    tester,
  ) async {
    final session = StaleSession();
    var connectionAttempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ControlsScreen(
          device: const Device(
            id: 'test-device',
            name: 'Desktop',
            host: '192.168.1.20',
            port: 22,
            username: 'user',
            shellStyle: 'linux',
            commands: linuxDefaultCommands,
          ),
          session: session,
          autoConnectOnOpen: true,
          onConnect: () async => connectionAttempts++,
          onDeviceUpdated: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(connectionAttempts, 1);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Network & Pi health'), findsOneWidget);
    expect(tester.takeException(), isNull);
    session.dispose();
  });

  testWidgets('camera and microphone is not duplicated in device information', (
    tester,
  ) async {
    final session = OfflineSession();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceInformationScreen(
          device: const Device(
            id: 'test-device',
            name: 'Desktop',
            host: '192.168.1.20',
            port: 22,
            username: 'user',
            shellStyle: 'windows',
            commands: windowsDefaultCommands,
          ),
          session: session,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Camera & microphone'), findsNothing);
    expect(tester.takeException(), isNull);
    session.dispose();
  });
}
