import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/carrier_selection_dialog.dart';
import '../customization/customization_health.dart';
import '../customization/local_customization.dart';
import '../customization/native_liquid_controls.dart';
import '../customization/saved_setup_sheet.dart';
import '../customization/settings_controls.dart';
import '../customization/text_tone_control.dart';
import '../services/app_shortcut_navigation.dart';

import 'app_network_screen.dart';
import 'battery_usage_screen.dart';
import 'button_shortcuts_screen.dart';
import 'camera_ring_screen.dart';
import 'clipboard_shelf_screen.dart';
import 'customization_health_screen.dart';
import 'device_snapshot_screen.dart';
import 'devices_screen.dart';
import 'edge_actions_screen.dart';
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

  Map<String, String> _edgeAppRules() => Map<String, String>.from(
    jsonDecode(_section('config')['edgePanelAppRules'] as String? ?? '{}')
        as Map,
  );

  Future<void> _selectEdgeApps({
    bool chooseContext = false,
    String? foregroundPackage,
    String? foregroundLabel,
    List<Map<String, dynamic>>? catalog,
  }) async {
    try {
      final apps =
          catalog ??
          ((await LocalCustomization.call('launcherApps', {
                    'includeSelf': true,
                    'edgeShortcuts': true,
                  }))['apps']
                  as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      final rules = _edgeAppRules();
      final defaultApps = _section('config')['edgePanelApps'] as String? ?? '';
      final current =
          (foregroundPackage == null
                  ? defaultApps
                  : rules[foregroundPackage] ?? '')
              .split(RegExp('[,+]'))
              .where((value) => value.isNotEmpty && value != foregroundPackage)
              .toSet();
      final selected = Set<String>.from(current);
      final contextual = foregroundPackage != null;
      final appLabels = {
        for (final app in apps)
          app['package'] as String: app['label'] as String,
      };
      var query = '';
      if (!mounted) return;
      final choices = [
        ...apps.where((app) => !chooseContext || app['builtin'] != true),
        if (chooseContext)
          for (final package in rules.keys)
            if (!appLabels.containsKey(package))
              {'package': package, 'label': package},
      ];
      final response = await showDialog<Object>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = choices.where((app) {
              if (contextual &&
                  (app['package'] == foregroundPackage ||
                      selected.contains(app['package']))) {
                return false;
              }
              final needle = query.toLowerCase();
              return needle.isEmpty ||
                  (app['label'] as String).toLowerCase().contains(needle) ||
                  (app['package'] as String).toLowerCase().contains(needle);
            }).toList();
            return AlertDialog(
              title: Text(
                chooseContext
                    ? 'Choose the app you’re using'
                    : foregroundLabel == null
                    ? 'Favorites'
                    : 'Shortcuts for $foregroundLabel',
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 480,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search apps',
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length + (contextual ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (contextual && index == 0) {
                            final theme = Theme.of(context);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Shortcuts on this panel',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const Text(
                                    'The app you’re using is skipped.',
                                  ),
                                  if (selected.isEmpty)
                                    const Text('No shortcuts selected.')
                                  else
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final package in selected)
                                          InputChip(
                                            label: Text(
                                              appLabels[package] ??
                                                  '$package (unavailable)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onDeleted: () => setDialogState(
                                              () => selected.remove(package),
                                            ),
                                          ),
                                      ],
                                    ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Add shortcuts',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ],
                              ),
                            );
                          }
                          final app = filtered[index - (contextual ? 1 : 0)];
                          final packageName = app['package'] as String;
                          final icon = app['icon'] as String?;
                          final graphic = icon == null || icon.isEmpty
                              ? const Icon(Icons.apps)
                              : Image.memory(
                                  base64Decode(icon),
                                  width: 40,
                                  height: 40,
                                  gaplessPlayback: true,
                                );
                          if (chooseContext) {
                            final hasRule = rules.containsKey(packageName);
                            return ListTile(
                              leading: graphic,
                              title: Text(app['label'] as String),
                              subtitle: Text(
                                hasRule
                                    ? '${rules[packageName]!.split(',').length} custom shortcuts'
                                    : packageName,
                              ),
                              onTap: hasRule || rules.length < 16
                                  ? () => Navigator.pop(dialogContext, app)
                                  : null,
                            );
                          }
                          if (contextual) {
                            return ListTile(
                              leading: graphic,
                              title: Text(app['label'] as String),
                              trailing: const Icon(Icons.add),
                              onTap: selected.length >= 12
                                  ? null
                                  : () => setDialogState(
                                      () => selected.add(packageName),
                                    ),
                            );
                          }
                          return CheckboxListTile(
                            value: selected.contains(packageName),
                            secondary: graphic,
                            title: Text(app['label'] as String),
                            subtitle: Text(
                              packageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged:
                                selected.length >= 12 &&
                                    !selected.contains(packageName)
                                ? null
                                : (value) => setDialogState(() {
                                    if (value == true) {
                                      selected.add(packageName);
                                    } else {
                                      selected.remove(packageName);
                                    }
                                  }),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                if (foregroundPackage != null &&
                    rules.containsKey(foregroundPackage))
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, 'default'),
                    child: const Text('Use Favorites'),
                  ),
                if (!chooseContext)
                  FilledButton(
                    onPressed: foregroundPackage != null && selected.isEmpty
                        ? null
                        : () => Navigator.pop(dialogContext, true),
                    child: const Text('Save'),
                  ),
              ],
            );
          },
        ),
      );
      if (!mounted) return;
      if (response is Map<String, dynamic>) {
        await _selectEdgeApps(
          foregroundPackage: response['package'] as String,
          foregroundLabel: response['label'] as String,
          catalog: apps,
        );
      } else if (foregroundPackage != null &&
          (response == true || response == 'default')) {
        final updated = _edgeAppRules();
        if (response == 'default') {
          updated.remove(foregroundPackage);
        } else {
          updated[foregroundPackage] = selected.join(',');
        }
        await _apply('edgePanelAppRules', jsonEncode(updated));
      } else if (response == true) {
        final groups = ((_section('config')['edgePanelApps'] as String?) ?? '')
            .split(',');
        final remaining = Set<String>.from(selected);
        final items = <String>[];
        for (final group in groups) {
          final members = group.split('+').where(remaining.contains).toList();
          if (members.isNotEmpty) {
            items.add(members.join('+'));
            remaining.removeAll(members);
          }
        }
        items.addAll(remaining);
        await _apply('edgePanelApps', items.join(','));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

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
                    subtitle: _edgePanelSummary(_data),
                    icon: Icons.view_sidebar_outlined,
                    onTap: () => _openFeature(
                      'Edge panel',
                      _edgePanelFeature,
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

  Widget _edgeSlider({
    required String title,
    required String keyName,
    required int min,
    required int max,
    required int fallback,
    String suffix = ' dp',
  }) {
    final value = ((_section('config')[keyName] as num?)?.toInt() ?? fallback)
        .clamp(min, max);
    return CustomizationSlider(
      title: title,
      value: value,
      min: min,
      max: max,
      suffix: suffix,
      onChanged: _busy ? null : (v) => _previewSetting(keyName, v),
      onChangeEnd: _busy ? null : (v) => _apply(keyName, v),
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

  Future<void> _installCarrier({required bool update}) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          update ? 'Update carrier backend?' : 'Install carrier backend?',
        ),
        content: Text(
          update
              ? 'This replaces the old bundled database with a firmware-local generator. Disabled overrides stay disabled. Reboot to finish the backend update, then enable it when ready.'
              : 'This installs a disabled KernelSU backend. After reboot, enable it to derive Tunisie Telecom and Orange mappings from the current vendor database. Unsupported database layouts stay stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(update ? 'Update' : 'Install'),
          ),
        ],
      ),
    );
    if (yes == true) await _run('installCarrier');
  }

  Future<void> _chooseCarriers(Map<String, dynamic> carrier) async {
    final current = '${carrier['selectedCarriers'] ?? '60502,60501'}'
        .split(',')
        .toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => CarrierSelectionDialog(
        selected: current,
        load: (query) =>
            LocalCustomization.call('carrierCatalog', {'query': query}),
      ),
    );
    if (!mounted ||
        result == null ||
        (result.length == current.length && result.containsAll(current))) {
      return;
    }
    await _run(
      'configureCarriers',
      arguments: {'carriers': (result.toList()..sort()).join(',')},
    );
  }

  Future<void> _setCarrierEnabled(bool enabled) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          enabled ? 'Enable carrier override?' : 'Restore stock behavior?',
        ),
        content: Text(
          enabled
              ? 'At the next boot, the backend will copy the current vendor database, resolve its stock 5G profile and patch only the selected carrier mappings. Unsupported layouts stay stock. A stock backup is retained.'
              : 'KernelSU will stop exposing the cfgdb override after the next reboot. The stock vendor database itself has never been modified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(enabled ? 'Enable' : 'Restore stock'),
          ),
        ],
      ),
    );
    if (yes == true) await _run(enabled ? 'enableCarrier' : 'disableCarrier');
  }

  String _carrierSims(Map<String, dynamic> carrier) {
    final sims =
        (carrier['activeSims'] as List?)?.whereType<Map>().toList() ?? const [];
    if (sims.isEmpty) return 'No supported SIM details';
    return sims.map((s) => '${s['name']} · ${s['mccmnc']}').join('\n');
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

  Widget _line(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Expanded(child: Text('$value', textAlign: TextAlign.end)),
      ],
    ),
  );
  Future<void> _openHealth() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomizationHealthScreen(initialData: _data),
      ),
    );
    if (mounted) _run('probe');
  }

  String _edgePanelSummary(Map<String, dynamic> data) {
    final config = healthSection(data, 'config');
    if (config['emergencyDisabled'] == true) return 'Stopped by recovery';
    if (config['edgePanelEnabled'] != true) return 'Off';
    if (data['supported'] != true) return 'Android build not validated';
    if ((data['safetyLeaseRemainingMs'] as num? ?? 0) <= 0) {
      return 'Waiting for safety check';
    }
    final hook = healthSection(data, 'hook');
    return _hookReady(hook)
        ? 'Active · swipe from the right edge'
        : 'Waiting for System UI';
  }

  Widget _edgePanelFeature(Map<String, dynamic> data) {
    final config = healthSection(data, 'config');
    final enabled = config['edgePanelEnabled'] == true;
    final panelSide = config['edgePanelSide'] as String? ?? 'right';
    final requirementsMet = hasSystemUiCapabilities(data);
    final quickApps = ((config['edgePanelApps'] as String?) ?? '')
        .split(',')
        .where((value) => value.isNotEmpty)
        .length;
    final appRuleCount = _edgeAppRules().length;
    return CustomizationCard('Edge panel', [
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable edge panel'),
        subtitle: const Text(
          'Swipe inward or tap the handle on the selected edge',
        ),
        value: enabled,
        onChanged: _busy ? null : (value) => _apply('edgePanelEnabled', value),
      ),

      if (!enabled && !requirementsMet)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            data['supported'] == true
                ? 'Complete Setup assistant before enabling this feature.'
                : 'This Android build is not validated; SystemUI features remain blocked.',
          ),
        ),
      const Divider(height: 30),
      const SizedBox(height: 10),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apps),
        title: const Text('Favorites'),
        subtitle: Text(
          quickApps == 0 ? 'No apps selected' : '$quickApps selected',
        ),
        trailing: const Icon(Icons.add),
        onTap: _busy ? null : _selectEdgeApps,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.swap_horiz),
        title: const Text('App-specific shortcuts'),
        subtitle: Text(
          appRuleCount == 0
              ? 'Show different shortcuts in selected apps'
              : '$appRuleCount of 16 app-specific lists',
        ),
        onTap: _busy ? null : () => _selectEdgeApps(chooseContext: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune),
        title: const Text('Panel actions'),
        subtitle: const Text('Buttons, order, columns, icon size and labels'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy
            ? null
            : () async {
                final raw = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: edgeActionsRoute),
                    builder: (_) => const EdgeActionsScreen(),
                  ),
                );
                if (raw != null && mounted) {
                  setState(
                    () => _data = {
                      ..._data,
                      'config': {
                        ..._section('config'),
                        'edgePanelActions': raw,
                      },
                    },
                  );
                  _featureRevision.value++;
                }
              },
      ),
      _edgeSlider(
        title: 'Panel width',
        keyName: 'edgePanelWidth',
        min: 120,
        max: 360,
        fallback: 260,
      ),
      _edgeSlider(
        title: 'Panel height',
        keyName: 'edgePanelHeight',
        min: 240,
        max: 720,
        fallback: 520,
      ),
      const Divider(height: 30),
      Text(
        'Handle appearance and position',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: panelSide,
        decoration: const InputDecoration(labelText: 'Screen edge'),
        items: const [
          DropdownMenuItem(value: 'right', child: Text('Right')),
          DropdownMenuItem(value: 'left', child: Text('Left')),
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) _apply('edgePanelSide', value);
              },
      ),
      TextToneControl(
        value: (config['edgePanelTextTone'] as num?)?.toInt() ?? -1,
        busy: _busy,
        onChanged: (v, transient) =>
            _applyLiveSetting('edgePanelTextTone', v),
      ),
      NativeLiquidControls(
        raw: (config['edgePanelNativeGlass'] as String?) ?? '{}',
        onChanged: (value) =>
            _applyLiveSetting('edgePanelNativeGlass', value),
      ),
      _edgeSlider(
        title: 'Vertical position',
        keyName: 'edgePanelPosition',
        min: 5,
        max: 95,
        fallback: 50,
        suffix: '%',
      ),
      _edgeSlider(
        title: 'Handle height',
        keyName: 'edgeHandleHeight',
        min: 40,
        max: 120,
        fallback: 72,
      ),
      const SizedBox(height: 8),
    ], icon: Icons.view_sidebar_outlined);
  }

  String _carrierSummary(Map<String, dynamic> carrier) =>
      carrier['active'] == true
      ? 'Active'
      : carrier['rebootRequired'] == true
      ? 'Change waiting for reboot'
      : carrier['installed'] == true
      ? 'Installed · '
      : 'Backend not installed';

  Widget _carrierFeature(Map<String, dynamic> data) {
    final carrier = healthSection(data, 'carrier');
    return CustomizationCard('Carrier profile override', [
      Text(
        carrier['active'] == true
            ? 'Active'
            : carrier['rebootRequired'] == true
            ? 'Change waiting for reboot'
            : carrier['installed'] == true
            ? 'Installed · ${carrier['moduleState'] ?? 'unknown'}'
            : 'Backend not installed',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      _line('Selected carriers', carrier['selectedCarriers'] ?? '60502,60501'),
      if (carrier['installed'] == true && carrier['updateRequired'] != true)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _chooseCarriers(carrier),
          icon: const Icon(Icons.search),
          label: const Text('Choose carriers'),
        ),
      _line('Mode', 'Firmware-local'),
      _line('SIMs', _carrierSims(carrier)),
      _line(
        'Current carrier ID',
        (carrier['currentCarrierId'] as num? ?? -1) > 0
            ? carrier['currentCarrierId']
            : 'Not reported',
      ),
      _line('Intended profile', carrier['intendedProfile'] ?? '—'),
      _line('Data network', carrier['dataNetworkName'] ?? '—'),
      if (carrier['nrAvailable'] != null)
        _line('NR available', carrier['nrAvailable']),
      if (carrier['endcAvailable'] != null)
        _line('EN-DC available', carrier['endcAvailable']),
      if (carrier['nrState'] != null) _line('NR state', carrier['nrState']),
      if (carrier['nrFrequencyRange'] != null)
        _line('NR frequency range', carrier['nrFrequencyRange']),
      _line(
        'Configuration',
        carrier['rebootRequired'] == true && carrier['sourceFound'] != 'true'
            ? 'Staged · generates from current firmware after reboot'
            : carrier['configurationValid'] == true
            ? 'Current vendor copy and selected mappings verified'
            : carrier['databaseCompatible'] == true &&
                  carrier['moduleState'] == 'disabled'
            ? 'Compatible vendor database · generates when enabled'
            : carrier['sourceFound'] == 'true'
            ? 'Unexpected database'
            : 'Not installed',
      ),
      _line(
        'Systemless override',
        carrier['mounted'] == true ? 'Mounted' : 'Not mounted',
      ),
      if (carrier['supportedCarrierDetected'] != true)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'No selected carrier is currently detected. You can configure carriers before inserting their SIMs.',
          ),
        ),
      if (carrier['rebootRequired'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Reboot required. Radio or airplane-mode cycling is not used because the modem may retain the previous database.',
          ),
        ),
      if (carrier['lastMount'] != null && '${carrier['lastMount']}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${carrier['lastMount']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (carrier['installed'] != true)
            FilledButton.icon(
              onPressed: _busy || carrier['backendAvailable'] != true
                  ? null
                  : () => _installCarrier(update: false),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Install backend'),
            ),
          if (carrier['updateRequired'] == true)
            FilledButton.icon(
              onPressed: _busy || carrier['backendAvailable'] != true
                  ? null
                  : () => _installCarrier(update: true),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Update backend'),
            ),
          if (carrier['installed'] == true &&
              carrier['updateRequired'] != true &&
              carrier['rebootRequired'] != true &&
              carrier['moduleState'] == 'disabled')
            FilledButton.icon(
              onPressed: _busy || carrier['databaseCompatible'] != true
                  ? null
                  : () => _setCarrierEnabled(true),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Enable override'),
            ),
          if (carrier['installed'] == true &&
              carrier['rebootRequired'] != true &&
              carrier['moduleState'] == 'enabled')
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _setCarrierEnabled(false),
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restore stock'),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Carrier IDs and wildcard_5g are resolved from this firmware. A compatible cfgdb is required; this does not unlock every modem or guarantee network 5G availability.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ], icon: Icons.network_cell_outlined);
  }

  bool _hookReady(Map<String, dynamic> hook) =>
      hook['fresh'] == true &&
      hook['state'] != 'unsupported' &&
      hook['state'] != 'error';

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
          _line(
            'Vector manager',
            vectorInstalled ? 'Installed' : 'Not installed',
          ),
          _line(
            'SystemUI',
            frameworkConnected
                ? '${xp['name']} connected'
                : hookReady
                ? 'Hook bridge active'
                : 'Not connected',
          ),
          _line(
            'Root',
            root['authorized'] == true ? 'KernelSU verified' : 'Not verified',
          ),
          _line(
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
              subtitle: _carrierSummary(_section('carrier')),
              icon: Icons.network_cell_outlined,
              onTap: () async {
                await _run('probe', arguments: {'requestRoot': true});
                if (mounted) {
                  await _openFeature(
                    'Carrier profile override',
                    _carrierFeature,
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
