import 'package:flutter/material.dart';

import '../ssh/ssh_session.dart';
import '../transport/tsnet_client.dart';

class PerformanceScreen extends StatefulWidget {
  final SshSession session;
  const PerformanceScreen({super.key, required this.session});
  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  String _link = 'Not checked';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _checkLink();
  }

  Future<void> _checkLink() async {
    if (widget.session.connectionRoute != 'Tailscale') {
      setState(() => _link = widget.session.connectionRoute ?? 'Disconnected');
      return;
    }
    setState(() => _busy = true);
    try {
      final peers = await TsnetClient.instance.peers();
      final host = widget.session.connectedHost;
      final matches = peers.where(
        (p) =>
            (p['ips'] as List? ?? []).contains(host) ||
            p['dnsName'] == host ||
            p['name'] == host,
      );
      final peer = matches.isEmpty ? null : matches.first;
      final direct = peer?['directAddress'] as String? ?? '';
      final relay = peer?['relay'] as String? ?? '';
      if (mounted) {
        setState(
          () => _link = direct.isNotEmpty && peer?['active'] == true
              ? 'Direct peer connection'
              : relay.isNotEmpty && peer?['active'] == true
              ? 'Relayed through $relay'
              : 'Path not confirmed; run a command and refresh',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _link = 'Could not inspect link: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Performance'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _checkLink,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh network path',
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.session,
        builder: (_, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.connectionRoute ?? 'Disconnected',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(widget.session.connectedHost ?? ''),
                    const SizedBox(height: 8),
                    Text(
                      'SSH cipher: ${widget.session.client?.incomingCipherName ?? 'Not reported'}',
                    ),
                    if (widget.session.connectionRoute == 'Tailscale')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_link),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.session.connectionDuration != null)
              Text(
                'Last connection: ${widget.session.connectionDuration!.inMilliseconds} ms (includes authentication and any LAN fallback)',
              ),
            const SizedBox(height: 16),
            Text(
              'Recent requests',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const ExpansionTile(
              title: Text('How to read timings'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Startup includes launching the helper and opening its SSH tunnel. Remote execution is measured on the PC. Response includes transport and helper polling. A dash means the PC did not return a timing; failures and fallback paths are also listed.',
                  ),
                ),
              ],
            ),
            if (widget.session.commandTimings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Run or refresh a Windows command, then return here.',
                ),
              ),
            if (widget.session.commandTimings.isNotEmpty)
              const SizedBox(height: 8),
            for (var i = 0; i < widget.session.commandTimings.length; i++) ...[
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  title: Text(
                    '${widget.session.commandTimings[i]['mode']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${widget.session.commandTimings[i]['total']} ms',
                    style: TextStyle(
                      color: widget.session.commandTimings[i]['failed'] == 1
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    '${(widget.session.commandTimings[i]['at'] as DateTime).toLocal().toString().split(' ').last.split('.').first}${widget.session.commandTimings[i]['failed'] == 1 ? ' · Failed / timed out' : ''}\nQueue ${widget.session.commandTimings[i]['queue']} ms · Startup ${widget.session.commandTimings[i]['startup']} ms\nPC ${widget.session.commandTimings[i]['execution'] == -1 ? '—' : '${widget.session.commandTimings[i]['execution']} ms'} · Response ${widget.session.commandTimings[i]['execution'] == -1 || widget.session.commandTimings[i]['response'] == -1 ? '—' : '${widget.session.commandTimings[i]['response']} ms'}',
                  ),
                ),
              ),
              if (i < widget.session.commandTimings.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}
