import 'package:flutter/material.dart';

import 'identity_screen.dart';
import '../models/ssh_identity.dart';
import '../services/identity_storage.dart';

class IdentitiesScreen extends StatefulWidget {
  const IdentitiesScreen({super.key});

  @override
  State<IdentitiesScreen> createState() => _IdentitiesScreenState();
}

class _IdentitiesScreenState extends State<IdentitiesScreen> {
  final _storage = IdentityStorage();

  List<SshIdentity> _identities = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identities = await _storage.loadIdentities();

    if (!mounted) return;

    setState(() {
      _identities = identities;
      _loading = false;
    });
  }

  Future<void> _addIdentity() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const IdentityScreen()));

    await _load();
  }

  Future<void> _openIdentity(SshIdentity identity) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IdentityScreen(identity: identity)),
    );

    await _load();
  }

  Future<void> _deleteIdentity(SshIdentity identity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Identity'),
          content: Text(
            'Delete "${identity.name}"?\n\n'
            'Devices using this identity '
            'will no longer be able to connect.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
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

    await _storage.deleteIdentity(identity.id);

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSH Identities')),

      floatingActionButton: FloatingActionButton(
        onPressed: _addIdentity,
        child: const Icon(Icons.add),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _identities.isEmpty
          ? const Center(child: Text('No identities yet'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _identities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final identity = _identities[index];

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.key),

                    title: Text(identity.name),

                    subtitle: const Text('Ed25519'),

                    onTap: () => _openIdentity(identity),

                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteIdentity(identity);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete),
                              SizedBox(width: 12),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
