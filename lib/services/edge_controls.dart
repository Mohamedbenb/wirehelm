import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../devices/device_connection_service.dart';
import '../models/device.dart';
import '../ssh/ssh_session.dart';
import '../ssh/ssh_session_manager.dart';
import 'device_storage.dart';
import 'known_host_storage.dart';
import 'linux_desktop.dart';
import 'plasma_desktop_resume.dart';
import 'plasma_power.dart';
import 'plasma_settings.dart';
import 'remote_keyboard.dart';
import 'smart_bulb.dart';

bool isEdgeBulbHost(Device device) =>
    device.shellStyle == 'linux' ||
    device.commands.any(
      (command) =>
          command.templateId?.startsWith('linux_') == true ||
          command.id.startsWith('linux_'),
    );

bool isEdgePcHost(Device device) => device.commandProfile == 'cachyos';

/// The panel first asks the running app for a matching authenticated session.
void attachSharedEdgeControls() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  const channel = MethodChannel('remote_control/shared_edge_controls');
  _EdgeControlWorker(
    channel,
    borrowSession: sshSessions.existingSession,
  ).attach();
  unawaited(
    channel
        .invokeMethod<void>('ready')
        .onError<MissingPluginException>((_, _) {}),
  );
}

/// A separate engine owns the short-lived connection when the app has none.
Future<void> attachEdgeControls() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_control/edge_controls');
  _EdgeControlWorker(channel).attach();
  await channel.invokeMethod<void>('ready');
}

class _EdgeControlWorker {
  _EdgeControlWorker(this.channel, {this.borrowSession});

  final MethodChannel channel;
  final SshSession? Function(String deviceId)? borrowSession;
  final _ownedSession = SshSession(manageBackgroundKeepAlive: false);
  String? _keyboardOwner;
  WaylandKeyboard? _keyboard;
  Object? _keyboardClient;
  bool? _keyboardWindows;

  void attach() => channel.setMethodCallHandler(_handle);

  Future<void> _closeKeyboard() async {
    final keyboard = _keyboard;
    _keyboard = null;
    _keyboardOwner = null;
    _keyboardClient = null;
    _keyboardWindows = null;
    await keyboard?.closeSession();
  }

  Future<Map<String, Object?>?> _handle(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map? ?? {});
    final owner = args['owner'] as String?;
    if (call.method == 'closeOwner') {
      if (_keyboardOwner == owner) await _closeKeyboard();
      return null;
    }

    final host = args['device'] as String;
    final lookup = borrowSession;
    final candidate = lookup == null ? _ownedSession : lookup(host);
    final session = candidate ?? _ownedSession;
    if (lookup != null &&
        (candidate == null || !_connectedTo(candidate, host))) {
      return {'noSession': true};
    }

    final request = args['request'] as String?;
    Future<bool> canRun() async =>
        await channel.invokeMethod<bool>('canRun', request) ?? false;
    final keyboardPage =
        call.method == 'keyboardRead' || call.method == 'keyboardSend';
    final pc = switch (call.method) {
      'pcRead' || 'pcPower' || 'pcUnlock' || 'textRead' || 'textApply' => true,
      _ => false,
    };
    if (lookup == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
    }
    final devices = await DeviceStorage().loadDevices();
    final device = devices
        .where(
          (device) =>
              device.id == host &&
              (keyboardPage ||
                  (pc ? isEdgePcHost(device) : isEdgeBulbHost(device))),
        )
        .firstOrNull;
    if (device == null) {
      return {
        'error': keyboardPage
            ? 'Choose a keyboard host in Wirehelm’s Panel actions.'
            : pc
            ? 'Choose a CachyOS PC in Wirehelm’s Panel actions.'
            : 'Choose a bulb host in Wirehelm’s Panel actions.',
      };
    }

    final known = await KnownHostStorage().getKnownHost(
      host: device.host,
      port: device.port,
    );
    if (known == null) {
      return {'error': 'Connect to this host in Wirehelm to verify it first.'};
    }
    final keyIdentity =
        '${known.keyType}:${base64Encode(known.fingerprint.codeUnits)}';
    bool matches() =>
        _connectedTo(session, host) &&
        session.configuredEndpoint == known.endpoint &&
        session.authenticatedUsername == device.username &&
        session.hostKeyIdentity == keyIdentity;
    if (!matches()) {
      if (lookup != null) return {'noSession': true};
      await _closeKeyboard();
      _ownedSession.disconnect();
      if (!await canRun()) {
        return {'error': 'The Controls page is unavailable.'};
      }
      try {
        await DeviceConnectionService().connect(
          device,
          targetSession: session,
          verifyHostKey: (_, type, fingerprint) async =>
              known.keyType == type &&
              known.fingerprint == String.fromCharCodes(fingerprint),
        );
      } catch (_) {
        return {'error': 'Could not connect to the selected host.'};
      }
    }

    final client = session.client;
    Future<bool> canUseSession() async =>
        await canRun() && identical(session.client, client) && matches();
    if (!await canUseSession()) {
      return {'error': 'The Controls page is unavailable.'};
    }

    if (keyboardPage) {
      if (call.method == 'keyboardSend') {
        try {
          if (_keyboardOwner != owner || !identical(_keyboardClient, client)) {
            await _closeKeyboard();
            if (!await canUseSession()) {
              return {'error': 'The keyboard page is closed.'};
            }
            _keyboardOwner = owner;
            _keyboardClient = client;
            _keyboard = WaylandKeyboard();
          }
          final keyboard = _keyboard!;
          final windows =
              _keyboardWindows ??
              await remoteKeyboardUsesWindows(device, session);
          if (identical(_keyboard, keyboard)) _keyboardWindows = windows;
          await sendRemoteKeyboard(
            device,
            session,
            windows: windows,
            text: args['text'] as String?,
            key: args['key'] as String?,
            wayland: keyboard,
            canSend: () async =>
                await canUseSession() && identical(_keyboard, keyboard),
          );
        } catch (_) {
          return {
            'error': 'Input was not confirmed. Check keyboard access for this host in Wirehelm.',
          };
        }
      }
      return {'deviceName': device.name, 'ready': true};
    }
    if (pc) {
      final target = {'deviceName': device.name, 'ready': true};
      try {
        switch (call.method) {
          case 'pcRead':
            return target;
          case 'pcPower':
            await sendConfirmedPlasmaPower(
              device: device,
              session: session,
              action: PlasmaPowerAction.values.byName(args['action'] as String),
            );
            return target;
          case 'pcUnlock':
            try {
              final result = await preparePlasmaDesktop(
                device: device,
                session: session,
                cancelled: () => !identical(session.client, client),
                authenticate: (name) async =>
                    await canUseSession() &&
                    (await channel.invokeMethod<bool>('authenticateUnlock', {
                          'request': request,
                          'device': name,
                        }) ??
                        false) &&
                    await canUseSession(),
              );
              return {...target, 'unlock': result.name};
            } on PlatformException catch (error) {
              return {'error': error.message ?? 'Phone authentication failed.'};
            }
          case 'textRead':
          case 'textApply':
            final settings = await PlasmaSettings(device, session).run({
              'action': 'text',
              if (call.method == 'textApply')
                'size': (args['halfPoints'] as int) / 2,
            });
            return {
              ...target,
              'size': (settings['size'] as num).toDouble(),
              'sizesMatch': settings['sizesMatch'] == true,
            };
        }
      } on StateError catch (error) {
        final message = error.message.toString();
        return {
          'error': message.length <= 180
              ? message
              : 'The PC did not confirm the request.',
        };
      }
    }

    final target = SmartBulb(device, session);
    try {
      final state = await switch (call.method) {
        'read' => target.read(),
        'power' => target.power(args['on'] as bool),
        'white' => target.white(
          args['brightness'] as int,
          args['temperature'] as int,
        ),
        'color' => target.color(
          args['brightness'] as int,
          args['hue'] as int,
          args['saturation'] as int,
        ),
        _ => throw const FormatException('Unsupported control'),
      };
      return {
        'on': state.on,
        'color': state.mode == 'colour',
        'whiteBrightness': state.whiteBrightness,
        'colorBrightness': state.colorBrightness,
        'temperature': state.temperature,
        'hue': state.hue,
        'saturation': state.saturation,
      };
    } on SmartBulbException catch (error) {
      return {
        'error': switch (error.code) {
          'configuration' ||
          'dependency' => 'Finish Smart bulb setup on this host in Wirehelm.',
          'offline' => 'The bulb is unreachable from the saved host.',
          _ => 'The bulb did not confirm the change. Refresh to check it.',
        },
      };
    }
  }

  static bool _connectedTo(SshSession session, String host) =>
      session.isConnected &&
      session.deviceId == host &&
      session.client?.isClosed == false;
}
