import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/ssh_identity.dart';
import '../services/identity_storage.dart';
import '../ssh/ssh_session.dart';
import 'identity_installer.dart';

class InstallIdentityDialog extends StatefulWidget {
  final Device device;

  //
  // Optional for backward compatibility
  // during the multi-session migration.
  //
  // If omitted, IdentityInstaller still
  // falls back to the legacy global
  // sshSession.
  //
  final SshSession? session;

  const InstallIdentityDialog({super.key, required this.device, this.session});

  @override
  State<InstallIdentityDialog> createState() => _InstallIdentityDialogState();
}

class _InstallIdentityDialogState extends State<InstallIdentityDialog> {
  final IdentityStorage _identityStorage = IdentityStorage();

  final IdentityInstaller _installer = IdentityInstaller();

  List<SshIdentity> _identities = [];

  String? _selectedIdentityId;

  bool _loading = true;
  bool _installing = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadIdentities();
  }

  Future<void> _loadIdentities() async {
    try {
      final identities = await _identityStorage.loadIdentities();

      if (!mounted) {
        return;
      }

      setState(() {
        _identities = identities;

        if (identities.isNotEmpty) {
          _selectedIdentityId = identities.first.id;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  SshIdentity? get _selectedIdentity {
    final selectedId = _selectedIdentityId;

    if (selectedId == null) {
      return null;
    }

    for (final identity in _identities) {
      if (identity.id == selectedId) {
        return identity;
      }
    }

    return null;
  }

  Future<void> _install() async {
    final identity = _selectedIdentity;

    if (identity == null) {
      setState(() {
        _error = 'Select an SSH identity.';
      });

      return;
    }

    setState(() {
      _installing = true;
      _error = null;
    });

    try {
      final result = await _installer.install(
        device: widget.device,

        publicKey: identity.publicKey,

        session: widget.session,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        InstallIdentityDialogResult(
          identity: identity,

          alreadyInstalled: result.alreadyInstalled,

          target: result.target,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();

        _installing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.key),

      title: const Text('Install SSH identity'),

      content: SizedBox(width: 420, child: _buildContent(context)),

      actions: [
        TextButton(
          onPressed: _installing
              ? null
              : () {
                  Navigator.of(context).pop();
                },

          child: const Text('Cancel'),
        ),

        FilledButton.icon(
          onPressed: _loading || _installing || _identities.isEmpty
              ? null
              : _install,

          icon: _installing
              ? const SizedBox(
                  width: 18,
                  height: 18,

                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),

          label: Text(_installing ? 'Installing...' : 'Install'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),

        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_identities.isEmpty) {
      return const Column(
        mainAxisSize: MainAxisSize.min,

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text('No SSH identities are available.'),

          SizedBox(height: 8),

          Text(
            'Create an identity first, then '
            'return here to install its '
            'public key on this device.',
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,

      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Text(
          'Install an SSH public key on '
          '${widget.device.name}.',
        ),

        const SizedBox(height: 6),

        Text(
          'Only the public key is sent '
          'to the remote device. The '
          'private key remains on this phone.',

          style: Theme.of(context).textTheme.bodySmall,
        ),

        const SizedBox(height: 20),

        const Text('Identity', style: TextStyle(fontWeight: FontWeight.w600)),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          initialValue: _selectedIdentityId,

          isExpanded: true,

          decoration: const InputDecoration(border: OutlineInputBorder()),

          items: _identities
              .map(
                (identity) => DropdownMenuItem<String>(
                  value: identity.id,

                  child: Text(identity.name),
                ),
              )
              .toList(),

          onChanged: _installing
              ? null
              : (value) {
                  setState(() {
                    _selectedIdentityId = value;

                    _error = null;
                  });
                },
        ),

        const SizedBox(height: 16),

        _DeviceTargetInfo(device: widget.device),

        if (_error != null) ...[
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),

            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,

              borderRadius: BorderRadius.circular(10),
            ),

            child: SelectableText(
              _error!,

              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DeviceTargetInfo extends StatelessWidget {
  final Device device;

  const _DeviceTargetInfo({required this.device});

  @override
  Widget build(BuildContext context) {
    String description;

    switch (device.shellStyle) {
      case 'linux':
        description =
            'The key will be installed in '
            '~/.ssh/authorized_keys for '
            '${device.username}.';
        break;

      case 'windows':
        description =
            'The app will detect whether '
            '${device.username} is an '
            'Administrator and install the '
            'key in the appropriate Windows '
            'OpenSSH authorized-keys file.';
        break;

      default:
        description =
            'This device must be configured '
            'as Linux or Windows before an '
            'identity can be installed.';
    }

    return Container(
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,

        borderRadius: BorderRadius.circular(10),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Icon(Icons.info_outline, size: 20),

          const SizedBox(width: 10),

          Expanded(child: Text(description)),
        ],
      ),
    );
  }
}

class InstallIdentityDialogResult {
  final SshIdentity identity;

  final bool alreadyInstalled;

  final String target;

  const InstallIdentityDialogResult({
    required this.identity,
    required this.alreadyInstalled,
    required this.target,
  });
}
