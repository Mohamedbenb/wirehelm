import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'add_command_screen.dart';
import '../commands/default_commands.dart';
import '../commands/command_options_menu.dart';
import '../models/device.dart';
import '../models/remote_command.dart';
import '../ssh/ssh_session.dart';
import '../stateful/stateful_command_executor.dart';
import '../stateful/stateful_command_item.dart';
import '../stateful/stateful_controls_controller.dart';
import 'terminal_screen.dart';
import 'device_information_screen.dart';
import 'bluetooth_devices_screen.dart';
import 'remote_keyboard_screen.dart';
import 'remote_media_screen.dart';
import 'sftp_screen.dart';
import 'windows_text_size_screen.dart';
import 'performance_screen.dart';
import 'remote_screenshot_screen.dart';
import 'remote_desktop_screen.dart';
import 'linux_health_screen.dart';
import '../utils/command_icons.dart';
import '../utils/command_parameters.dart';
import '../utils/sudo_command.dart';
import '../utils/command_transfer.dart';
import '../widgets/app_update_banner.dart';

class ControlsScreen extends StatefulWidget {
  final Device device;

  //
  // Optional during the multi-session
  // migration.
  //
  // Once DevicesScreen is migrated it will
  // always pass the device-specific session.
  //
  final SshSession? session;

  final Future<void> Function(Device device) onDeviceUpdated;
  final Future<void> Function()? onConnect;
  final bool autoConnectOnOpen;
  final List<Device> peerDevices;
  final Future<String?> Function()? onFindOnLan;
  final Future<void> Function(Device)? onOpenPeer;

  const ControlsScreen({
    super.key,
    required this.device,
    this.session,
    this.onConnect,
    this.autoConnectOnOpen = false,
    this.peerDevices = const [],
    this.onFindOnLan,
    this.onOpenPeer,
    required this.onDeviceUpdated,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen>
    with WidgetsBindingObserver {
  bool _appActive = true;
  bool _wasConnected = false;
  bool _lostConnection = false;

  bool get _canRefreshStatuses =>
      mounted &&
      _appActive &&
      (ModalRoute.of(context)?.isCurrent ?? false) &&
      _view == 'controls' &&
      _session.isConnected &&
      _session.deviceId == _device.id;

  void _onSessionChanged() {
    if (!mounted) return;
    final connected = _session.isConnected && _session.deviceId == _device.id;
    if (_wasConnected && !connected) {
      _statefulControls.markDisconnected();
      _lostConnection = true;
    }
    if (!_wasConnected && connected && _canRefreshStatuses) {
      unawaited(_refreshStatefulStatuses());
    }
    _wasConnected = connected;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_canRefreshStatuses) unawaited(_refreshStatefulStatuses());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statefulControls.startPolling(
      context: context,
      commands: () => _device.commands,
      canPoll: () => _canRefreshStatuses,
    );
  }

  late Device _device;

  late final SshSession _session;

  late final StatefulControlsController _statefulControls;

  bool _busy = false;
  bool _connecting = false;
  bool _findingLanAddress = false;
  String _view = 'home';
  Future<bool?>? _windowsAdminCheck;

  String? _status;

  final Set<String> _updatingTargetCommandIds = <String>{};

  bool _isUserSavedCommand(RemoteCommand command) => command.templateId == null;

  Future<bool?> _windowsAccountIsAdmin() {
    if (_device.shellStyle != 'windows') return Future.value(null);
    return _windowsAdminCheck ??= () async {
      try {
        final result = await _session.runPowerShell(
          r"[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
          label: 'Account privilege check',
          timeout: const Duration(seconds: 5),
        );
        return utf8.decode(result, allowMalformed: true).trim().toLowerCase() ==
            'true';
      } catch (_) {
        return null;
      }
    }();
  }

  String _accountPermissionsMessage(bool? isAdmin) => switch (isAdmin) {
    true => 'The connected Windows account has administrator privileges. This command can make system-wide changes.',
    false => 'This runs with the permissions of the connected Windows account.',
    null => 'The account privilege check was unavailable. Assume this runs with all permissions granted to the connected account.',
  };

  @override
  void initState() {
    super.initState();

    _device = widget.device;

    //
    // Backward compatible until
    // DevicesScreen performs the final
    // manager cutover.
    //
    _session = widget.session ?? sshSession;

    _statefulControls = StatefulControlsController(
      session: _session,
      interval: Duration(seconds: _device.refreshSeconds),
    );

    _statefulControls.addListener(_onStatefulControlsChanged);

    WidgetsBinding.instance.addObserver(this);
    _wasConnected = _session.isConnected && _session.deviceId == _device.id;
    _session.addListener(_onSessionChanged);

    unawaited(_session.healthCheck());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.autoConnectOnOpen &&
            (!_session.isConnected || _session.deviceId != _device.id)) {
          unawaited(_connectFromHome());
        } else {
          _refreshStatefulStatuses();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _statefulControls.removeListener(_onStatefulControlsChanged);

    _statefulControls.dispose();

    super.dispose();
  }

  void _onStatefulControlsChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _refreshStatefulStatuses({bool allowPrompt = false}) async {
    _statefulControls.setRefreshInterval(
      Duration(seconds: _device.refreshSeconds),
    );
    final connected = _session.isConnected && _session.deviceId == _device.id;

    if (!connected || !_canRefreshStatuses) {
      return;
    }

    await _statefulControls.refreshCommands(
      context: context,
      commands: _device.commands,
      allowPrompt: allowPrompt,
    );
  }

  Future<void> _connectFromHome() async {
    if (widget.onConnect == null || _connecting) return;
    setState(() => _connecting = true);
    try {
      await widget.onConnect!();
      final discoveredHost = _session.connectionRoute == 'LAN'
          ? _session.connectedHost
          : null;
      if (discoveredHost != null && discoveredHost != _device.localHost) {
        final updated = _device.copyWith(localHost: discoveredHost);
        await widget.onDeviceUpdated(updated);
        if (mounted) setState(() => _device = updated);
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _findDeviceOnLan() async {
    final find = widget.onFindOnLan;
    if (find == null || _findingLanAddress) return;
    setState(() => _findingLanAddress = true);
    try {
      final host = await find();
      if (!mounted) return;
      if (host != null && host != _device.localHost) {
        final updated = _device.copyWith(localHost: host);
        await widget.onDeviceUpdated(updated);
        if (!mounted) return;
        setState(() => _device = updated);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            host == null
                ? 'Device not found on this Wi-Fi network.'
                : 'Found and saved the device at $host.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('LAN search failed: $error')));
    } finally {
      if (mounted) setState(() => _findingLanAddress = false);
    }
  }

  bool _commandMatchesTemplate(RemoteCommand command, RemoteCommand template) {
    final templateId = template.templateId ?? template.id;

    if (command.templateId == templateId) {
      return true;
    }

    if (command.id == template.id) {
      return true;
    }

    //
    // Compatibility with commands created
    // before templateId existed.
    //
    if (command.templateId == null &&
        command.command == template.command &&
        command.executionMode == template.executionMode) {
      return true;
    }

    return false;
  }

  bool _deviceHasTemplate(RemoteCommand template) {
    return _device.commands.any(
      (command) => _commandMatchesTemplate(command, template),
    );
  }

  Future<void> _openTerminal() async {
    final connected = _session.isConnected && _session.deviceId == _device.id;

    if (!connected) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(device: _device, session: _session),
      ),
    );

    //
    // Returning from TerminalScreen no
    // longer closes the terminal shell.
    //
    // This simply verifies the underlying
    // SSH transport.
    //
    await _session.healthCheck();

    if (mounted) {
      setState(() {});
      await _refreshStatefulStatuses();
    }
  }

  Future<void> _duplicateCommand(RemoteCommand command) async {
    final duplicate = cloneCommand(command, _device.commands, rename: true);
    final commands = [..._device.commands];
    final index = commands.indexWhere((item) => item.id == command.id);
    commands.insert(index + 1, duplicate);
    await _storeCommands(commands);
  }

  Future<void> _storeCommands(List<RemoteCommand> commands) async {
    final updatedDevice = _device.copyWith(commands: commands);
    try {
      await widget.onDeviceUpdated(updatedDevice);
      if (!mounted) return;
      setState(() => _device = updatedDevice);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save command. Please try again.'),
        ),
      );
    }
  }

  Future<void> _copyCommand(RemoteCommand command) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: encodeCommandTransfer(command)),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Command copied. Open another device and choose Paste command.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy command. Please try again.'),
        ),
      );
    }
  }

  Future<void> _pasteCommand() async {
    RemoteCommand copied;
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      copied = decodeCommandTransfer(clipboard?.text ?? '');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard does not contain a valid copied command.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final command = await Navigator.of(context).push<RemoteCommand>(
      MaterialPageRoute(
        builder: (_) => AddCommandScreen(
          initialCommand: cloneCommand(copied, _device.commands),
          shellStyle: _device.shellStyle,
          session: _session,
        ),
      ),
    );
    if (!mounted || command == null) return;
    await _storeCommands([..._device.commands, command]);
  }

  Future<void> _addCommand() async {
    final defaults = defaultCommandsFor(_device.shellStyle);

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Custom command'),
                subtitle: const Text('Create a command from scratch'),
                onTap: () {
                  Navigator.pop(bottomSheetContext, '__custom__');
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('Paste command'),
                subtitle: const Text(
                  'Use a command copied from another device',
                ),
                onTap: () => Navigator.pop(bottomSheetContext, '__paste__'),
              ),
              if (defaults.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Text(
                    'Default commands',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final template in defaults)
                  ListTile(
                    leading: Icon(commandIcon(template.icon)),
                    title: Text(template.name),
                    subtitle: Text(
                      template.parameters.isEmpty
                          ? template.category
                          : '${template.category} • '
                                '${template.parameters.length} '
                                'parameter'
                                '${template.parameters.length == 1 ? '' : 's'}',
                    ),
                    trailing: _deviceHasTemplate(template)
                        ? const Icon(Icons.check)
                        : null,
                    enabled: !_deviceHasTemplate(template),
                    onTap: _deviceHasTemplate(template)
                        ? null
                        : () {
                            Navigator.pop(bottomSheetContext, template.id);
                          },
                  ),
              ],
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == '__paste__') {
      await _pasteCommand();
      return;
    }

    RemoteCommand? command;

    if (choice == '__custom__') {
      command = await Navigator.of(context).push<RemoteCommand>(
        MaterialPageRoute(
          builder: (_) => AddCommandScreen(
            shellStyle: _device.shellStyle,
            session: _session,
          ),
        ),
      );
    } else {
      RemoteCommand? template;

      for (final item in defaults) {
        if (item.id == choice) {
          template = item;
          break;
        }
      }

      if (template == null) {
        return;
      }

      command = await Navigator.of(context).push<RemoteCommand>(
        MaterialPageRoute(
          builder: (_) => AddCommandScreen(
            template: template,
            shellStyle: _device.shellStyle,
            session: _session,
          ),
        ),
      );
    }

    if (command == null) {
      return;
    }

    final updatedDevice = _device.copyWith(
      commands: [..._device.commands, command],
    );

    await widget.onDeviceUpdated(updatedDevice);

    if (!mounted) {
      return;
    }

    setState(() {
      _device = updatedDevice;
    });

    if (command.isStateful && mounted) {
      await _statefulControls.refreshCommand(
        context: context,
        command: command,
      );
    }
  }

  Future<void> _editCommand(RemoteCommand command) async {
    final updated = await Navigator.of(context).push<RemoteCommand>(
      MaterialPageRoute(
        builder: (_) => AddCommandScreen(
          command: command,
          shellStyle: _device.shellStyle,
          session: _session,
        ),
      ),
    );

    if (updated == null) {
      return;
    }

    final commands = _device.commands
        .map((item) => item.id == command.id ? updated : item)
        .toList();

    final updatedDevice = _device.copyWith(commands: commands);

    await widget.onDeviceUpdated(updatedDevice);

    if (!mounted) {
      return;
    }

    setState(() {
      _device = updatedDevice;
    });

    _statefulControls.removeCommand(command.id);

    if (updated.isStateful && mounted) {
      await _statefulControls.refreshCommand(
        context: context,
        command: updated,
      );
    }
  }

  Future<void> _editStatefulTarget(RemoteCommand command) async {
    final config = command.stateful;

    final target = config?.target;

    if (config == null ||
        target == null ||
        _updatingTargetCommandIds.contains(command.id)) {
      return;
    }

    var value = target.value;

    final updatedValue = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final trimmed = value.trim();

            return AlertDialog(
              title: Text(target.label),
              content: TextFormField(
                initialValue: target.value,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: target.label),
                onChanged: (newValue) {
                  setDialogState(() {
                    value = newValue;
                  });
                },
                onFieldSubmitted: (_) {
                  if (trimmed.isEmpty) {
                    return;
                  }

                  Navigator.pop(dialogContext, trimmed);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: trimmed.isEmpty
                      ? null
                      : () {
                          Navigator.pop(dialogContext, trimmed);
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || updatedValue == null || updatedValue == target.value) {
      return;
    }

    setState(() {
      _updatingTargetCommandIds.add(command.id);
    });

    final updatedCommand = command.copyWith(
      stateful: config.copyWith(target: target.copyWith(value: updatedValue)),
    );

    final updatedDevice = _device.copyWith(
      commands: _device.commands
          .map((item) => item.id == command.id ? updatedCommand : item)
          .toList(),
    );

    try {
      await widget.onDeviceUpdated(updatedDevice);

      if (!mounted) {
        return;
      }

      setState(() {
        _device = updatedDevice;

        _status =
            '${target.label} updated to '
            '$updatedValue.';
      });

      //
      // Throw away the old cached status first.
      //
      _statefulControls.removeCommand(command.id);

      //
      // Immediately resolve the state using the
      // newly saved target.
      //
      await _statefulControls.refreshCommand(
        context: context,
        command: updatedCommand,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status =
            'Could not update '
            '${target.label}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingTargetCommandIds.remove(command.id);
        });
      }
    }
  }

  Future<void> _deleteCommand(RemoteCommand command) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Command'),
          content: Text('Delete "${command.name}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final updatedDevice = _device.copyWith(
      commands: _device.commands
          .where((item) => item.id != command.id)
          .toList(),
    );

    await widget.onDeviceUpdated(updatedDevice);

    if (!mounted) {
      return;
    }

    setState(() {
      _device = updatedDevice;
    });

    _statefulControls.removeCommand(command.id);
  }

  Future<void> _runCommand(
    RemoteCommand command,
    Map<String, String> values,
  ) async {
    final connected = _session.isConnected && _session.deviceId == _device.id;

    if (!connected) {
      setState(() {
        _status = 'Disconnected';
      });

      return;
    }

    final commandText = renderCommandTemplate(command.command, command, values);

    final verificationText = command.verificationCommand == null
        ? null
        : renderCommandTemplate(command.verificationCommand!, command, values);

    setState(() {
      _busy = true;

      _status = 'Running ${command.name}...';
    });

    try {
      //
      // Handles both ordinary and sudo
      // command execution.
      //
      // The important multi-device change is
      // that the exact SshSession belonging to
      // this ControlsScreen is supplied.
      //
      final result = await runCommandWithPrivileges(
        context: context,
        command: command,
        commandText: commandText,
        session: _session,
      );

      if (!mounted) {
        return;
      }

      //
      // null means the user cancelled the
      // sudo-password dialog.
      //
      if (result == null) {
        setState(() {
          _status = 'Cancelled.';
        });

        return;
      }

      final output = utf8.decode(result, allowMalformed: true).trim();

      //
      // No verification command.
      //
      if (verificationText == null || verificationText.trim().isEmpty) {
        setState(() {
          _status = output.isEmpty ? '${command.name} command sent' : output;
        });

        return;
      }

      //
      // Give asynchronous commands a short
      // moment before checking their result.
      //
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) {
        return;
      }

      //
      // Verification also has to use this
      // device's SSH session rather than the
      // old global singleton.
      //
      final verificationResult = await runCommandWithPrivileges(
        context: context,
        command: command,
        commandText: verificationText,
        session: _session,
      );

      if (!mounted) {
        return;
      }

      if (verificationResult == null) {
        setState(() {
          _status = 'Cancelled.';
        });

        return;
      }

      final verificationOutput = utf8
          .decode(verificationResult, allowMalformed: true)
          .trim();

      final expected = command.expectedOutput?.trim();

      if (expected == null || expected.isEmpty) {
        setState(() {
          _status = verificationOutput.isEmpty
              ? '${command.name} '
                    'verification completed'
              : verificationOutput;
        });

        return;
      }

      if (verificationOutput.contains(expected)) {
        setState(() {
          _status = '✓ ${command.name} verified';

          if (verificationOutput.isNotEmpty) {
            _status =
                '✓ ${command.name} verified\n'
                '$verificationOutput';
          }
        });
      } else {
        setState(() {
          _status =
              '✗ ${command.name} verification failed\n'
              'Expected: $expected\n'
              'Received: '
              '$verificationOutput';
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = e is TimeoutException
            ? 'Timed out. The command may still have completed; check the device before retrying.'
            : _session.isConnected
            ? 'Error: $e'
            : 'Disconnected: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _handleCommand(RemoteCommand command) async {
    final wakeTemplate = linuxDefaultCommands.firstWhere(
      (item) => item.id == 'linux_wake_pc',
    );
    if (_isLinuxDevice &&
        _commandMatchesTemplate(command, wakeTemplate) &&
        command.command == wakeTemplate.command) {
      await _handleDeviceTool('network_health');
      return;
    }
    final unknown = unknownCommandParameters(command);

    if (unknown.isNotEmpty) {
      setState(() {
        _status =
            'Undefined parameter(s): '
            '${unknown.map((key) => '{{param:$key}}').join(', ')}';
      });

      return;
    }

    //
    // Ask for runtime parameters first.
    //
    final values = await promptCommandParameters(context, command);

    if (!mounted || values == null) {
      return;
    }

    final rendered = renderCommandTemplate(command.command, command, values);

    //
    // Confirmation happens after parameters
    // are resolved so the user can see the
    // exact command that will run.
    //
    final userCommand = _isUserSavedCommand(command);
    final windowsAdmin = userCommand && _device.shellStyle == 'windows'
        ? await _windowsAccountIsAdmin()
        : null;
    if (!mounted) return;
    if (command.requiresUserConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(command.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  userCommand
                      ? 'Review this saved command before running it.'
                      : 'Are you sure you want to run this command?',
                ),
                if (userCommand && _device.shellStyle == 'windows') ...[
                  const SizedBox(height: 10),
                  Text(_accountPermissionsMessage(windowsAdmin)),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    rendered,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                if (command.requiresSudo) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text('This command will run with sudo.')),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Run'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    await _runCommand(command, values);
  }

  Future<void> _handleStatefulState(
    RemoteCommand command,
    StatefulCommandState state,
  ) async {
    final connected = _session.isConnected && _session.deviceId == _device.id;

    if (!connected) {
      setState(() {
        _status = 'Disconnected';
      });

      return;
    }

    final userCommand = _isUserSavedCommand(command);
    final windowsAdmin = userCommand && _device.shellStyle == 'windows'
        ? await _windowsAccountIsAdmin()
        : null;
    if (!mounted) return;
    if (command.requiresUserConfirmation) {
      final rendered = renderStatefulCommand(
        command: command,
        template: state.command,
      );

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              '${command.name}: '
              '${state.label}',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Are you sure you want '
                  'to switch to this state?',
                ),
                if (userCommand && _device.shellStyle == 'windows') ...[
                  const SizedBox(height: 10),
                  Text(_accountPermissionsMessage(windowsAdmin)),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    rendered,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                if (command.requiresSudo) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This command will '
                          'run with sudo.',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Run'),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmed != true) {
        return;
      }
    }

    final result = await _statefulControls.runState(
      context: context,
      command: command,
      state: state,
    );

    if (!mounted) {
      return;
    }

    switch (result.outcome) {
      case StatefulStateRunOutcome.success:
        setState(() {
          if (result.output != null && result.output!.trim().isNotEmpty) {
            _status = result.output!.trim();
          } else if (command.hasStateCheck) {
            _status =
                '${command.name}: '
                '${state.label} command sent '
                'and status refreshed.';
          } else {
            _status =
                '${command.name}: '
                '${state.label} command sent.';
          }
        });

        break;

      case StatefulStateRunOutcome.cancelled:
        setState(() {
          _status = 'Cancelled.';
        });

        break;

      case StatefulStateRunOutcome.busy:
        break;

      case StatefulStateRunOutcome.failed:
        setState(() {
          _status = result.message ?? 'State change failed.';
        });

        break;
    }
  }

  void _disconnect() {
    //
    // Only this device's SSH connection is
    // disconnected.
    //
    // Other managed sessions remain alive.
    //
    _session.disconnect();
    if (mounted) {
      setState(() {
        _lostConnection = false;
      });
    }
  }

  Future<void> _handleDeviceTool(String tool) async {
    // A connection can close while the tools menu is open.
    const remoteTools = {
      'terminal',
      'keyboard',
      'files',
      'screenshot',
      'media',
      'text_size',
      'network_health',
      'bluetooth',
      'disconnect',
    };
    if (remoteTools.contains(tool) &&
        (!_session.isConnected || _session.deviceId != _device.id)) {
      return;
    }

    switch (tool) {
      case 'add':
        await _addCommand();
        return;
      case 'paste':
        await _pasteCommand();
        return;
      case 'disconnect':
        _disconnect();
        return;
      case 'connect':
      case 'reconnect':
        await _connectFromHome();
        return;
      case 'terminal':
        await _openTerminal();
        return;
      default:
        final Widget screen;
        switch (tool) {
          case 'information':
            screen = DeviceInformationScreen(
              device: _device,
              session: _session,
            );
          case 'bluetooth':
            screen = BluetoothDevicesScreen(device: _device, session: _session);
          case 'performance':
            screen = PerformanceScreen(session: _session);
          case 'text_size':
            if (_device.shellStyle != 'windows') return;
            screen = WindowsTextSizeScreen(session: _session);
          case 'files':
            screen = SftpScreen(
              device: _device,
              session: _session,
              peerDevices: widget.peerDevices,
            );
          case 'screenshot':
            screen = RemoteScreenshotScreen(device: _device, session: _session);
          case 'desktop':
            screen = RemoteDesktopScreen(device: _device, session: _session);
          case 'keyboard':
            screen = RemoteKeyboardScreen(device: _device, session: _session);
          case 'media':
            screen = RemoteMediaScreen(device: _device, session: _session);
          case 'network_health':
            if (!_isLinuxDevice) return;
            screen = LinuxHealthScreen(
              device: _device,
              session: _session,
              peerDevices: widget.peerDevices,
              onOpenPeer: widget.onOpenPeer,
            );
          default:
            return;
        }
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => screen));
    }
  }

  Widget _buildCommandItem(RemoteCommand command, bool connected) {
    if (command.isStateful) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: StatefulCommandItem(
          command: command,
          status: _statefulControls.statusFor(command),
          checkedAt: _statefulControls.checkedAt(command),
          refreshing: _statefulControls.isRefreshing(command),
          switching: _statefulControls.isRunning(command),
          onRefresh: () => _statefulControls.refreshCommand(
            context: context,
            command: command,
          ),
          connected: connected,
          busy:
              _busy ||
              _updatingTargetCommandIds.contains(command.id) ||
              _statefulControls.isRunning(command),
          onStatePressed: (state) => _handleStatefulState(command, state),
          onEditTarget: command.stateful?.target == null
              ? null
              : () => _editStatefulTarget(command),
          onEdit: () {
            _editCommand(command);
          },
          onDelete: () {
            _deleteCommand(command);
          },
          onDuplicate: () => _duplicateCommand(command),
          onCopy: () => _copyCommand(command),
        ),
      );
    }

    return _buildActionCommandItem(command, connected);
  }

  Widget _buildActionCommandItem(RemoteCommand command, bool connected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: !_busy && connected
                    ? () => _handleCommand(command)
                    : null,
                icon: Icon(commandIcon(command.icon)),
                label: Text(command.name),
              ),
            ),
            const SizedBox(width: 8),
            CommandOptionsMenu(
              onEdit: () => _editCommand(command),
              onDuplicate: () => _duplicateCommand(command),
              onCopy: () => _copyCommand(command),
              onDelete: () => _deleteCommand(command),
            ),
          ],
        ),
        if (command.parameters.isNotEmpty || command.requiresSudo)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (command.parameters.isNotEmpty)
                  Text(
                    '${command.parameters.length} parameter'
                    '${command.parameters.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (command.requiresSudo)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'sudo',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCategoryHeader(
    BuildContext context,
    String category,
    int controlCount,
  ) {
    final icon = switch (category.toLowerCase()) {
      'display' => Icons.desktop_windows_outlined,
      'network' || 'network & devices' => Icons.lan_outlined,
      'power' || 'power controls' => Icons.power_settings_new,
      'system' => Icons.settings_outlined,
      _ => Icons.tune,
    };
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$controlCount',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  bool _isPowerControl(RemoteCommand command) =>
      command.category.trim().toLowerCase() == 'power';

  bool get _isLinuxDevice =>
      _device.shellStyle == 'linux' ||
      _device.commands.any(
        (command) =>
            command.templateId?.startsWith('linux_') == true ||
            command.id.startsWith('linux_'),
      );

  Widget _homeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap,
    String? trailing,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) ...[
                Text(trailing, style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceHome(BuildContext context, bool connected) {
    final route = _session.connectionRoute;
    final stateText = connected
        ? 'Connected${route == null ? '' : ' · $route'}'
        : _connecting
        ? 'Connecting…'
        : 'Disconnected';
    final connectLabel = connected
        ? null
        : (_lostConnection ? 'Reconnect' : 'Connect');
    final stateColor = connected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final statefulCount = _device.commands.where((c) => c.isStateful).length;
    final commandCount = _device.commands
        .where((c) => !c.isStateful && !_isPowerControl(c))
        .length;
    final tools = <({String action, String title, IconData icon})>[
      (action: 'terminal', title: 'Terminal', icon: Icons.terminal),
      (
        action: 'keyboard',
        title: 'Remote keyboard',
        icon: Icons.keyboard_outlined,
      ),
      (action: 'files', title: 'Files · SFTP', icon: Icons.folder_outlined),
      (
        action: 'screenshot',
        title: 'Screenshot',
        icon: Icons.screenshot_monitor,
      ),
      (
        action: 'desktop',
        title: 'Live desktop',
        icon: Icons.desktop_windows_outlined,
      ),
      (
        action: 'media',
        title: 'Camera & microphone',
        icon: Icons.videocam_outlined,
      ),
      (action: 'bluetooth', title: 'Bluetooth devices', icon: Icons.bluetooth),
      if (_device.shellStyle == 'windows')
        (
          action: 'text_size',
          title: 'Windows text size',
          icon: Icons.text_fields,
        ),
      if (_isLinuxDevice)
        (
          action: 'network_health',
          title: 'Network & Pi health',
          icon: Icons.health_and_safety_outlined,
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const AppUpdateBanner(),
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 13,
                      color: connected ? Colors.green : stateColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stateText,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (connected && _session.connectedHost != null)
                            Text(
                              'Using ${_session.connectedHost}:${_device.port}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Text(
                            'Saved LAN: ${_device.localHost.isEmpty ? 'Not configured' : _device.localHost}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (!connected && !_connecting)
                            Text(
                              'Saved settings remain available while offline.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (_connecting || _findingLanAddress)
                      const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                  ],
                ),
                if (!connected) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (connectLabel != null)
                        FilledButton.tonal(
                          onPressed: _busy || _connecting
                              ? null
                              : _connectFromHome,
                          child: Text(connectLabel),
                        ),
                      OutlinedButton.icon(
                        onPressed: _findingLanAddress || _connecting
                            ? null
                            : _findDeviceOnLan,
                        icon: const Icon(Icons.wifi_find),
                        label: Text(
                          _findingLanAddress ? 'Searching…' : 'Find on LAN',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Text('Remote tools', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tool in tools)
                  SizedBox(
                    width: tileWidth,
                    child: _toolTile(
                      context,
                      tool.action,
                      tool.title,
                      tool.icon,
                      connected,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _homeCard(
          context: context,
          title: 'Control panel',
          subtitle: 'Display, network and power controls',
          icon: Icons.tune,
          trailing:
              '${statefulCount + _device.commands.where(_isPowerControl).length}',
          onTap: () {
            setState(() => _view = 'controls');
            if (connected) unawaited(_refreshStatefulStatuses());
          },
        ),
        _homeCard(
          context: context,
          title: 'Commands',
          subtitle: 'Custom actions and system commands',
          icon: Icons.terminal,
          trailing: '$commandCount',
          onTap: () => setState(() => _view = 'commands'),
        ),
      ],
    );
  }

  Widget _toolTile(
    BuildContext context,
    String action,
    String title,
    IconData icon,
    bool connected,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: connected ? () => _handleDeviceTool(action) : null,
        child: SizedBox(
          height: 104,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: connected
                      ? theme.colorScheme.onSurface
                      : theme.disabledColor,
                ),
                const SizedBox(height: 8),
                Text(title, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, bool connected) {
    final categories = <String, List<RemoteCommand>>{};
    for (final command in _device.commands.where(
      (item) => item.isStateful && !_isPowerControl(item),
    )) {
      categories.putIfAbsent(command.category, () => []).add(command);
    }
    final powerCommands = _device.commands.where(_isPowerControl).toList();
    return RefreshIndicator(
      onRefresh: () => _refreshStatefulStatuses(allowPrompt: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          for (final entry in categories.entries) ...[
            _buildCategoryHeader(
              context,
              entry.key.toLowerCase() == 'network'
                  ? 'Network & devices'
                  : entry.key,
              entry.value.length,
            ),
            for (final command in entry.value)
              _buildCommandItem(command, connected),
          ],
          if (powerCommands.isNotEmpty) ...[
            _buildCategoryHeader(
              context,
              'Power controls',
              powerCommands.length,
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final width = (constraints.maxWidth - gap * 2) / 3;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final command in powerCommands)
                          SizedBox(
                            width: width,
                            child: _buildPowerControl(command, connected),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_status != null && !_busy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_status!, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  Widget _buildPowerControl(RemoteCommand command, bool connected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: command.name,
          onPressed: !_busy && connected ? () => _handleCommand(command) : null,
          icon: Icon(commandIcon(command.icon)),
        ),
        Text(
          command.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SizedBox(
          height: 34,
          child: CommandOptionsMenu(
            onEdit: () => _editCommand(command),
            onDuplicate: () => _duplicateCommand(command),
            onCopy: () => _copyCommand(command),
            onDelete: () => _deleteCommand(command),
          ),
        ),
      ],
    );
  }

  Widget _buildCommands(BuildContext context, bool connected) {
    final categories = <String, List<RemoteCommand>>{};
    for (final command in _device.commands.where(
      (item) => !item.isStateful && !_isPowerControl(item),
    )) {
      categories.putIfAbsent(command.category, () => []).add(command);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Text('Commands', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Custom actions for this device.'),
        const SizedBox(height: 14),
        if (categories.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No custom commands yet. Add a command from the menu.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        for (final entry in categories.entries) ...[
          _buildCategoryHeader(context, entry.key, entry.value.length),
          for (final command in entry.value)
            _buildCommandItem(command, connected),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_status != null && !_busy)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(_status!, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      //
      // Rebuild only when THIS device's
      // session changes.
      //
      animation: _session,
      builder: (context, _) {
        final connected =
            _session.isConnected && _session.deviceId == _device.id;
        final title = switch (_view) {
          'controls' => 'Control panel',
          'commands' => 'Commands',
          _ => _device.name,
        };

        return PopScope(
          canPop: _view == 'home',
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _view != 'home') {
              setState(() => _view = 'home');
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: _view == 'home'
                  ? null
                  : IconButton(
                      tooltip: 'Back to ${_device.name}',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _view = 'home'),
                    ),
              title: Text(title),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Device menu',
                  onSelected: (value) => _handleDeviceTool(value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'information',
                      child: Text('Device information'),
                    ),
                    const PopupMenuItem(
                      value: 'performance',
                      child: Text('Performance & connection'),
                    ),
                    const PopupMenuDivider(),
                    if (_view != 'commands')
                      const PopupMenuItem(
                        value: 'add',
                        child: Text('Add command'),
                      ),
                    const PopupMenuItem(
                      value: 'paste',
                      child: Text('Paste command'),
                    ),
                    if (connected)
                      const PopupMenuItem(
                        value: 'disconnect',
                        child: Text('Disconnect'),
                      ),
                  ],
                ),
              ],
            ),
            floatingActionButton: _view == 'commands'
                ? FloatingActionButton.extended(
                    onPressed: _addCommand,
                    icon: const Icon(Icons.add),
                    label: const Text('Add command'),
                  )
                : null,
            body: SafeArea(
              child: switch (_view) {
                'controls' => _buildControlPanel(context, connected),
                'commands' => _buildCommands(context, connected),
                _ => _buildDeviceHome(context, connected),
              },
            ),
          ),
        );
      },
    );
  }
}
