import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/models/device.dart';
import 'package:remote_control/screens/controls_screen.dart';
import 'package:remote_control/services/plasma_desktop_resume.dart';
import 'package:remote_control/ssh/ssh_session.dart';

const _pc = Device(
  id: 'pc',
  name: 'Desktop',
  host: 'desktop',
  port: 22,
  username: 'owner',
  shellStyle: 'linux',
  desktopProfile: 'cachyos',
  commands: [],
);

class _Client implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DesktopSession extends SshSession {
  _DesktopSession(this.replies) : super(manageBackgroundKeepAlive: false);

  final List<String> replies;
  final commands = <String>[];

  @override
  SSHClient? client = _Client();

  @override
  bool get isConnected => true;

  @override
  String get deviceId => _pc.id;

  @override
  String? hostKeyIdentity = 'verified';

  @override
  String get authenticatedUsername => _pc.username;

  @override
  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    commands.add(command);
    expect(input, isNotNull);
    return utf8.encode('__WIREHELM_PLASMA__ ${replies.removeAt(0)}\n');
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_control/desktop_unlock');
  final messenger = binding.defaultBinaryMessenger;
  var prompts = 0;
  bool Function()? respond;

  setUp(() {
    prompts = 0;
    respond = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      prompts++;
      expect(call.method, 'authenticate');
      expect(call.arguments, {'device': _pc.name});
      return respond!();
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<PlasmaDesktopPreparation> prepare(
    _DesktopSession session, {
    bool Function()? cancelled,
  }) {
    addTearDown(session.dispose);
    return preparePlasmaDesktop(
      device: _pc,
      session: session,
      cancelled: cancelled ?? () => false,
    );
  }

  test('opens an unlocked desktop without asking for authentication', () async {
    final session = _DesktopSession(['ready']);
    expect(await prepare(session), PlasmaDesktopPreparation.ready);
    expect(session.commands, ['sh -s']);
    expect(prompts, 0);
  });

  test('phone authentication unlocks the probed session', () async {
    final session = _DesktopSession(['locked c2', 'ready']);
    respond = () {
      expect(session.commands, ['sh -s']);
      return true;
    };
    expect(await prepare(session), PlasmaDesktopPreparation.ready);
    expect(session.commands, ['sh -s', 'sh -s -- c2']);
    expect(prompts, 1);
  });

  test('cancelling authentication leaves the desktop locked', () async {
    final session = _DesktopSession(['locked c2']);
    respond = () => false;
    expect(await prepare(session), PlasmaDesktopPreparation.cancelled);
    expect(session.commands, ['sh -s']);
  });

  test('an abandoned request cannot unlock after authentication', () async {
    final session = _DesktopSession(['locked c2']);
    var cancelled = false;
    respond = () {
      cancelled = true;
      return true;
    };
    expect(
      await prepare(session, cancelled: () => cancelled),
      PlasmaDesktopPreparation.cancelled,
    );
    expect(session.commands, ['sh -s']);
  });

  test(
    'rejects unlock if the SSH connection changed during the prompt',
    () async {
      final session = _DesktopSession(['locked c2']);
      respond = () {
        session.client = _Client();
        return true;
      };
      await expectLater(prepare(session), throwsStateError);
      expect(session.commands, ['sh -s']);
    },
  );

  test(
    'an unconfirmed display wake leaves the unlocked desktop usable',
    () async {
      final session = _DesktopSession(['display-unconfirmed']);
      expect(
        await prepare(session),
        PlasmaDesktopPreparation.displayUnconfirmed,
      );
      expect(prompts, 0);
    },
  );

  testWidgets(
    'CachyOS Power controls unlock directly without opening a stream',
    (tester) async {
      final session = _DesktopSession(['locked c2', 'ready']);
      addTearDown(session.dispose);
      respond = () => true;
      await tester.pumpWidget(
        MaterialApp(
          home: ControlsScreen(
            device: _pc,
            session: session,
            onDeviceUpdated: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Controls'));
      await tester.pumpAndSettle();
      final unlock = find.byTooltip('Unlock PC');
      await tester.ensureVisible(unlock);
      await tester.tap(unlock.hitTestable());
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(session.commands, ['sh -s', 'sh -s -- c2']);
      expect(find.text('PC is unlocked. Display is awake.'), findsOneWidget);
      expect(find.byType(ControlsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('a fresh boot reports the required Plasma sign-in', () async {
    final session = _DesktopSession(['sign-in']);
    await expectLater(
      prepare(session),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Sign in to Plasma'),
        ),
      ),
    );
    expect(prompts, 0);
    expect(session.commands, ['sh -s']);
  });
}
