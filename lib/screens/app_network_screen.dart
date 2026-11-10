import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppNetworkScreen extends StatefulWidget {
  const AppNetworkScreen({super.key});

  @override
  State<AppNetworkScreen> createState() => _AppNetworkScreenState();
}

class _AppNetworkScreenState extends State<AppNetworkScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('remote_control/app_network');
  List<Map<String, Object?>> _apps = [];
  String _filter = '';
  String? _error;
  bool _busy = true;
  bool _verified = false;
  final _readAge = Stopwatch();
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _request('list');
  }

  @override
  void dispose() {
    _countdown?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _request('list');
  }

  int _seconds(Map<String, Object?> app) =>
      (app['temporarySeconds'] as int? ?? 0);

  Future<void> _openAlarmSettings() async {
    try {
      await _channel.invokeMethod<bool>('alarmSettings');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _request(String method, [Map<String, Object>? args]) async {
    _countdown?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _verified = false;
    });
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
        method,
        args,
      );
      if (!mounted) return;
      setState(() {
        _apps = rows!.map(Map<String, Object?>.from).toList();
        _verified = true;
      });
      _readAge
        ..reset()
        ..start();
      if (_apps.any((app) => _seconds(app) > 0)) {
        _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
          final age = _readAge.elapsed.inSeconds;
          if (_apps.any((app) => _seconds(app) > 0 && _seconds(app) <= age)) {
            _request('list');
          } else {
            setState(() {});
          }
        });
      }
    } on PlatformException catch (error) {
      if (mounted)
        setState(() => _error = error.message ?? 'Firewall unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _apps.where((app) {
      final name = '${app['label']} ${app['name']}'.toLowerCase();
      return name.contains(_filter);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('App manager'),
        actions: [
          IconButton(
            tooltip: 'Refresh firewall status',
            onPressed: _busy ? null : () => _request('list'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Text(
                'Block direct network traffic from selected apps. Traffic sent '
                'on their behalf by other apps or services can still pass.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _filter = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Find an app',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_verified &&
                _apps.any(
                  (app) =>
                      app['retry'] == true ||
                      (app['saved'] == true &&
                          app['blocked'] != true &&
                          _seconds(app) == 0),
                ))
              TextButton(
                onPressed: _busy ? null : () => _request('restore'),
                child: const Text('Reapply saved rules'),
              ),
            if (_verified && visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matching apps'),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final app = visible[index];
                  final external = app['external'] == true;
                  final saved = app['saved'] == true;
                  final blocked = app['blocked'] == true;
                  final temporary = _seconds(app) > 0;
                  final remaining = (_seconds(app) - _readAge.elapsed.inSeconds)
                      .clamp(0, 300);
                  final timer =
                      '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
                  final status = !_verified
                      ? 'Status unverified'
                      : external
                      ? 'Managed outside Wirehelm'
                      : blocked
                      ? 'Network blocked'
                      : temporary
                      ? 'Temporarily allowed · $timer left'
                      : saved
                      ? 'Saved block inactive'
                      : 'No Wirehelm block';
                  final tile = SwitchListTile(
                    title: Text(app['label'] as String),
                    subtitle: Text('${app['name']}\n$status'),
                    isThreeLine: true,
                    value: _verified && (saved || blocked),
                    onChanged: !_verified || _busy || external
                        ? null
                        : (value) => _request('setBlocked', {
                            'package': app['name'] as String,
                            'blocked': value,
                          }),
                  );
                  if (!_verified ||
                      external ||
                      !saved ||
                      (!temporary && !blocked)) {
                    return tile;
                  }
                  final name = app['name'] as String;
                  final canSchedule = app['canSchedule'] == true;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      tile,
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : temporary
                              ? () => _request('setBlocked', {
                                  'package': name,
                                  'blocked': true,
                                })
                              : canSchedule
                              ? () => _request('allowTemporarily', {
                                  'package': name,
                                })
                              : _openAlarmSettings,
                          child: Text(
                            temporary
                                ? 'Block now'
                                : canSchedule
                                ? 'Allow for 5 minutes'
                                : 'Allow exact alarms for timed exceptions',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
