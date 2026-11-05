import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../transport/tsnet_client.dart';

class TailscaleScreen extends StatefulWidget {
  const TailscaleScreen({super.key});
  @override
  State<TailscaleScreen> createState() => _TailscaleScreenState();
}

class _TailscaleScreenState extends State<TailscaleScreen>
    with WidgetsBindingObserver {
  final _client = TsnetClient.instance;
  TsnetStatus? _status;
  String? _error;
  bool _busy = false;
  bool _useTsnet = true;
  bool _active = true;
  Timer? _timer;
  final _debugPC = TextEditingController();
  Map<String, dynamic> _debug = const {};
  bool _debugBusy = false;
  bool _temporaryRoot = false;
  bool _peerSuggested = false;
  String? _debugError;
  int _debugRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_active && (ModalRoute.of(context)?.isCurrent ?? false)) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _load() async {
    final enabled = await _client.useTsnet();
    if (!mounted) return;
    setState(() => _useTsnet = enabled);
    await _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy || _debugBusy || !mounted) return;
    final debugRevision = _debugRevision;
    setState(() => _busy = true);
    try {
      final status = await _client.status();
      final debug = await _client.debugRelayStatus();
      if (!mounted) return;
      if (status.isReady && !_peerSuggested) {
        final peers = await _client.peers();
        if (!mounted) return;
        final candidates = peers.where(
          (p) => p['os'] == 'windows' && p['online'] == true,
        );
        if (candidates.isNotEmpty && _debugPC.text.isEmpty) {
          final ips = (candidates.first['ips'] as List? ?? []).cast<String>();
          if (ips.isNotEmpty) _debugPC.text = ips.first;
        }
        _peerSuggested = true;
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        if (debugRevision == _debugRevision) _debug = debug;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDebugRelay(bool enable) async {
    setState(() {
      _debugBusy = true;
      _debugError = null;
      _debugRevision++;
    });
    try {
      if (enable) {
        final value = await _client.startDebugRelay(
          _debugPC.text,
          temporaryRoot: _temporaryRoot,
        );
        if (mounted) {
          setState(() {
            _debug = value;
            _debugError = null;
          });
        }
      } else {
        await _client.stopDebugRelay();
        if (mounted) {
          setState(() {
            _debug = const {};
            _debugError = null;
          });
        }
      }
    } catch (error) {
      final message = error is PlatformException
          ? (error.message ?? error.code)
          : error.toString();
      final diagnostics = await _client.debugRelayStatus().catchError(
        (_) => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _debugError = message;
          _debug = diagnostics;
        });
      }
    } finally {
      if (mounted) setState(() => _debugBusy = false);
    }
  }

  Future<void> _setDebugDuration(int minutes) async {
    setState(() {
      _debugBusy = true;
      _debugError = null;
      _debugRevision++;
    });
    try {
      final result = await _client.setDebugRelayDuration(minutes);
      if (mounted) setState(() => _debug = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _debugError = error is PlatformException
              ? error.message
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _debugBusy = false);
    }
  }

  Widget _debugCard() {
    final enabled = _debug['enabled'] == true;
    final ip = _status?.ips.isNotEmpty == true
        ? _status!.ips.firstWhere(
            (ip) => !ip.contains(':'),
            orElse: () => _status!.ips.first,
          )
        : '';
    final address = ip.contains(':') ? '[$ip]:5555' : '$ip:5555';
    final expires = _debug['expiresAt'] as num?;
    final minutes = expires == null
        ? 0
        : ((expires.toInt() - DateTime.now().millisecondsSinceEpoch) / 60000)
              .ceil()
              .clamp(0, 1440);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remote ADB · temporary session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Uses this app’s Tailscale connection. Off by default; expires after the selected duration.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _debugPC,
              enabled: !enabled && !_debugBusy,
              decoration: const InputDecoration(
                labelText: 'Permitted PC · Tailscale IP',
                hintText: '100.x.x.x',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(
                'adb.duration.${_debug['preferredDurationMinutes'] ?? 30}',
              ),
              initialValue:
                  (_debug['preferredDurationMinutes'] as num?)?.toInt() ?? 30,
              decoration: const InputDecoration(labelText: 'Session duration'),
              items:
                  const <int, String>{
                        5: '5 minutes',
                        15: '15 minutes',
                        30: '30 minutes',
                        60: '1 hour',
                        120: '2 hours',
                        240: '4 hours',
                        480: '8 hours',
                        1440: '24 hours',
                      }.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
              onChanged: _debugBusy
                  ? null
                  : (value) {
                      if (value != null) _setDebugDuration(value);
                    },
            ),
            if (enabled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Changing duration resets the timer from now without disconnecting.',
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Temporary local ADB (root)'),
              subtitle: const Text(
                'For mobile data or no Wi-Fi. Temporary IPv4/IPv6 guards restrict ADB to local access. Stop restores the listener and removes its guards; no boot changes.',
              ),
              value: _temporaryRoot,
              onChanged: enabled || _debugBusy
                  ? null
                  : (v) => setState(() => _temporaryRoot = v),
            ),
            if (!_temporaryRoot && !enabled)
              const Text(
                'Reuses an existing Wireless debugging listener without changing Android settings.',
              ),
            if (enabled) ...[
              Text('${_debug['mode']} · $minutes min remaining'),
              SelectableText('adb connect $address'),
              Text(
                'Permitted PC: ${_debug['allowedPC']} · connections: ${_debug['connections'] ?? 0}',
              ),
              if (_debug['backgroundProtected'] == true)
                const Text('Background connection protected'),
            ],
            if ((_debug['lastError'] as String? ?? '').isNotEmpty)
              Text(_debug['lastError'] as String),
            if (_debug['cleanupError'] != null)
              Text('Restore pending: ${_debug['cleanupError']}'),
            if (_debugError != null)
              Text(
                _debugError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_debugBusy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_debug['diagnostics'] is Map)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Connection diagnostics'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ')
                        .convert(_debug['diagnostics']),
                  ),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: jsonEncode(_debug['diagnostics'])),
                    ),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy diagnostics'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (!enabled)
                  FilledButton.icon(
                    onPressed: _debugBusy || _status?.isReady != true
                        ? null
                        : () => _setDebugRelay(true),
                    icon: const Icon(Icons.cable),
                    label: const Text('Start remote ADB'),
                  ),
                if (enabled ||
                    _debug['temporaryRoot'] == true ||
                    _debug['cleanupError'] != null)
                  OutlinedButton.icon(
                    onPressed: _debugBusy ? null : () => _setDebugRelay(false),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop / restore'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Android’s ADB authorization remains required. Active sessions stay protected when the app is in the background. Updates, force stop or reboot can still end the connection; reopen this screen to restore any temporary listener left behind.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    try {
      await _client.openLogin(_status!.authUrl);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debugPC.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tailscale')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Connect through Tailscale'),
              subtitle: const Text(
                'Built into this app. The Tailscale VPN app can stay off.',
              ),
              value: _useTsnet,
              onChanged: (enabled) async {
                await _client.setUseTsnet(enabled);
                if (mounted) setState(() => _useTsnet = enabled);
              },
            ),
            const Text(
              'Applies to new connections. Turn off to use direct TCP for local-network devices.',
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _status?.isReady == true
                    ? Icons.check_circle_outline
                    : Icons.cloud_outlined,
              ),
              title: Text(_status?.state ?? 'Starting…'),
              subtitle: _status?.ips.isNotEmpty == true
                  ? Text(_status!.ips.join('\n'))
                  : null,
              trailing: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Refresh Tailscale status',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
            ),
            if (_status?.authUrl.isNotEmpty == true)
              FilledButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login),
                label: const Text('Sign in to Tailscale'),
              ),
            if (_status?.state == 'NeedsMachineAuth')
              const Text(
                'Approve remote-control-android in your Tailscale admin console.',
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 20),
            _debugCard(),
            const SizedBox(height: 20),
            const Text(
              'This app has its own Tailscale identity. Sign in once, then use your PC’s Tailscale IP or DNS name in the device address.',
            ),
          ],
        ),
      ),
    );
  }
}
