import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/customization_health.dart';
import '../customization/local_customization.dart';
import '../customization/saved_setup_sheet.dart';
import '../customization/settings_controls.dart';
import '../services/app_shortcut_navigation.dart';

import 'app_network_screen.dart';
import 'battery_usage_screen.dart';
import 'button_shortcuts_screen.dart';
import 'camera_ring_screen.dart';
import 'carrier_override_screen.dart';
import 'clipboard_shelf_screen.dart';
import 'customization_health_screen.dart';
import 'device_snapshot_screen.dart';
import 'devices_screen.dart';
import 'edge_panel_screen.dart';
import 'network_speed_screen.dart';
import 'notification_undo_screen.dart';
import 'photos_sources_screen.dart';
import 'root_files_screen.dart';
import 'settings_screen.dart';

class LocalCustomizationScreen extends StatefulWidget {
  const LocalCustomizationScreen({super.key});
  @override
  State<LocalCustomizationScreen> createState() =>
      _LocalCustomizationScreenState();
}

class _LocalCustomizationScreenState extends State<LocalCustomizationScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _data = {};
  final ValueNotifier<int> _featureRevision = ValueNotifier(0);
  bool _busy = false;
  bool _polling = false;
  bool _resumed = true;
  int _requestId = 0;
  int _visualRequestId = 0;
  int _writes = 0;
  String? _error;
  Timer? _poll;
  Route<void>? _networkSpeedRoute;
  Timer? _healthRefreshAfterWrite;
  bool _liveWriteRunning = false;
  MapEntry<String, Object>? _pendingLiveSetting;
  Map<String, dynamic> _section(String key) =>
      Map<String, dynamic>.from((_data[key] as Map?) ?? {});
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run('probe');
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_busy &&
          mounted &&
          _resumed &&
          (ModalRoute.of(context)?.isCurrent != false ||
              _networkSpeedRoute?.isCurrent == true)) {
        _run('probe', quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && !_busy) _run('probe');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _healthRefreshAfterWrite?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _featureRevision.dispose();
    super.dispose();
  }

  Future<void> _run(
    String operation, {
    Map<String, dynamic>? arguments,
    bool quiet = false,
  }) async {
    if (_busy || (quiet && _polling)) return;
    final requestId = ++_requestId;
    final visualRequestId = _visualRequestId;
    if (quiet) {
      _polling = true;
    } else {
      setState(() {
        _busy = true;
        _error = null;
      });
      _featureRevision.value++;
    }
    try {
      var result = await LocalCustomization.call(operation, arguments);
      if (operation == 'framework' ||
          operation == 'frameworkModule' ||
          operation == 'installVector' ||
          operation == 'installKernelSu' ||
          operation == 'kernelSu') {
        result = await LocalCustomization.call('probe');
      }
      if (mounted &&
          requestId == _requestId &&
          visualRequestId == _visualRequestId &&
          !_liveWriteRunning) {
        setState(() => _data = result);
        if (quiet) _featureRevision.value++;
      }
    } catch (e) {
      if (mounted && requestId == _requestId && !quiet) {
        setState(() => _error = '$e');
      }
    } finally {
      if (quiet) {
        _polling = false;
      } else if (mounted) {
        setState(() => _busy = false);
        _featureRevision.value++;
      }
    }
  }

  Future<void> _apply(String key, Object value) async {
    if (!mounted) return;
    _writes++;
    try {
      final visualRequestId = ++_visualRequestId;
      final config = _section('config');
      config[key] = value;
      if (key == 'position') config['horizontalPosition'] = -1;
      if (key == 'enabled') {
        await _run('apply', arguments: {'config': jsonEncode(config)});
        return;
      }
      setState(() => _data = {..._data, 'config': config});
      _featureRevision.value++;
      if (key == 'edgePanelEnabled') {
        await _run('apply', arguments: {'config': jsonEncode(config)});
        return;
      }
      try {
        final result = await LocalCustomization.call('applyVisual', {
          'config': jsonEncode(config),
        });
        if (mounted &&
            visualRequestId == _visualRequestId &&
            result['config'] is Map) {
          setState(() {
            _data = {
              ..._data,
              'config': Map<String, dynamic>.from(result['config'] as Map),
            };
            _error = null;
          });
          _featureRevision.value++;
        }
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    } finally {
      _writes--;
    }
  }

  Future<void> _flushSetupEdits() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_writes > 0 ||
        _liveWriteRunning ||
        _pendingLiveSetting != null) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Settings are still applying. Try saving again.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_error != null) {
      throw StateError('Resolve the settings error before saving a setup.');
    }
  }

  Future<SetupChoice?> _chooseSetup({
    String scope = 'all',
    bool restore = false,
  }) {
    final saved = ((_data['savedSetups'] as List?) ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    saved.sort(
      (a, b) => ((b['updatedAt'] ?? b['at']) as int).compareTo(
        (a['updatedAt'] ?? a['at']) as int,
      ),
    );
    return showModalBottomSheet<SetupChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) =>
          SavedSetupSheet(setups: saved, scope: scope, restore: restore),
    );
  }

  Future<void> _saveSetup({String scope = 'all'}) async {
    final choice = await _chooseSetup(scope: scope);
    if (choice == null || !mounted) return;
    try {
      await _flushSetupEdits();
      if (!mounted) return;
      await _run(
        choice.id == null ? 'saveSetup' : 'updateSetup',
        arguments: choice.id == null
            ? {'name': choice.name}
            : {'id': choice.id, 'scope': scope},
      );
      if (mounted && _error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              choice.id == null
                  ? 'New setup saved'
                  : '${setupScopeLabel(scope)} saved to your setup',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _restoreSetup({String scope = 'all'}) async {
    await _run('probe');
    if (!mounted) return;
    final choice = await _chooseSetup(scope: scope, restore: true);
    if (choice?.id == null || !mounted) return;
    try {
      await _flushSetupEdits();
      if (mounted) {
        await _run(
          'restoreSetup',
          arguments: {'id': choice!.id, 'scope': scope},
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _setupMenu() => PopupMenuButton<String>(
    tooltip: 'Saved device setups',
    onSelected: (value) {
      if (value == 'save') {
        _saveSetup();
      } else {
        _restoreSetup();
      }
    },
    enabled: !_busy,
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'save', child: Text('Save setup')),
      PopupMenuItem(value: 'restore', child: Text('Restore setup')),
    ],
    icon: const Icon(Icons.save_outlined),
  );

  // One in-flight write and one latest pending value keep a drag responsive
  // without building a queue of obsolete native settings operations.
  void _applyLiveSetting(String key, Object value) {
    _healthRefreshAfterWrite?.cancel();
    _previewSetting(key, value);
    _visualRequestId++; // An older response must not rewind the local thumb.
    _pendingLiveSetting = MapEntry(key, value);
    if (!_liveWriteRunning) unawaited(_flushLiveSettings());
  }

  Future<void> _flushLiveSettings() async {
    _liveWriteRunning = true;
    try {
      while (_pendingLiveSetting != null) {
        final update = _pendingLiveSetting!;
        _pendingLiveSetting = null;
        await _apply(update.key, update.value);
      }
    } finally {
      _liveWriteRunning = false;
      _healthRefreshAfterWrite?.cancel();
      if (mounted) {
        _healthRefreshAfterWrite = Timer(const Duration(seconds: 1), () {
          if (mounted && !_liveWriteRunning) {
            unawaited(_run('probe', quiet: true));
          }
        });
      }
    }
  }

  void _previewSetting(String key, Object value) {
    final config = _section('config')..[key] = value;
    if (key == 'position') config['horizontalPosition'] = -1;
    setState(() => _data = {..._data, 'config': config});
    _featureRevision.value++;
  }

  Future<void> _openFeature(
    String title,
    Widget Function(Map<String, dynamic>) content, {
    String? saveScope,
  }) async {
    final networkSpeed = saveScope == 'network';
    unawaited(_run('probe', quiet: true));
    final route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (saveScope != null)
              TextButton.icon(
                onPressed: _busy ? null : () => _saveSetup(scope: saveScope),
                icon: const Icon(Icons.save_outlined, size: 20),
                label: const Text('Save'),
              ),
            if (saveScope != null)
              IconButton(
                tooltip: 'Restore feature settings',
                onPressed: _busy ? null : () => _restoreSetup(scope: saveScope),
                icon: const Icon(Icons.restore_rounded),
              ),
            if (saveScope == null) _setupMenu(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy
                  ? null
                  : () => _run(
                      'probe',
                      arguments:
                          networkSpeed || title == 'Carrier profile override'
                          ? {'requestRoot': true}
                          : null,
                    ),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: SizedBox(
              height: 3,
              child: _busy ? const LinearProgressIndicator() : null,
            ),
          ),
        ),
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: _featureRevision,
            builder: (context, _, _) {
              final child = content(_data);
              if (networkSpeed) return child;
              return ListView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [child],
              );
            },
          ),
        ),
      ),
    );
    if (networkSpeed) _networkSpeedRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      if (_networkSpeedRoute == route) _networkSpeedRoute = null;
    }
    if (mounted) _run('probe');
  }

  Widget _featureLink({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );

  void _openUiFeatures() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (menuContext) => Scaffold(
          appBar: AppBar(title: const Text('UI features')),
          body: SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: _featureRevision,
              builder: (_, _, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _featureLink(
                    title: 'Edge panel',
                    subtitle: edgePanelSummary(_data),
                    icon: Icons.view_sidebar_outlined,
                    onTap: () => _openFeature(
                      'Edge panel',
                      (report) => EdgePanelScreen(
                        report: report,
                        busy: _busy,
                        onApply: _apply,
                        onPreview: _previewSetting,
                        onLiveChange: _applyLiveSetting,
                        onError: (e) => setState(() => _error = '$e'),
                      ),
                      saveScope: 'edge',
                    ),
                  ),
                  _featureLink(
                    title: 'Notification ring',
                    subtitle: 'Camera ring for pending notifications · app priorities',
                    icon: Icons.notifications_active_outlined,
                    onTap: () => Navigator.of(menuContext).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const CameraRingScreen(),
                      ),
                    ),
                  ),
                  _featureLink(
                    title: 'Notification Undo',
                    subtitle:
                        'Undo with a button or shake · drawer and lock screen',
                    icon: Icons.undo,
                    onTap: () => Navigator.of(menuContext).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const NotificationUndoScreen(),
                      ),
                    ),
                  ),
                  _featureLink(
                    title: 'Screen-off buttons',
                    subtitle: 'Assign volume gestures for when audio is idle',
                    icon: Icons.volume_up_outlined,
                    onTap: () => Navigator.of(menuContext).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const ButtonShortcutsScreen(),
                      ),
                    ),
                  ),
                  _featureLink(
                    title: 'Network speed',
                    subtitle: indicatorStatus(_data),
                    icon: Icons.speed,
                    onTap: () => _openFeature(
                      'Network speed',
                      (report) => NetworkSpeedScreen(
                        report: report,
                        busy: _busy,
                        error: _error,
                        onEnabledChanged: (value) => _apply('enabled', value),
                        onSettingChanged: _applyLiveSetting,
                      ),
                      saveScope: 'network',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _install() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install recovery backend?'),
        content: const Text(
          'Installs the bundled KernelSU ZIP for SystemUI restart monitoring. It has no system/vendor mounts or boot image changes. A reboot may be required. Disabled modules are never automatically re-enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (yes == true) await _run('install');
  }

  Future<void> _restartSystemUi() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart SystemUI?'),
        content: const Text(
          'The status bar and navigation UI will briefly restart. Customization is disabled first and stays disabled until you enable it again. The phone does not reboot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restart SystemUI'),
          ),
        ],
      ),
    );
    if (yes == true) await _run('restartSystemUi');
  }

  Future<void> _openHealth() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomizationHealthScreen(initialData: _data),
      ),
    );
    if (mounted) _run('probe');
  }

  bool _setupComplete(Map<String, dynamic> data) {
    final vector = healthSection(data, 'vector');
    final xp = healthSection(data, 'xposed');
    final hook = healthSection(data, 'hook');
    final root = healthSection(data, 'root');
    final scope = (xp['scope'] as List?) ?? const [];
    final hookDetected = systemUiHookDetected(hook);
    return vector['installed'] == true &&
        (xp['connected'] == true || hookDetected) &&
        (scope.contains('com.android.systemui') || hookDetected) &&
        root['authorized'] == true &&
        root['moduleState'] == 'healthy';
  }

  String _setupSummary(Map<String, dynamic> data) {
    if (_setupComplete(data)) {
      return data['supported'] == true
          ? 'Vector, root access and recovery are ready'
          : 'Setup complete · Android build not validated';
    }
    final root = healthSection(data, 'root');
    if (root['moduleState'] == 'pendingReboot') {
      return 'Recovery installed · reboot required';
    }
    return 'Finish the required integration steps';
  }

  Widget _setupStep({
    required String title,
    required String detail,
    required bool complete,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          complete ? Icons.check_circle : Icons.radio_button_unchecked,
          color: complete ? Colors.green : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _setupAssistantFeature(Map<String, dynamic> data) {
    final vector = healthSection(data, 'vector');
    final kernelsu = healthSection(data, 'kernelsu');
    final xp = healthSection(data, 'xposed');
    final hook = healthSection(data, 'hook');
    final root = healthSection(data, 'root');
    final vectorReady = vector['installed'] == true;
    final hookDetected = systemUiHookDetected(hook);
    final moduleReady = xp['connected'] == true || hookDetected;
    final scope = (xp['scope'] as List?) ?? const [];
    final scopeReady = hookDetected || scope.contains('com.android.systemui');
    final kernelSuReady = kernelsu['installed'] == true;
    final rootReady = root['authorized'] == true;
    final recoveryReady = root['moduleState'] == 'healthy';
    final recoveryState = '${root['moduleState'] ?? 'not checked'}';
    final firstIncomplete = !vectorReady
        ? 0
        : !moduleReady
        ? 1
        : !scopeReady
        ? 2
        : !kernelSuReady
        ? 3
        : !rootReady
        ? 4
        : !recoveryReady
        ? 5
        : 6;

    return CustomizationCard('Guided setup', [
      Text(
        firstIncomplete == 6
            ? data['supported'] == true
                  ? 'Setup is complete. Phone customization can now use its required safety backends.'
                  : 'Setup is complete. This Android build is not validated; SystemUI features remain blocked.'
            : 'Complete each step in order. Installation, root access and module activation always require your confirmation.',
      ),
      const SizedBox(height: 12),
      _setupStep(
        title: '1. Vector manager',
        detail: vectorReady ? 'Installed' : 'Required for System UI hooks',
        complete: vectorReady,
        action: firstIncomplete == 0
            ? FilledButton.icon(
                onPressed: _busy ? null : () => _run('installVector'),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Install Vector'),
              )
            : null,
      ),
      _setupStep(
        title: '2. Enable Wirehelm',
        detail: moduleReady
            ? xp['connected'] == true
                  ? 'Vector module connected'
                  : 'Module detected in SystemUI'
            : 'Enable the module from Vector’s Modules tab',
        complete: moduleReady,
        action: firstIncomplete == 1
            ? FilledButton.icon(
                onPressed: _busy ? null : () => _run('framework'),
                icon: const Icon(Icons.extension_outlined),
                label: const Text('Open Vector modules'),
              )
            : null,
      ),
      _setupStep(
        title: '3. System UI scope',
        detail: scopeReady
            ? 'System UI is included'
            : 'Add System UI to Wirehelm’s scope',
        complete: scopeReady,
        action: firstIncomplete == 2
            ? FilledButton.icon(
                onPressed: _busy ? null : () => _run('frameworkModule'),
                icon: const Icon(Icons.tune),
                label: const Text('Configure scope'),
              )
            : null,
      ),
      _setupStep(
        title: '4. KernelSU manager',
        detail: kernelSuReady
            ? 'Installed'
            : 'Required for the recovery backend',
        complete: kernelSuReady,
        action: firstIncomplete == 3
            ? FilledButton.icon(
                onPressed: _busy ? null : () => _run('installKernelSu'),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Get KernelSU'),
              )
            : null,
      ),
      _setupStep(
        title: '5. Root access',
        detail: rootReady
            ? 'KernelSU access verified'
            : 'Approve Wirehelm when KernelSU asks',
        complete: rootReady,
        action: firstIncomplete == 4
            ? FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('probe', arguments: {'requestRoot': true}),
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Check root access'),
              )
            : null,
      ),
      _setupStep(
        title: '6. Recovery backend',
        detail: recoveryReady
            ? 'Watchdog ready'
            : recoveryState == 'pendingReboot'
            ? 'Installed; reboot the phone to finish'
            : 'Current state: $recoveryState',
        complete: recoveryReady,
        action: firstIncomplete == 5 && recoveryState == 'absent'
            ? FilledButton.icon(
                onPressed: _busy ? null : _install,
                icon: const Icon(Icons.install_mobile_outlined),
                label: const Text('Install recovery'),
              )
            : firstIncomplete == 5 && recoveryState == 'disabled'
            ? FilledButton.icon(
                onPressed: _busy ? null : () => _run('kernelSu'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open KernelSU'),
              )
            : null,
      ),
    ], icon: Icons.fact_check_outlined);
  }

  String _systemSummary(Map<String, dynamic> data) {
    final root = healthSection(data, 'root');
    final xp = healthSection(data, 'xposed');
    final hook = healthSection(data, 'hook');
    final vector = healthSection(data, 'vector');
    final frameworkReady =
        xp['connected'] == true || systemUiHookDetected(hook);
    final recoveryReady = root['moduleState'] == 'healthy';
    if (vector['installed'] != true && !frameworkReady) {
      return 'Vector installation required';
    }
    if (frameworkReady && recoveryReady) {
      return data['supported'] == true
          ? 'Vector and recovery ready'
          : 'Module loaded · Android build not validated';
    }
    if (frameworkReady) return 'Vector ready · recovery needs attention';
    if (recoveryReady) return 'Recovery ready · Vector needs attention';
    return 'Setup or verification required';
  }

  Widget _systemIntegrationFeature(Map<String, dynamic> data) {
    final config = healthSection(data, 'config');
    final xp = healthSection(data, 'xposed');
    final root = healthSection(data, 'root');
    final hook = healthSection(data, 'hook');
    final vector = healthSection(data, 'vector');
    final vectorInstalled = vector['installed'] == true;
    final hookReady =
        hook['fresh'] == true &&
        hook['state'] != 'unsupported' &&
        hook['state'] != 'error';
    final frameworkConnected = xp['connected'] == true;
    final hookDetected = systemUiHookDetected(hook);
    final frameworkReady = frameworkConnected || hookDetected;
    final scope = (xp['scope'] as List?)?.cast<Object?>() ?? const [];
    final systemUiScoped =
        hookDetected || scope.contains('com.android.systemui');
    final String vectorGuidance;
    if (!vectorInstalled && !frameworkReady) {
      vectorGuidance = 'Vector is not installed. Install it first; Vector will discover Wirehelm automatically from this app.';
    } else if (!frameworkReady) {
      vectorGuidance = 'Vector found Wirehelm, but the module is inactive. Enable it and keep System UI in its scope.';
    } else if (frameworkConnected && !systemUiScoped) {
      vectorGuidance = 'Wirehelm is enabled, but System UI is outside its scope. Add System UI in Vector.';
    } else if (data['supported'] != true) {
      vectorGuidance = 'Wirehelm is detected in SystemUI. This Android build is not validated, so SystemUI features remain blocked.';
    } else if (!hookReady) {
      vectorGuidance = 'Wirehelm is configured in Vector. Restart System UI or reboot to activate the hook.';
    } else {
      vectorGuidance = 'Wirehelm is active in Vector for System UI.';
    }
    return Column(
      children: [
        CustomizationCard('Backends', [
          CustomizationDetail(
            'Vector manager',
            vectorInstalled ? 'Installed' : 'Not installed',
          ),
          CustomizationDetail(
            'SystemUI',
            frameworkConnected
                ? '${xp['name']} connected'
                : hookReady
                ? 'Hook bridge active'
                : 'Not connected',
          ),
          CustomizationDetail(
            'Root',
            root['authorized'] == true ? 'KernelSU verified' : 'Not verified',
          ),
          CustomizationDetail(
            'Recovery',
            root['moduleState'] == 'healthy'
                ? 'Watchdog ready'
                : root['moduleState'] ?? 'Not checked',
          ),
          if (root['probeWarning'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${root['probeWarning']}'),
            ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(vectorGuidance),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run('probe', arguments: {'requestRoot': true}),
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Check backends'),
              ),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        !vectorInstalled && !frameworkReady
                            ? 'installVector'
                            : !frameworkReady
                            ? 'framework'
                            : 'frameworkModule',
                      ),
                icon: Icon(
                  !vectorInstalled && !frameworkReady
                      ? Icons.download_outlined
                      : Icons.extension_outlined,
                ),
                label: Text(
                  !vectorInstalled && !frameworkReady
                      ? 'Install Vector'
                      : !frameworkReady
                      ? 'Enable in Vector'
                      : hookReady && (!frameworkConnected || systemUiScoped)
                      ? 'Open in Vector'
                      : 'Configure in Vector',
                ),
              ),
              if (root['moduleState'] == 'absent')
                FilledButton(
                  onPressed: _busy ? null : _install,
                  child: const Text('Set up recovery'),
                ),
            ],
          ),
          if (root['moduleState'] == 'pendingReboot')
            const Text('Recovery installed. Reboot manually when ready.'),
          if (root['moduleState'] == 'disabled')
            const Text(
              'Disabled by KernelSU or the user. Enable it in KernelSU when ready.',
            ),
        ], icon: Icons.extension_outlined),
        CustomizationCard('Recovery', [
          const Text(
            'Crash-loop protection and framework safe mode remain active. Restoring settings keeps the feature off until you enable it.',
          ),
          if ((config['recoveryReason'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('${config['recoveryReason']}'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run('disable'),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Disable customization'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _restoreSetup,
                child: const Text('Restore saved setup'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || root['moduleState'] != 'healthy'
                    ? null
                    : _restartSystemUi,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart SystemUI'),
              ),
            ],
          ),
        ], icon: Icons.health_and_safety_outlined),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wirehelm'),
        actions: [
          _setupMenu(),
          IconButton(
            tooltip: 'Remote devices',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
            icon: const Icon(Icons.devices_other_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Refresh health',
            onPressed: _busy ? null : () => _run('probe'),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: SizedBox(
            height: 3,
            child: _busy ? const LinearProgressIndicator() : null,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_section('config')['emergencyDisabled'] == true)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Customization paused by recovery'),
                      Text(
                        '${_section('config')['recoveryReason'] ?? 'Safety check required'}',
                      ),
                      const Text(
                        'Your saved choices are retained. Resume checks safety before applying them.',
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                'apply',
                                arguments: {
                                  'config': jsonEncode(_section('config')),
                                },
                              ),
                        child: const Text('Resume saved choices'),
                      ),
                    ],
                  ),
                ),
              ),
            Card.filled(
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.bookmarks_outlined,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your setups',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${((_data['savedSetups'] as List?) ?? []).length} saved · ready when you need them',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Keep a look you love. Update one feature or restore your entire setup.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _saveSetup(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Save setup'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _restoreSetup,
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('Restore setup'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Card(
                color: colors.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_error!),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.phone_android),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_data['device'] ?? 'This device'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Android ${_data['android'] ?? '—'} · ${_data['supported'] == true ? 'Build validated' : 'Compatibility not verified'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _featureLink(
              title: 'Setup assistant',
              subtitle: _setupSummary(_data),
              icon: _setupComplete(_data)
                  ? Icons.verified_outlined
                  : Icons.fact_check_outlined,
              onTap: () =>
                  _openFeature('Setup assistant', _setupAssistantFeature),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Text(
                'Features',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _featureLink(
              title: 'UI features',
              subtitle: 'Edge panel, notification tools and network speed',
              icon: Icons.dashboard_customize_outlined,
              onTap: _openUiFeatures,
            ),
            _featureLink(
              title: 'App manager',
              subtitle: 'Manage per-app network access',
              icon: Icons.app_settings_alt_outlined,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AppNetworkScreen()),
              ),
            ),
            _featureLink(
              title: 'Photos Sources',
              subtitle: 'Google Photos grouping, destinations and status',
              icon: Icons.photo_library_outlined,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const PhotosSourcesScreen()),
              ),
            ),
            _featureLink(
              title: 'Clipboard shelf',
              subtitle: 'Copied text, images and pinned clips',
              icon: Icons.content_copy,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  settings: const RouteSettings(name: clipboardShelfRoute),
                  builder: (_) => const ClipboardShelfScreen(),
                ),
              ),
            ),
            _featureLink(
              title: 'Battery usage',
              subtitle: 'Discharge history and customization activity',
              icon: Icons.history_outlined,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const BatteryUsageScreen()),
              ),
            ),
            _featureLink(
              title: 'What changed?',
              subtitle: 'Compare your phone with a saved snapshot',
              icon: Icons.history_outlined,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const DeviceSnapshotScreen()),
              ),
            ),
            _featureLink(
              title: 'Root file explorer',
              subtitle:
                  'Read-only browsing · protected, temporary folder writes',
              icon: Icons.folder_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RootFilesScreen(),
                ),
              ),
            ),
            _featureLink(
              title: 'Carrier profile override',
              subtitle: carrierOverrideStatus(_section('carrier')),
              icon: Icons.network_cell_outlined,
              onTap: () async {
                await _run('probe', arguments: {'requestRoot': true});
                if (mounted) {
                  await _openFeature(
                    'Carrier profile override',
                    (report) => CarrierOverrideScreen(
                      carrier: healthSection(report, 'carrier'),
                      busy: _busy,
                      onOperation: _run,
                    ),
                  );
                }
              },
            ),
            _featureLink(
              title: 'System integration',
              subtitle: _systemSummary(_data),
              icon: Icons.extension_outlined,
              onTap: () =>
                  _openFeature('System integration', _systemIntegrationFeature),
            ),
            _featureLink(
              title: 'Customization health',
              subtitle: 'Visibility, safety checks and recent events',
              icon: Icons.monitor_heart_outlined,
              onTap: _openHealth,
            ),
          ],
        ),
      ),
    );
  }
}
