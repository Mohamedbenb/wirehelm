import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'add_command_screen.dart';
import '../commands/default_commands.dart';
import '../commands/command_options_menu.dart';
import '../models/device.dart';
import '../models/remote_command.dart';
import '../services/plasma_desktop_resume.dart';
import '../services/plasma_power.dart';
import '../services/plasma_settings.dart';
import '../services/smart_bulb.dart';
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
import 'remote_downloads_screen.dart';
import 'ota_preparation_screen.dart';
import 'windows_text_size_screen.dart';
import 'performance_screen.dart';
import 'remote_screenshot_screen.dart';
import 'remote_desktop_screen.dart';
import 'linux_health_screen.dart';
import 'plasma_display_screen.dart';
import 'plasma_text_size_screen.dart';
import 'smart_bulb_screen.dart';
import '../utils/command_icons.dart';
import '../utils/command_parameters.dart';
import '../utils/sudo_command.dart';
import '../utils/command_transfer.dart';
import '../widgets/app_update_banner.dart';
import '../widgets/edge_panel_control_toggle.dart';

enum _DeviceTab { tools, controls, commands }

class _DeviceTool {
  const _DeviceTool(
    this.action,
    this.title,
    this.icon, {
    this.needsConnection = true,
  });

  final String action;
  final String title;
  final IconData icon;
  final bool needsConnection;
}

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
  final Future<SshSession> Function(Device)? onConnectPeer;

  const ControlsScreen({
    super.key,
    required this.device,
    this.session,
    this.onConnect,
    this.autoConnectOnOpen = false,
    this.peerDevices = const [],
    this.onFindOnLan,
    this.onOpenPeer,
    this.onConnectPeer,
    required this.onDeviceUpdated,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _appActive = true;
  bool _wasConnected = false;
  bool _lostConnection = false;

  bool get _canRefreshStatuses =>
      mounted &&
      _appActive &&
      (ModalRoute.of(context)?.isCurrent ?? false) &&
      _tab == _DeviceTab.controls &&
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
  bool _unlockingPc = false;
  bool _findingLanAddress = false;
  late final TabController _tabs;
  _DeviceTab _tab = _DeviceTab.tools;
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
    _tabs = TabController(length: _DeviceTab.values.length, vsync: this)
      ..addListener(_onTabChanged);

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
    _tabs.dispose();
    _statefulControls.removeListener(_onStatefulControlsChanged);

    _statefulControls.dispose();

    super.dispose();
  }

  void _onTabChanged() {
    final tab = _DeviceTab.values[_tabs.index];
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (_canRefreshStatuses) unawaited(_refreshStatefulStatuses());
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
    final defaults = defaultCommandsFor(_device.commandProfile);

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

  Future<void> _unlockPc() async {
    if (_unlockingPc ||
        _busy ||
        _device.commandProfile != 'cachyos' ||
        !_session.isConnected ||
        _session.deviceId != _device.id) {
      return;
    }
    setState(() => _unlockingPc = true);
    bool cancelled() => !mounted || ModalRoute.of(context)?.isCurrent != true;
    try {
      final outcome = await preparePlasmaDesktop(
        device: _device,
        session: _session,
        cancelled: cancelled,
      );
      if (mounted && !cancelled()) {
        final message = switch (outcome) {
          PlasmaDesktopPreparation.ready => 'PC is unlocked. Display is awake.',
          PlasmaDesktopPreparation.displayUnconfirmed =>
            'PC is unlocked. Display wake could not be confirmed.',
          PlasmaDesktopPreparation.cancelled => 'PC unlock canceled.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted && !cancelled()) {
        final message = error is StateError ? error.message : '$error';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _unlockingPc = false);
    }
  }

  Future<void> _handleDeviceTool(String tool) async {
    // A connection can close while the tools menu is open.
    const remoteTools = {
      'terminal',
      'desktop',
      'keyboard',
      'files',
      'remote_downloads',
      'ota_preparation',
      'screenshot',
      'media',
      'text_size',
      'plasma_display',
      'smart_bulb',
      'network_health',
      'bluetooth',
    };
    if (remoteTools.contains(tool) &&
        (!_session.isConnected || _session.deviceId != _device.id)) {
      return;
    }

    switch (tool) {
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
            if (_device.commandProfile == 'cachyos') {
              screen = PlasmaTextSizeScreen(
                settings: PlasmaSettings(_device, _session),
              );
            } else if (_device.shellStyle == 'windows') {
              screen = WindowsTextSizeScreen(session: _session);
            } else {
              return;
            }
          case 'plasma_display':
            if (_device.commandProfile != 'cachyos') return;
            screen = PlasmaDisplayScreen(
              settings: PlasmaSettings(_device, _session),
            );
          case 'files':
            screen = SftpScreen(
              device: _device,
              session: _session,
              peerDevices: widget.peerDevices,
            );
          case 'remote_downloads':
            screen = RemoteDownloadsScreen(
              device: _device,
              session: _session,
              peerDevices: widget.peerDevices,
            );
          case 'ota_preparation':
            screen = OtaPreparationScreen(device: _device, session: _session);
          case 'screenshot':
            screen = RemoteScreenshotScreen(device: _device, session: _session);
          case 'desktop':
            screen = RemoteDesktopScreen(device: _device, session: _session);
          case 'keyboard':
            screen = RemoteKeyboardScreen(device: _device, session: _session);
          case 'media':
            screen = RemoteMediaScreen(device: _device, session: _session);
          case 'smart_bulb':
            if (!_isLinuxDevice) return;
            screen = SmartBulbScreen(bulb: SmartBulb(_device, _session));
          case 'network_health':
            if (!_isLinuxDevice) return;
            screen = LinuxHealthScreen(
              device: _device,
              session: _session,
              peerDevices: widget.peerDevices,
              onOpenPeer: widget.onOpenPeer,
              onConnectPeer: widget.onConnectPeer,
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

  Iterable<RemoteCommand> get _savedPowerControls => _device.commands.where(
    (command) => _isPowerControl(command) && !_replacedByPlasmaPower(command),
  );

  bool _replacedByPlasmaPower(RemoteCommand command) {
    if (_device.commandProfile != 'cachyos' ||
        !command.requiresSudo ||
        !command.requiresConfirmation ||
        command.verificationCommand != null ||
        command.parameters.isNotEmpty) {
      return false;
    }
    return switch ((command.templateId, command.name, command.command)) {
      ('linux_suspend', 'Suspend', 'systemctl suspend') ||
      ('linux_restart', 'Restart', 'systemctl reboot') ||
      ('linux_shutdown', 'Shutdown', 'systemctl poweroff') => true,
      _ => false,
    };
  }

  Future<void> _runPlasmaPower(PlasmaPowerAction action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final accepted = await requestPlasmaPower(
        context,
        device: _device,
        session: _session,
        action: action,
      );
      if (mounted && accepted) {
        setState(() => _status = '${action.label} requested.');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is StateError ? error.message : '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isLinuxDevice =>
      _device.shellStyle == 'linux' ||
      _device.commands.any(
        (command) =>
            command.templateId?.startsWith('linux_') == true ||
            command.id.startsWith('linux_'),
      );

  Widget _buildConnectionBar(BuildContext context, bool connected) {
    final theme = Theme.of(context);
    final route = _session.connectionRoute;
    final working = _connecting || _findingLanAddress;
    final status = connected
        ? (route == null ? 'Connected' : 'Connected · $route')
        : _connecting
        ? 'Connecting…'
        : _findingLanAddress
        ? 'Searching on LAN…'
        : 'Disconnected';
    final host = connected ? _session.connectedHost : _device.localHost;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        child: Row(
          children: [
            if (working)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                connected ? Icons.check_circle_outline : Icons.link_off,
                color: connected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: theme.textTheme.titleSmall),
                  if (host != null && host.isNotEmpty)
                    Text(
                      connected ? host : 'Saved LAN · $host',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (connected)
              IconButton(
                tooltip: 'Disconnect',
                onPressed: _disconnect,
                icon: const Icon(Icons.logout),
              )
            else ...[
              FilledButton.tonal(
                onPressed: working || _busy || widget.onConnect == null
                    ? null
                    : _connectFromHome,
                child: Text(_lostConnection ? 'Reconnect' : 'Connect'),
              ),
              if (widget.onFindOnLan != null)
                IconButton(
                  tooltip: 'Find on LAN',
                  onPressed: working ? null : _findDeviceOnLan,
                  icon: const Icon(Icons.wifi_find),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolGroup(
    BuildContext context,
    String title,
    List<_DeviceTool> tools,
    bool connected,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < tools.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 56, endIndent: 16),
                _buildToolRow(tools[index], connected),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildToolRow(_DeviceTool tool, bool connected) {
    final enabled = !tool.needsConnection || connected;
    return ListTile(
      enabled: enabled,
      leading: Icon(tool.icon),
      title: Text(tool.title),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? () => _handleDeviceTool(tool.action) : null,
    );
  }

  Widget _buildDeviceTools(BuildContext context, bool connected) {
    final cachyos = _device.commandProfile == 'cachyos';
    return ListView(
      key: const PageStorageKey<String>('device-tools'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      children: [
        const AppUpdateBanner(),
        _buildToolGroup(context, 'Remote access', [
          const _DeviceTool(
            'desktop',
            'Live desktop',
            Icons.desktop_windows_outlined,
          ),
          const _DeviceTool(
            'keyboard',
            'Remote keyboard',
            Icons.keyboard_outlined,
          ),
          const _DeviceTool('terminal', 'Terminal', Icons.terminal),
        ], connected),
        _buildToolGroup(context, 'Files & updates', const [
          _DeviceTool('files', 'Files · SFTP', Icons.folder_outlined),
          _DeviceTool(
            'remote_downloads',
            'Remote downloads',
            Icons.download_outlined,
          ),
          _DeviceTool('ota_preparation', 'Prepare rooted OTA', Icons.security),
        ], connected),
        _buildToolGroup(context, 'Media', const [
          _DeviceTool('screenshot', 'Screenshot', Icons.screenshot_monitor),
          _DeviceTool('media', 'Camera & microphone', Icons.videocam_outlined),
        ], connected),
        _buildToolGroup(context, 'Device & network', [
          if (_isLinuxDevice)
            _DeviceTool(
              'network_health',
              cachyos ? 'Network & system health' : 'Network & Pi health',
              Icons.health_and_safety_outlined,
            ),
          const _DeviceTool(
            'information',
            'Device information',
            Icons.info_outline,
            needsConnection: false,
          ),
          const _DeviceTool(
            'performance',
            'Performance & connection',
            Icons.speed,
            needsConnection: false,
          ),
        ], connected),
      ],
    );
  }

  Widget _buildControlPanel(BuildContext context, bool connected) {
    final categories = <String, List<RemoteCommand>>{};
    for (final command in _device.commands.where(
      (item) => item.isStateful && !_isPowerControl(item),
    )) {
      categories.putIfAbsent(command.category, () => []).add(command);
    }
    final powerCommands = _savedPowerControls.toList();
    final cachyos = _device.commandProfile == 'cachyos';
    final windows = _device.shellStyle == 'windows';
    final plasmaPower = cachyos
        ? PlasmaPowerAction.values
        : const <PlasmaPowerAction>[];
    final canUsePower = connected && !_busy && !_unlockingPc;
    return RefreshIndicator(
      onRefresh: () => _refreshStatefulStatuses(allowPrompt: true),
      child: ListView(
        key: const PageStorageKey<String>('device-controls'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (powerCommands.isNotEmpty || plasmaPower.isNotEmpty) ...[
            _buildCategoryHeader(
              context,
              'Power controls',
              powerCommands.length + plasmaPower.length + (cachyos ? 1 : 0),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 8.0;
                        final width = (constraints.maxWidth - gap * 2) / 3;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final action in plasmaPower) ...[
                              SizedBox(
                                width: width,
                                child: _buildPowerButton(
                                  action.label,
                                  action.icon,
                                  canUsePower
                                      ? () => _runPlasmaPower(action)
                                      : null,
                                ),
                              ),
                              if (action == PlasmaPowerAction.lock)
                                SizedBox(
                                  width: width,
                                  child: _buildPowerButton(
                                    _unlockingPc
                                        ? 'Unlocking PC…'
                                        : 'Unlock PC',
                                    Icons.lock_open_outlined,
                                    canUsePower ? _unlockPc : null,
                                  ),
                                ),
                            ],
                            for (final command in powerCommands)
                              SizedBox(
                                width: width,
                                child: _buildPowerControl(
                                  command,
                                  connected && !_unlockingPc,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (cachyos)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: EdgePanelControlToggle(
                        control: EdgePanelControl.power,
                        deviceId: _device.id,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (windows || cachyos)
            _buildToolGroup(context, 'Display', [
              if (cachyos)
                const _DeviceTool(
                  'plasma_display',
                  'Display configuration',
                  Icons.display_settings_outlined,
                ),
              _DeviceTool(
                'text_size',
                windows ? 'Windows text size' : 'Plasma text size',
                Icons.text_fields,
              ),
            ], connected),
          _buildToolGroup(context, 'Accessories', [
            const _DeviceTool(
              'bluetooth',
              'Bluetooth devices',
              Icons.bluetooth,
            ),
            if (_isLinuxDevice)
              const _DeviceTool(
                'smart_bulb',
                'Smart bulb',
                Icons.lightbulb_outline,
              ),
          ], connected),
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

  Widget _buildPowerButton(
    String label,
    IconData icon,
    VoidCallback? pressed,
  ) => Column(
    children: [
      IconButton.filledTonal(
        tooltip: label,
        onPressed: pressed,
        icon: Icon(icon),
      ),
      Text(label, textAlign: TextAlign.center),
    ],
  );

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
      key: const PageStorageKey<String>('device-commands'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: _addCommand,
              icon: const Icon(Icons.add),
              label: const Text('Add command'),
            ),
            OutlinedButton.icon(
              onPressed: _pasteCommand,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste command'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No saved commands yet.',
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
        return PopScope(
          canPop: _tab == _DeviceTab.tools,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _tab != _DeviceTab.tools) {
              _tabs.animateTo(_DeviceTab.tools.index);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: _tab == _DeviceTab.tools
                  ? null
                  : BackButton(
                      onPressed: () => _tabs.animateTo(_DeviceTab.tools.index),
                    ),
              title: Text(_device.name, overflow: TextOverflow.ellipsis),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _buildConnectionBar(context, connected),
                  TabBar(
                    controller: _tabs,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: const [
                      Tab(text: 'Tools'),
                      Tab(text: 'Controls'),
                      Tab(text: 'Commands'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _buildDeviceTools(context, connected),
                        _buildControlPanel(context, connected),
                        _buildCommands(context, connected),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
