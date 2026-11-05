import 'package:flutter/material.dart';

import '../command_editor/action/action_command_editor.dart';
import '../command_editor/action/action_command_tester.dart';
import '../command_editor/action/action_parameter_controller.dart';
import '../command_editor/command_builders.dart';
import '../command_editor/command_editor_sections.dart';
import '../command_editor/stateful/state_editor_dialog.dart';
import '../command_editor/stateful/stateful_command_validation.dart';
import '../command_editor/stateful/stateful_execution_section.dart';
import '../command_editor/stateful/stateful_states_section.dart';
import '../command_editor/stateful/stateful_status_section.dart';
import '../command_editor/stateful/stateful_target_section.dart';
import '../models/remote_command.dart';
import '../utils/command_parameters.dart';
import '../ssh/ssh_session.dart';
import '../stateful/stateful_command_executor.dart';

class AddCommandScreen extends StatefulWidget {
  final RemoteCommand? command;
  final RemoteCommand? template;
  final RemoteCommand? initialCommand;
  final String shellStyle;
  final SshSession? session;

  const AddCommandScreen({
    super.key,
    this.command,
    this.template,
    this.initialCommand,
    this.shellStyle = 'auto',
    this.session,
  });

  @override
  State<AddCommandScreen> createState() => _AddCommandScreenState();
}

class _AddCommandScreenState extends State<AddCommandScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  late final TextEditingController _categoryController;

  late final TextEditingController _commandController;

  late final TextEditingController _verificationController;

  late final TextEditingController _expectedOutputController;

  late final TextEditingController _targetKeyController;

  late final TextEditingController _targetLabelController;

  late final TextEditingController _targetValueController;

  late final TextEditingController _statusCommandController;

  late String _selectedIcon;
  late String _executionMode;
  late String _commandType;
  late String _statusExecutionMode;

  late bool _requiresConfirmation;
  late bool _requiresSudo;
  late bool _targetEnabled;

  late List<CommandParameter> _parameters;

  late List<StatefulCommandState> _states;

  bool _testing = false;
  bool _dirty = false;

  String? _testResult;

  bool get _editing => widget.command != null;

  bool get _isStateful => _commandType == 'stateful';

  @override
  void initState() {
    super.initState();

    final source = widget.command ?? widget.initialCommand ?? widget.template;

    final stateful = source?.stateful;

    _commandType = stateful == null ? 'action' : 'stateful';

    _nameController = TextEditingController(text: source?.name ?? '');

    _categoryController = TextEditingController(
      text: source?.category ?? 'Custom',
    );

    _commandController = TextEditingController(text: source?.command ?? '');

    _verificationController = TextEditingController(
      text: source?.verificationCommand ?? '',
    );

    _expectedOutputController = TextEditingController(
      text: source?.expectedOutput ?? '',
    );

    _targetEnabled = stateful?.target != null;

    _targetKeyController = TextEditingController(
      text: stateful?.target?.key ?? 'target',
    );

    _targetLabelController = TextEditingController(
      text: stateful?.target?.label ?? 'Target',
    );

    _targetValueController = TextEditingController(
      text: stateful?.target?.value ?? '',
    );

    _statusCommandController = TextEditingController(
      text: stateful?.statusCommand ?? '',
    );

    _selectedIcon = source?.icon ?? 'terminal';

    _requiresConfirmation = source?.requiresConfirmation ?? false;

    _requiresSudo = source?.requiresSudo ?? false;

    _executionMode = source?.executionMode ?? 'standard';
    _statusExecutionMode = stateful?.statusExecutionMode ?? 'standard';

    _parameters = [...?source?.parameters];

    _states = [...?stateful?.states];

    //
    // Linux cannot use the Windows interactive
    // desktop execution mode.
    //
    if (widget.shellStyle == 'linux' && _executionMode == 'interactive') {
      _executionMode = 'standard';
    }

    //
    // sudo is Linux-only.
    //
    if (widget.shellStyle != 'linux') {
      _requiresSudo = false;
    }

    _nameController.addListener(_markDirty);

    _categoryController.addListener(_markDirty);

    _commandController.addListener(_markDirty);

    _verificationController.addListener(_markDirty);

    _expectedOutputController.addListener(_markDirty);

    //
    // The target key is also displayed in
    // helper text, so it needs a rebuild.
    //
    _targetKeyController.addListener(_markDirtyAndRefresh);

    _targetLabelController.addListener(_markDirty);

    _targetValueController.addListener(_markDirty);

    _statusCommandController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);

    _categoryController.removeListener(_markDirty);

    _commandController.removeListener(_markDirty);

    _verificationController.removeListener(_markDirty);

    _expectedOutputController.removeListener(_markDirty);

    _targetKeyController.removeListener(_markDirtyAndRefresh);

    _targetLabelController.removeListener(_markDirty);

    _targetValueController.removeListener(_markDirty);

    _statusCommandController.removeListener(_markDirty);

    _nameController.dispose();
    _categoryController.dispose();
    _commandController.dispose();

    _verificationController.dispose();

    _expectedOutputController.dispose();

    _targetKeyController.dispose();
    _targetLabelController.dispose();
    _targetValueController.dispose();

    _statusCommandController.dispose();

    super.dispose();
  }

  void _markDirty() {
    if (_dirty) {
      return;
    }

    setState(() {
      _dirty = true;
    });
  }

  void _markDirtyAndRefresh() {
    if (!mounted) {
      return;
    }

    setState(() {
      _dirty = true;
    });
  }

  void _setCommandType(String value) {
    if (_commandType == value) {
      return;
    }

    setState(() {
      _commandType = value;

      _testResult = null;

      if (widget.shellStyle == 'linux') {
        _executionMode = 'standard';
      }

      _dirty = true;
    });
  }

  void _setIcon(String value) {
    if (value == _selectedIcon) {
      return;
    }

    setState(() {
      _selectedIcon = value;

      _dirty = true;
    });
  }

  void _setExecutionMode(String value) {
    if (value == _executionMode) {
      return;
    }

    setState(() {
      _executionMode = value;

      if (_executionMode != 'standard') {
        _requiresSudo = false;
      }

      _dirty = true;
    });
  }

  void _setRequiresSudo(bool value) {
    if (value == _requiresSudo) {
      return;
    }

    setState(() {
      _requiresSudo = value;

      if (_requiresSudo) {
        _executionMode = 'standard';
      }

      _dirty = true;
    });
  }

  RemoteCommand _buildActionCommand() {
    return buildActionCommand(
      existingCommand: widget.command ?? widget.initialCommand,

      template: widget.template,

      name: _nameController.text,

      category: _categoryController.text,

      command: _commandController.text,

      icon: _selectedIcon,

      requiresConfirmation: _requiresConfirmation,

      requiresSudo: widget.shellStyle == 'linux' ? _requiresSudo : false,

      executionMode: _executionMode,

      verificationCommand: _verificationController.text,

      expectedOutput: _expectedOutputController.text,

      parameters: _parameters,
    );
  }

  RemoteCommand _buildStatefulCommand() {
    return buildStatefulCommand(
      existingCommand: widget.command ?? widget.initialCommand,

      template: widget.template,

      name: _nameController.text,

      category: _categoryController.text,

      icon: _selectedIcon,

      requiresConfirmation: _requiresConfirmation,

      requiresSudo: widget.shellStyle == 'linux' ? _requiresSudo : false,

      executionMode: _executionMode,

      targetEnabled: _targetEnabled,

      targetKey: _targetKeyController.text,

      targetLabel: _targetLabelController.text,

      targetValue: _targetValueController.text,

      statusCommand: _statusCommandController.text,

      statusExecutionMode: _statusExecutionMode,

      states: _states,
    );
  }

  RemoteCommand _buildCurrentCommand() {
    return _isStateful ? _buildStatefulCommand() : _buildActionCommand();
  }

  Future<void> _testCommand() async {
    if (_isStateful || _testing) {
      return;
    }

    final command = _buildActionCommand();

    setState(() {
      _testing = true;

      _testResult = 'Running...';
    });

    final result = await testActionCommand(
      session: widget.session ?? sshSession,
      context: context,

      command: command,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _testing = false;

      _testResult = result;
    });
  }

  Future<void> _testStatefulStatus() async {
    if (!_isStateful || _testing) {
      return;
    }

    final statusText = _statusCommandController.text.trim();

    if (statusText.isEmpty) {
      return;
    }

    final session = widget.session ?? sshSession;

    if (!session.isConnected) {
      await _showValidationError('Status test', 'Not connected to the device.');

      return;
    }

    final command = _buildStatefulCommand();

    setState(() {
      _testing = true;
    });

    try {
      final result = await checkStatefulCommandStatus(
        context: context,
        command: command,
        session: session,
      );

      if (!mounted) {
        return;
      }

      final raw = result.rawValue?.trim();

      String? matchedLabel;

      final stateId = result.stateId;

      if (stateId != null) {
        for (final state in _states) {
          if (state.id == stateId) {
            matchedLabel = state.label;
            break;
          }
        }
      }

      final buffer = StringBuffer();

      if (raw != null && raw.isNotEmpty) {
        buffer.writeln('Raw output:');

        buffer.writeln(raw);
      } else {
        buffer.writeln('Raw output:');

        buffer.writeln('(empty)');
      }

      buffer.writeln();

      if (matchedLabel != null) {
        buffer.writeln('Matched state:');

        buffer.write(matchedLabel);
      } else if (result.error != null && result.error!.trim().isNotEmpty) {
        buffer.writeln('Result:');

        buffer.write(result.error!);
      } else {
        buffer.writeln('Matched state:');

        buffer.write('No configured state matched.');
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Status test'),

            content: SelectableText(buffer.toString()),

            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },

                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      await _showValidationError('Status test failed', e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  ActionParameterController _parameterController() {
    return ActionParameterController(
      context: context,

      commandController: _commandController,

      verificationController: _verificationController,

      parameters: _parameters,
    );
  }

  Future<void> _editParameter({CommandParameter? parameter, int? index}) async {
    final result = await _parameterController().editParameter(
      parameter: parameter,

      index: index,
    );

    if (!mounted || result == null) {
      return;
    }

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return;
    }

    setState(() {
      if (result.isNew) {
        _parameters.add(result.parameter);
      } else {
        _parameters[result.index!] = result.parameter;
      }

      _dirty = true;
    });
  }

  void _deleteParameter(int index) {
    _parameterController().removeParameter(index);

    setState(() {
      _parameters.removeAt(index);

      _dirty = true;
    });
  }

  Future<void> _editState({StatefulCommandState? state, int? index}) async {
    final result = await showStateEditorDialog(
      context: context,

      state: state,

      index: index,

      states: _states,

      targetEnabled: _targetEnabled,

      targetKey: _targetKeyController.text,
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      if (index == null) {
        _states.add(result);
      } else {
        _states[index] = result;
      }

      _dirty = true;
    });
  }

  void _duplicateState(int index) {
    final source = _states[index];

    String uniqueCopyValue(String value, Iterable<String> existingValues) {
      final used = existingValues
          .map((value) => value.trim().toLowerCase())
          .toSet();
      final base = '${value.trim()}_copy';
      var candidate = base;
      var suffix = 2;
      while (used.contains(candidate.toLowerCase())) {
        candidate = '${base}_${suffix++}';
      }
      return candidate;
    }

    final duplicate = source.copyWith(
      id: uniqueCopyValue(source.id, _states.map((state) => state.id)),
      label: '${source.label} (copy)',
      expectedStatus: uniqueCopyValue(
        source.expectedStatus,
        _states.map((state) => state.expectedStatus),
      ),
    );

    setState(() {
      _states.insert(index + 1, duplicate);
      _dirty = true;
    });
  }

  void _deleteState(int index) {
    setState(() {
      _states.removeAt(index);

      _dirty = true;
    });
  }

  void _moveState(int index, int offset) {
    final newIndex = index + offset;

    if (newIndex < 0 || newIndex >= _states.length) {
      return;
    }

    setState(() {
      final state = _states.removeAt(index);

      _states.insert(newIndex, state);

      _dirty = true;
    });
  }

  Future<void> _showValidationError(String title, String message) async {
    await showDialog<void>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),

          content: Text(message),

          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },

              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _validateBeforeSave() async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    if (_isStateful) {
      final error = validateStatefulCommand(
        states: _states,

        targetEnabled: _targetEnabled,

        targetKey: _targetKeyController.text,

        targetLabel: _targetLabelController.text,

        targetValue: _targetValueController.text,

        statusCommand: _statusCommandController.text,
      );

      if (error != null) {
        await _showValidationError('Invalid stateful control', error);

        return false;
      }
    } else {
      final command = _buildActionCommand();

      final unknown = unknownCommandParameters(command);

      if (unknown.isNotEmpty) {
        await _showValidationError(
          'Undefined parameters',
          'The command contains '
              'placeholder(s) without a '
              'matching parameter:\n\n'
              '${unknown.map((key) => '{{param:$key}}').join('\n')}',
        );

        return false;
      }
    }

    final command = _buildCurrentCommand();

    if (command.requiresSudo && widget.shellStyle != 'linux') {
      await _showValidationError(
        'Invalid sudo configuration',
        'Run with sudo can only be '
            'used with Linux devices.',
      );

      return false;
    }

    if (command.requiresSudo && command.executionMode != 'standard') {
      await _showValidationError(
        'Invalid execution mode',
        'sudo commands must use '
            'Standard SSH execution.',
      );

      return false;
    }

    return true;
  }

  Future<void> _save() async {
    final valid = await _validateBeforeSave();

    if (!valid || !mounted) {
      return;
    }

    final current = _buildCurrentCommand();

    final saved = commandWithPersistentId(
      command: current,

      existingCommand: widget.command ?? widget.initialCommand,
    );

    _close(saved);
  }

  void _close([RemoteCommand? result]) {
    if (!_dirty) {
      Navigator.of(context).pop(result);

      return;
    }

    setState(() {
      _dirty = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(result);
    });
  }

  Future<void> _requestClose() async {
    if (!_dirty) {
      Navigator.of(context).pop();

      return;
    }

    final result = await showDialog<String>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unsaved changes'),

          content: const Text(
            'You have changes that '
            'have not been saved.',
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, 'cancel');
              },

              child: const Text('Cancel'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, 'discard');
              },

              child: const Text('Discard'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, 'save');
              },

              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case 'discard':
        _close();

        break;

      case 'save':
        await _save();

        break;
    }
  }

  Widget _buildCommandTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Text('Command type', style: Theme.of(context).textTheme.titleMedium),

        const SizedBox(height: 8),

        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'action',

              icon: Icon(Icons.play_arrow),

              label: Text('Action'),
            ),

            ButtonSegment<String>(
              value: 'stateful',

              icon: Icon(Icons.tune),

              label: Text('Stateful'),
            ),
          ],

          selected: {_commandType},

          onSelectionChanged: (selection) {
            if (selection.isEmpty) {
              return;
            }

            _setCommandType(selection.first);
          },
        ),

        const SizedBox(height: 6),

        Text(
          _isStateful
              ? 'A stateful control has two or more '
                    'switch states and may optionally '
                    'query its current status.'
              : 'An action runs one command when tapped.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCommonFields() {
    return CommandBasicFields(
      nameController: _nameController,

      categoryController: _categoryController,

      commandController: _commandController,

      selectedIcon: _selectedIcon,

      executionMode: _executionMode,

      shellStyle: widget.shellStyle,

      requiresSudo: _requiresSudo,

      showCommandFields: !_isStateful,

      onIconChanged: _setIcon,

      onExecutionModeChanged: _setExecutionMode,

      onRequiresSudoChanged: _setRequiresSudo,
    );
  }

  Widget _buildActionEditor() {
    return ActionCommandEditor(
      parameters: _parameters,

      onAddParameter: () {
        _editParameter();
      },

      onEditParameter: (parameter, index) {
        _editParameter(parameter: parameter, index: index);
      },

      onDeleteParameter: _deleteParameter,

      verificationController: _verificationController,

      expectedOutputController: _expectedOutputController,

      testing: _testing,

      testResult: _testResult,

      onTest: _testCommand,
    );
  }

  Widget _buildStatefulEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        StatefulExecutionSection(
          executionMode: _executionMode,

          shellStyle: widget.shellStyle,

          requiresSudo: _requiresSudo,

          onExecutionModeChanged: _setExecutionMode,

          onRequiresSudoChanged: _setRequiresSudo,
        ),

        const SizedBox(height: 24),

        StatefulTargetSection(
          enabled: _targetEnabled,

          keyController: _targetKeyController,

          labelController: _targetLabelController,

          valueController: _targetValueController,

          onEnabledChanged: (value) {
            setState(() {
              _targetEnabled = value;

              _dirty = true;
            });
          },
        ),

        const SizedBox(height: 24),

        StatefulStatusSection(
          statusCommandController: _statusCommandController,

          targetEnabled: _targetEnabled,

          targetKey: _targetKeyController.text,

          statusExecutionMode: _statusExecutionMode,

          onStatusExecutionModeChanged: (value) {
            setState(() {
              _statusExecutionMode = value;

              _dirty = true;
            });
          },

          isTestingStatus: _testing,

          onTestStatus: _testStatefulStatus,
        ),

        const SizedBox(height: 24),

        StatefulStatesSection(
          states: _states,

          onAdd: () {
            _editState();
          },

          onEdit: (state, index) {
            _editState(state: state, index: index);
          },

          onDelete: _deleteState,

          onDuplicate: _duplicateState,

          onMove: _moveState,
        ),
      ],
    );
  }

  Widget _buildConfirmationSwitch() {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,

      title: const Text('Require confirmation'),

      subtitle: _isStateful
          ? const Text(
              'Ask for confirmation before '
              'changing state.',
            )
          : null,

      value: _requiresConfirmation,

      onChanged: (value) {
        if (value == _requiresConfirmation) {
          return;
        }

        setState(() {
          _requiresConfirmation = value;

          _dirty = true;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,

      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        _requestClose();
      },

      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),

            onPressed: _requestClose,
          ),

          title: Text(
            _editing
                ? 'Edit Command'
                : widget.template != null
                ? 'Add Default Command'
                : 'Add Command',
          ),
        ),

        body: SafeArea(
          child: Form(
            key: _formKey,

            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),

              children: [
                if (widget.template != null) ...[
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),

                      child: Text(
                        'This command is based on a '
                        'built-in template. You can '
                        'change anything before saving it.',
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],

                _buildCommandTypeSection(),

                const SizedBox(height: 24),

                _buildCommonFields(),

                const SizedBox(height: 24),

                if (_isStateful)
                  _buildStatefulEditor()
                else
                  _buildActionEditor(),

                const SizedBox(height: 8),

                _buildConfirmationSwitch(),

                const SizedBox(height: 20),

                FilledButton.icon(
                  onPressed: _save,

                  icon: const Icon(Icons.save),

                  label: Text(
                    _editing
                        ? 'Save Changes'
                        : _isStateful
                        ? 'Add Control'
                        : 'Add Command',
                  ),
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
