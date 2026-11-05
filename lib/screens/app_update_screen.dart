import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../services/app_update.dart';
import '../services/transfer_rate.dart';
import '../ssh/ssh_session.dart';
import 'performance_screen.dart';

class AppUpdateScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  final bool startSpeedTest;
  const AppUpdateScreen({
    super.key,
    required this.device,
    required this.session,
    this.startSpeedTest = false,
  });
  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final _path = TextEditingController();
  PreparedUpdate? _prepared;
  bool _busy = false, _cancelled = false, _loading = true;
  bool _downloadFailed = false;
  int _received = 0, _total = 0;
  int _operationId = 0;
  final _downloadClock = Stopwatch();
  final _rate = TransferRate();
  Timer? _rateTimer;
  double _bytesPerSecond = 0;
  double _averageRate = 0;
  double? _networkRate;
  String? _testPhase;
  String? _message;
  String get _key => 'apk_update_path_${widget.device.id}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedPath = prefs.getString(_key);
    _path.text =
        (savedPath == AppUpdate.legacyWindowsPath
            ? AppUpdate.defaultWindowsPath
            : savedPath) ??
        (widget.device.shellStyle == 'linux'
            ? ''
            : AppUpdate.defaultWindowsPath);
    setState(() {
      _loading = false;
    });
    if (widget.startSpeedTest) await _download(testOnly: true);
  }

  Future<void> _download({bool testOnly = false}) async {
    if (_path.text.trim().isEmpty) {
      setState(() {
        _message = 'Enter the APK path on this device.';
      });
      return;
    }
    final operationId = ++_operationId;
    setState(() {
      _busy = true;
      _downloadClock.reset();
      _downloadClock.start();
      _bytesPerSecond = 0;
      _averageRate = 0;
      _rate.reset();
      _rate.sample(0, Duration.zero);
      _cancelled = false;
      _downloadFailed = false;
      _message = null;
      _prepared = null;
      _received = 0;
      _total = 0;
      _networkRate = null;
      _testPhase = testOnly ? 'Network-only test (1 of 2)' : null;
    });
    _rateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_busy) return;
      setState(() {
        _bytesPerSecond = _rate.sample(_received, _downloadClock.elapsed);
      });
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _path.text.trim());
      if (testOnly) {
        _networkRate = await AppUpdate.benchmarkNetwork(
          widget.session,
          _path.text,
          cancelled: () => _cancelled || !mounted,
          onProgress: (n, total) {
            if (mounted && operationId == _operationId && !_cancelled) {
              setState(() {
                _received = n;
                _total = total;
                _averageRate =
                    n /
                    (_downloadClock.elapsedMicroseconds / 1000000).clamp(
                      0.001,
                      double.infinity,
                    );
              });
            }
          },
        );
        if (_cancelled || !mounted) return;
        setState(() {
          _received = 0;
          _total = 0;
          _testPhase = 'APK download test (2 of 2)';
          _downloadClock.reset();
          _rate.reset();
          _rate.sample(0, Duration.zero);
          _bytesPerSecond = 0;
          _averageRate = 0;
        });
      }
      final prepared = await AppUpdate.download(
        widget.session,
        _path.text,
        deviceId: widget.device.id,
        cancelled: () => _cancelled || !mounted,
        onProgress: (n, total) {
          if (mounted && operationId == _operationId && !_cancelled) {
            setState(() {
              _received = n;
              _total = total;
              final seconds = _downloadClock.elapsedMilliseconds / 1000;
              _averageRate = seconds > 0 ? n / seconds : 0;
            });
          }
        },
      );
      if (!mounted || _cancelled) {
        await AppUpdate.cancel(prepared.id);
        return;
      }
      if (testOnly) {
        await AppUpdate.cancel(prepared.id);
        if (mounted) {
          setState(
            () => _message =
                'Network-only: ${(_networkRate! / 1048576).toStringAsFixed(2)} MB/s.\nAPK download: ${(_averageRate / 1048576).toStringAsFixed(2)} MB/s (including setup and file writes).\nSimilar results suggest the network/SSH path is limiting speed; a much slower APK result suggests phone-side processing.',
          );
        }
        return;
      }
      setState(() {
        _prepared = prepared;
        _message = 'APK verified. Ready to install.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadFailed = !_cancelled;
          _message = _cancelled ? 'Download cancelled.' : 'Download failed: $e';
        });
      }
    } finally {
      _rateTimer?.cancel();
      _downloadClock.stop();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
    });
    try {
      final result = await AppUpdate.install(_prepared!.id);
      if (mounted) {
        setState(() {
          _message = result == 'permission_required'
              ? 'Allow Node Cockpit to install apps, return here, then tap Install update again.'
              : 'Confirm the update in Android’s installer. Reopen Node Cockpit after installation.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _rateTimer?.cancel();
    // Keep a verified APK available to Android's installer after leaving.
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Update Node Cockpit')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Download from ${widget.device.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_busy && _testPhase != null) Text(_testPhase!),
          if (_testPhase != null)
            const Text(
              'Two passes: network only, then download and verification. Test copies are discarded.',
            ),
          Text(
            'Connection: ${widget.session.connectionRoute ?? 'SSH'} · ${widget.session.connectedHost ?? widget.device.host}',
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PerformanceScreen(session: widget.session),
              ),
            ),
            icon: const Icon(Icons.network_check),
            label: const Text('Connection diagnostics'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _loading
                ? null
                : () => _download(testOnly: true),
            icon: const Icon(Icons.speed),
            label: const Text('Test download speed'),
          ),
          const Text('Keep the update PC awake while downloading.'),
          const SizedBox(height: 20),
          TextField(
            controller: _path,
            enabled: !_busy && !_loading,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'APK path on the remote device',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (_busy) ...[
            LinearProgressIndicator(
              value: _total > 0 ? (_received / _total).clamp(0, 1) : null,
            ),
            const SizedBox(height: 8),
            Text(
              _total > 0
                  ? '${(_received / 1048576).toStringAsFixed(1)} / ${(_total / 1048576).toStringAsFixed(1)} MB · ${(_bytesPerSecond / 1048576).toStringAsFixed(2)} MB/s'
                  : 'Preparing…',
            ),
            if (_total > 0 && _received == _total)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Finishing download and verification…'),
              ),
            if (_total > 0 &&
                _received < _total &&
                _rate.idleFor(_downloadClock.elapsed).inSeconds >= 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Waiting for data · ${_rate.idleFor(_downloadClock.elapsed).inSeconds}s since last progress',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
          if (_prepared != null) ...[
            const SizedBox(height: 16),
            Text(
              'Installed: ${_prepared!.details['installedVersion']} (${_prepared!.details['installedBuild']})\nDownloaded: ${_prepared!.details['version']} (${_prepared!.details['build']})',
            ),
            const SizedBox(height: 8),
            const Text(
              'Package and signing key match. Your saved devices and settings will be preserved.',
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(
                _message!,
                style: _downloadFailed
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _loading
                ? null
                : _prepared == null
                ? _download
                : _install,
            icon: Icon(
              _prepared == null ? Icons.download : Icons.system_update,
            ),
            label: Text(
              _prepared != null
                  ? 'Install update'
                  : _downloadFailed
                  ? 'Retry download'
                  : 'Download update',
            ),
          ),
          if (_busy && _prepared == null)
            TextButton(
              onPressed: () {
                _cancelled = true;
              },
              child: const Text('Cancel download'),
            ),
          if (!_busy && _prepared != null)
            TextButton(
              onPressed: _download,
              child: const Text('Download again'),
            ),
        ],
      ),
    ),
  );
}
