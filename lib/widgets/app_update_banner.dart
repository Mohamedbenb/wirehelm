import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/app_updates_settings_screen.dart';
import '../services/app_update.dart';
import '../ssh/ssh_session_manager.dart';

int? newerUpdateBuild(String json, int installed) {
  final data = jsonDecode(json);
  if (data is! Map || data['version'] is! String || data['build'] is! int) {
    return null;
  }
  final build = data['build'] as int;
  return build > installed ? build : null;
}

class AppUpdateBanner extends StatefulWidget {
  const AppUpdateBanner({super.key});
  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;
  String? _available;
  String? _source;
  int? _dismissed;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sshSessions.addListener(_check);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final source = prefs.getString('apk_update_source');
      if (source != _source) {
        _source = source;
        _lastCheck = null;
        _dismissed = null;
        if (mounted) setState(() => _available = null);
      }
      if (source == null) return;
      final installed = await AppUpdate.channel
          .invokeMapMethod<String, dynamic>('installed');
      if (installed == null) return;
      final path =
          prefs.getString('apk_update_path_$source') ??
          AppUpdate.defaultWindowsPath;
      final cacheKey = 'apk_update_manifest_$source:$path';
      void showManifest(String raw) {
        final build = newerUpdateBuild(raw, installed['build'] as int);
        if (mounted) {
          setState(
            () => _available = build == null || build == _dismissed
                ? null
                : '${(jsonDecode(raw) as Map)['version']} (build $build)',
          );
        }
      }

      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        try {
          showManifest(cached);
        } catch (_) {
          await prefs.remove(cacheKey);
        }
      }
      final session = sshSessions.existingSession(source);
      if (session == null || !session.isConnected) return;
      if (_lastCheck != null &&
          DateTime.now().difference(_lastCheck!) < const Duration(minutes: 1)) {
        return;
      }
      _lastCheck = DateTime.now();
      final sftp = await session.client!.sftp().timeout(
        const Duration(seconds: 10),
      );
      try {
        final file = await sftp
            .open('${path.replaceAll('\\', '/')}.json')
            .timeout(const Duration(seconds: 10));
        try {
          final bytes = await file
              .read(length: 4096)
              .timeout(const Duration(seconds: 10))
              .fold<List<int>>([], (a, b) => a..addAll(b));
          final raw = utf8.decode(bytes);
          showManifest(raw);
          await prefs.setString(cacheKey, raw);
        } finally {
          await file.close().timeout(const Duration(seconds: 3));
        }
      } finally {
        sftp.close();
      }
    } catch (_) {
      // Missing manifest/offline source should not interrupt device use.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    sshSessions.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _available == null
      ? const SizedBox.shrink()
      : MaterialBanner(
          leading: const Icon(Icons.system_update),
          content: Text('Node Cockpit $_available is available.'),
          actions: [
            TextButton(
              onPressed: () {
                _dismissed = int.tryParse(
                  RegExp(r'build (\d+)').firstMatch(_available!)?.group(1) ??
                      '',
                );
                setState(() => _available = null);
              },
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AppUpdatesSettingsScreen(),
                  ),
                );
                _lastCheck = null;
                _check();
              },
              child: const Text('Update'),
            ),
          ],
        );
}
