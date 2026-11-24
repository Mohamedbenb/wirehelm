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

Finder tabScroll(String section) => find.descendant(
  of: find.byKey(PageStorageKey<String>('device-$section')),
  matching: find.byType(Scrollable),
);

Future<void> selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'device tabs keep connection actions visible and organize the tools',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = OfflineSession();
      addTearDown(session.dispose);
      var connectAttempts = 0;
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
            onConnect: () async => connectAttempts++,
            onFindOnLan: () async => null,
            onDeviceUpdated: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('Connect').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Find on LAN').hitTestable(), findsOneWidget);
      expect(find.text('Remote access').hitTestable(), findsOneWidget);
      expect(find.text('Live desktop').hitTestable(), findsOneWidget);
      expect(find.text('Files & updates'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Live desktop'))
            .enabled,
        isFalse,
      );

      await tester.scrollUntilVisible(
        find.text('Camera & microphone'),
        200,
        scrollable: tabScroll('tools'),
      );
      expect(find.text('Camera & microphone'), findsOneWidget);
      expect(find.text('Connect').hitTestable(), findsOneWidget);

      await selectTab(tester, 'Controls');
      expect(find.text('Power controls').hitTestable(), findsOneWidget);
      expect(find.text('Remote keyboard'), findsNothing);
      final lockCard = find
          .ancestor(of: find.text('Lock'), matching: find.byType(Card))
          .first;
      final shutdownCard = find
          .ancestor(of: find.text('Shutdown'), matching: find.byType(Card))
          .first;
      expect(tester.element(lockCard), same(tester.element(shutdownCard)));
      expect(find.text('Windows text size'), findsOneWidget);
      expect(find.text('Bluetooth devices'), findsOneWidget);

      await selectTab(tester, 'Commands');
      expect(find.text('Add command').hitTestable(), findsOneWidget);
      expect(find.text('Paste command').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(connectAttempts, 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey<String>('device-tools')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'CachyOS controls stay reachable on a narrow screen with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = OfflineSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: ControlsScreen(
            device: const Device(
              id: 'test-device',
              name: 'CachyOS desktop',
              host: '192.168.1.20',
              port: 22,
              username: 'user',
              shellStyle: 'linux',
              desktopProfile: 'cachyos',
              commands: [],
            ),
            session: session,
            onConnect: () async {},
            onFindOnLan: () async => null,
            onDeviceUpdated: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlock PC'), findsNothing);
      await tester.drag(find.byType(TabBarView), const Offset(-296, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey<String>('device-controls')),
        findsOneWidget,
      );
      for (final label in [
        'Lock',
        'Unlock PC',
        'Sleep',
        'Lock & sleep',
        'Restart',
        'Shut down',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
      }
      final powerCard = find.ancestor(
        of: find.byTooltip('Lock'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: powerCard, matching: find.byTooltip('Unlock PC')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Plasma text size'),
        120,
        scrollable: tabScroll('controls'),
      );
      expect(find.text('Display configuration'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Smart bulb'),
        120,
        scrollable: tabScroll('controls'),
      );
      expect(find.text('Smart bulb').hitTestable(), findsOneWidget);
      expect(find.text('Connect').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
    await tester.scrollUntilVisible(
      find.text('Network & Pi health'),
      160,
      scrollable: tabScroll('tools'),
    );
    expect(find.text('Network & Pi health').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Device information'),
      120,
      scrollable: tabScroll('tools'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Device information').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(DeviceInformationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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
