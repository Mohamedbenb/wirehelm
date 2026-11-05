import 'package:flutter/material.dart';

import '../commands/default_commands.dart';
import '../models/device.dart';
import '../models/remote_command.dart';
import '../models/ssh_identity.dart';
import '../services/credential_storage.dart';
import '../services/identity_storage.dart';
import '../utils/command_icons.dart';

class AddDeviceScreen extends StatefulWidget {
  final Device? device;
  final String initialName, initialHost, initialLocalHost, initialShellStyle;
  final int initialPort;

  const AddDeviceScreen({
    super.key,
    this.device,
    this.initialName = '',
    this.initialHost = '',
    this.initialLocalHost = '',
    this.initialShellStyle = 'auto',
    this.initialPort = 22,
  });

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();

  final IdentityStorage _identityStorage = IdentityStorage();

  final CredentialStorage _credentialStorage = CredentialStorage();

  late final TextEditingController _nameController;

  late final TextEditingController _hostController;
  late final TextEditingController _localHostController;
  late final TextEditingController _refreshController;

  late final TextEditingController _portController;

  late final TextEditingController _usernameController;

  late final TextEditingController _passwordController;

  late String _shellStyle;
  late String _authType;

  String? _identityId;

  List<SshIdentity> _identities = [];

  bool _loadingIdentities = true;
  bool _loadingPassword = false;

  bool _passwordVisible = false;
  bool _dirty = false;
  bool _saving = false;

  final Set<String> _selectedDefaults = {};

  bool get _editing => widget.device != null;

  List<RemoteCommand> get _availableDefaults => defaultCommandsFor(_shellStyle);

  @override
  void initState() {
    super.initState();

    final device = widget.device;

    _nameController = TextEditingController(
      text: device?.name ?? widget.initialName,
    );

    _hostController = TextEditingController(
      text: device?.host ?? widget.initialHost,
    );
    _localHostController = TextEditingController(
      text: device?.localHost ?? widget.initialLocalHost,
    );
    _refreshController = TextEditingController(
      text: '${device?.refreshSeconds ?? 20}',
    );
    _localHostController.addListener(_markDirty);
    _refreshController.addListener(_markDirty);

    _portController = TextEditingController(
      text: device?.port.toString() ?? '${widget.initialPort}',
    );

    _usernameController = TextEditingController(text: device?.username ?? '');

    _passwordController = TextEditingController();

    _shellStyle = device?.shellStyle ?? widget.initialShellStyle;

    _authType = device?.authType ?? 'password';

    _identityId = device?.identityId;

    if (device != null) {
      for (final template in allDefaultCommands) {
        final exists = device.commands.any(
          (command) => _commandMatchesTemplate(command, template),
        );

        if (exists) {
          _selectedDefaults.add(template.id);
        }
      }
    }

    _nameController.addListener(_markDirty);

    _hostController.addListener(_markDirty);

    _portController.addListener(_markDirty);

    _usernameController.addListener(_markDirty);

    _passwordController.addListener(_markDirty);

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadIdentities(), _loadExistingPassword()]);
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);

    _hostController.removeListener(_markDirty);

    _portController.removeListener(_markDirty);

    _usernameController.removeListener(_markDirty);

    _passwordController.removeListener(_markDirty);

    _nameController.dispose();
    _hostController.dispose();
    _localHostController.dispose();
    _refreshController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();

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

  Future<void> _loadExistingPassword() async {
    final passwordId = widget.device?.passwordId;

    if (passwordId == null) {
      return;
    }

    setState(() {
      _loadingPassword = true;
    });

    final password = await _credentialStorage.loadPassword(passwordId);

    if (!mounted) {
      return;
    }

    //
    // Setting the controller would normally trigger
    // _markDirty(), so temporarily preserve the flag.
    //
    final wasDirty = _dirty;

    _passwordController.text = password ?? '';

    setState(() {
      _loadingPassword = false;
      _dirty = wasDirty;
    });
  }

  Future<void> _loadIdentities() async {
    final identities = await _identityStorage.loadIdentities();

    if (!mounted) {
      return;
    }

    setState(() {
      _identities = identities;
      _loadingIdentities = false;

      if (_authType == 'key' && _identityId == null && identities.isNotEmpty) {
        _identityId = identities.first.id;
      }

      if (_identityId != null &&
          !identities.any((identity) => identity.id == _identityId)) {
        _identityId = identities.isEmpty ? null : identities.first.id;
      }
    });
  }

  bool _commandMatchesTemplate(RemoteCommand command, RemoteCommand template) {
    final templateId = template.templateId ?? template.id;

    if (command.templateId == templateId) {
      return true;
    }

    if (command.id == template.id) {
      return true;
    }

    if (command.templateId == null &&
        command.command == template.command &&
        command.executionMode == template.executionMode) {
      return true;
    }

    return false;
  }

  void _selectAllDefaults() {
    final before = _selectedDefaults.length;

    setState(() {
      for (final command in _availableDefaults) {
        _selectedDefaults.add(command.id);
      }

      if (_selectedDefaults.length != before) {
        _dirty = true;
      }
    });
  }

  void _clearDefaultSelection() {
    final before = _selectedDefaults.length;

    setState(() {
      for (final command in _availableDefaults) {
        _selectedDefaults.remove(command.id);
      }

      if (_selectedDefaults.length != before) {
        _dirty = true;
      }
    });
  }

  List<RemoteCommand> _buildCommands() {
    final existingCommands = widget.device?.commands ?? const <RemoteCommand>[];

    final customCommands = existingCommands.where((command) {
      return !allDefaultCommands.any(
        (template) => _commandMatchesTemplate(command, template),
      );
    }).toList();

    final commands = <RemoteCommand>[...customCommands];

    for (final template in _availableDefaults) {
      if (!_selectedDefaults.contains(template.id)) {
        continue;
      }

      RemoteCommand? existing;

      for (final command in existingCommands) {
        if (_commandMatchesTemplate(command, template)) {
          existing = command;
          break;
        }
      }

      if (existing != null) {
        commands.add(existing);
      } else {
        commands.add(commandFromTemplate(template));
      }
    }

    return commands;
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_authType == 'key' && _identityId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select an SSH identity.')));

      return;
    }

    final password = _passwordController.text;

    if (_authType == 'password' && password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an SSH password.')));

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final existing = widget.device;

      final deviceId =
          existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

      String? passwordId;

      if (_authType == 'password') {
        passwordId = existing?.passwordId ?? deviceId;

        await _credentialStorage.savePassword(
          passwordId: passwordId,
          password: password,
        );
      } else {
        //
        // If the device previously used password auth,
        // remove that credential when the user explicitly
        // saves the device as key-authenticated.
        //
        if (existing?.passwordId != null) {
          await _credentialStorage.deletePassword(existing!.passwordId!);
        }
      }

      final device = Device(
        id: deviceId,

        name: _nameController.text.trim(),

        host: _hostController.text.trim(),
        localHost: _localHostController.text.trim(),
        refreshSeconds: int.parse(_refreshController.text),

        port: int.parse(_portController.text.trim()),

        username: _usernameController.text.trim(),

        shellStyle: _shellStyle,

        authType: _authType,

        identityId: _authType == 'key' ? _identityId : null,

        passwordId: _authType == 'password' ? passwordId : null,

        commands: _buildCommands(),
      );

      if (!mounted) {
        return;
      }

      _close(device);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save credentials: $e')));
    }
  }

  void _close([Device? result]) {
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
          content: const Text('You have changes that have not been saved.'),
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

  String _environmentDescription() {
    switch (_shellStyle) {
      case 'windows':
        return 'Windows command environment. '
            'Windows-specific defaults and interactive '
            'desktop commands are available.';

      case 'linux':
        return 'Linux/Unix command environment. '
            'Linux-specific defaults are available.';

      default:
        return 'Generic command environment. '
            'Only portable defaults are shown.';
    }
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

          title: Text(_editing ? 'Edit Device' : 'Add Device'),
        ),

        body: SafeArea(
          child: Form(
            key: _formKey,

            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),

              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Desktop',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a device name';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Internet host',
                    hintText: 'Tailscale IP or hostname',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a host';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _localHostController,
                  decoration: const InputDecoration(
                    labelText: 'Local host (optional)',
                    hintText: '192.168.1.100',
                    helperText:
                        'Local first; internet if local is unreachable.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _refreshController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Status refresh (seconds)',
                    helperText: '5–300 seconds. Manual and switch checks are immediate.',
                  ),
                  validator: (value) {
                    final seconds = int.tryParse(value ?? '');
                    return seconds == null || seconds < 5 || seconds > 300
                        ? 'Enter 5–300 seconds'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  // SSH uses the same port for both addresses.
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final port = int.tryParse(value?.trim() ?? '');

                    if (port == null || port < 1 || port > 65535) {
                      return 'Enter a valid port';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Remote account username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a username';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  initialValue: _shellStyle,
                  decoration: const InputDecoration(
                    labelText: 'Command environment',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'windows', child: Text('Windows')),
                    DropdownMenuItem(value: 'linux', child: Text('Linux')),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _shellStyle) {
                      return;
                    }

                    setState(() {
                      _shellStyle = value;

                      final availableIds = _availableDefaults
                          .map((command) => command.id)
                          .toSet();

                      _selectedDefaults.removeWhere(
                        (id) => !availableIds.contains(id),
                      );

                      _dirty = true;
                    });
                  },
                ),

                const SizedBox(height: 8),

                Text(
                  _environmentDescription(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  initialValue: _authType,
                  decoration: const InputDecoration(
                    labelText: 'Authentication',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'key', child: Text('SSH key')),
                    DropdownMenuItem(
                      value: 'password',
                      child: Text('Password'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _authType) {
                      return;
                    }

                    setState(() {
                      _authType = value;

                      if (_authType == 'key' &&
                          _identityId == null &&
                          _identities.isNotEmpty) {
                        _identityId = _identities.first.id;
                      }

                      _dirty = true;
                    });
                  },
                ),

                const SizedBox(height: 12),

                if (_authType == 'key') ...[
                  if (_loadingIdentities)
                    const Center(child: CircularProgressIndicator())
                  else if (_identities.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No SSH identities exist yet. '
                          'Create one from the key icon '
                          'on the Devices screen.',
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _identityId,
                      decoration: const InputDecoration(
                        labelText: 'SSH identity',
                        border: OutlineInputBorder(),
                      ),
                      items: _identities
                          .map(
                            (identity) => DropdownMenuItem<String>(
                              value: identity.id,
                              child: Text(identity.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == _identityId) {
                          return;
                        }

                        setState(() {
                          _identityId = value;
                          _dirty = true;
                        });
                      },
                    ),
                ] else ...[
                  TextFormField(
                    controller: _passwordController,

                    obscureText: !_passwordVisible,

                    enableSuggestions: false,

                    autocorrect: false,

                    decoration: InputDecoration(
                      labelText: 'Password',

                      border: const OutlineInputBorder(),

                      suffixIcon: IconButton(
                        tooltip: _passwordVisible
                            ? 'Hide password'
                            : 'Show password',

                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),

                        onPressed: () {
                          setState(() {
                            _passwordVisible = !_passwordVisible;
                          });
                        },
                      ),
                    ),

                    validator: (value) {
                      if (_authType != 'password') {
                        return null;
                      }

                      if (_loadingPassword) {
                        return null;
                      }

                      if (value == null || value.isEmpty) {
                        return 'Enter a password';
                      }

                      return null;
                    },
                  ),

                  if (_loadingPassword) ...[
                    const SizedBox(height: 8),

                    const LinearProgressIndicator(),
                  ],

                  const SizedBox(height: 8),

                  Text(
                    'Stored securely on this device.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Default commands',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),

                    TextButton(
                      onPressed: _selectAllDefaults,
                      child: const Text('Select all'),
                    ),

                    TextButton(
                      onPressed: _clearDefaultSelection,
                      child: const Text('Clear'),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  _editing
                      ? 'Choose which built-in commands this device should have.'
                      : 'Optionally add built-in commands to this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                const SizedBox(height: 12),

                if (_availableDefaults.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No default commands are available '
                        'for this environment.',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final command in _availableDefaults)
                          CheckboxListTile(
                            value: _selectedDefaults.contains(command.id),

                            title: Text(command.name),

                            subtitle: Text(command.category),

                            secondary: Icon(commandIcon(command.icon)),

                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedDefaults.add(command.id);
                                } else {
                                  _selectedDefaults.remove(command.id);
                                }

                                _dirty = true;
                              });
                            },
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _saving ? null : _save,

                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),

                  label: Text(_editing ? 'Save Changes' : 'Save Device'),
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
