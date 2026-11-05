import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinenacl/ed25519.dart';

import '../models/ssh_identity.dart';
import '../services/identity_storage.dart';

class IdentityScreen extends StatefulWidget {
  final SshIdentity? identity;

  const IdentityScreen({super.key, this.identity});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final IdentityStorage _storage = IdentityStorage();

  late final TextEditingController _nameController;

  String? _pendingPrivateKeyPem;
  String? _pendingPublicKey;

  bool _dirty = false;
  bool _saving = false;
  bool _generating = false;

  String? _error;

  bool get _editing => widget.identity != null;

  String? get _publicKey => widget.identity?.publicKey ?? _pendingPublicKey;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.identity?.name ?? '');

    _nameController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _nameController.removeListener(_markDirty);

    _nameController.dispose();

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

  OpenSSHEd25519KeyPair _generateKeyPair() {
    final signingKey = SigningKey.generate();

    final privateKey = Uint8List.fromList(signingKey);

    final publicKey = Uint8List.fromList(signingKey.verifyKey);

    return OpenSSHEd25519KeyPair(publicKey, privateKey, 'remote-control-app');
  }

  String _toAuthorizedKey(OpenSSHEd25519KeyPair keyPair) {
    final encoded = keyPair.toPublicKey().encode();

    return 'ssh-ed25519 '
        '${base64Encode(encoded)} '
        'remote-control-app';
  }

  Future<void> _generate() async {
    if (_generating) {
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final keyPair = _generateKeyPair();

      final privateKeyPem = keyPair.toPem();

      final publicKey = _toAuthorizedKey(keyPair);

      if (!mounted) {
        return;
      }

      setState(() {
        _pendingPrivateKeyPem = privateKeyPem;

        _pendingPublicKey = publicKey;

        _generating = false;
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyPublicKey() async {
    final publicKey = _publicKey;

    if (publicKey == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: publicKey));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Public key copied')));
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = 'Enter an identity name.';
      });

      return;
    }

    if (!_editing &&
        (_pendingPrivateKeyPem == null || _pendingPublicKey == null)) {
      setState(() {
        _error = 'Generate a key first.';
      });

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final identities = await _storage.loadIdentities();

      if (_editing) {
        final existing = widget.identity!;

        final updated = existing.copyWith(name: name);

        final updatedList = identities.map((item) {
          if (item.id == existing.id) {
            return updated;
          }

          return item;
        }).toList();

        await _storage.saveIdentities(updatedList);
      } else {
        final id = DateTime.now().microsecondsSinceEpoch.toString();

        final identity = SshIdentity(
          id: id,
          name: name,
          publicKey: _pendingPublicKey!,
        );

        await _storage.savePrivateKey(
          identityId: id,
          privateKeyPem: _pendingPrivateKeyPem!,
        );

        await _storage.saveIdentities([...identities, identity]);
      }

      if (!mounted) {
        return;
      }

      _close(true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  void _close([bool? result]) {
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

  @override
  Widget build(BuildContext context) {
    final publicKey = _publicKey;

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

          title: Text(_editing ? 'SSH Identity' : 'New Identity'),
        ),

        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),

            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Identity name',
                  hintText: 'Personal Windows',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              if (!_editing && publicKey == null)
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key),
                  label: const Text('Generate key'),
                ),

              if (!_editing && publicKey != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            'This identity has not '
                            'been saved yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
              ],

              if (publicKey != null) ...[
                Text(
                  'Public key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),

                const SizedBox(height: 8),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      publicKey,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _copyPublicKey,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy public key'),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),

                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],

              const SizedBox(height: 28),

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_editing ? 'Save Changes' : 'Save Identity'),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
