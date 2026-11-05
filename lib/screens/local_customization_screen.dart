import 'dart:async';
import 'camera_ring_screen.dart';
import 'notification_undo_screen.dart';
import 'root_files_screen.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/local_customization.dart';
import '../customization/feature_registry.dart';
import '../customization/customization_health.dart';
import '../customization/network_indicator_preview.dart';
import '../customization/saved_setup_sheet.dart';
import '../customization/text_tone_control.dart';
import '../customization/native_liquid_controls.dart';
import 'customization_health_screen.dart';
import 'devices_screen.dart';
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
  Timer? _networkHealthRefresh;
  bool _networkUpdateRunning = false;
  MapEntry<String, Object>? _pendingNetworkUpdate;
  static const _liveNetworkKeys = {
    'textSize',
    'stackedTextSize',
    'arrowScale',
    'indicatorHeight',
    'rateWidth',
    'arrowGap',
    'directionGap',
    'iconGap',
    'verticalOffset',
    'horizontalPosition',
    'unitGap',
    'unitScale',
    'thresholdKB',
  };
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
          ModalRoute.of(context)?.isCurrent != false) {
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
    _networkHealthRefresh?.cancel();
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
          !_networkUpdateRunning) {
        setState(() => _data = result);
        _featureRevision.value++;
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
      setState(() => _data = {..._data, 'config': config});
      _featureRevision.value++;
      if (key == 'edgePanelEnabled' || key == 'enabled') {
        await _run('apply', arguments: {'config': jsonEncode(config)});
        return;
      }
      try {
        final result = await LocalCustomization.call(
          'applyVisual',
          {'config': jsonEncode(config)},
        );
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
        _networkUpdateRunning ||
        _pendingNetworkUpdate != null) {
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

  Future<void> _selectEdgeApps() async {
    try {
      final result = await LocalCustomization.call('launcherApps');
      final apps = ((result['apps'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final current = ((_section('config')['edgePanelApps'] as String?) ?? '')
          .split(RegExp('[,+]'))
          .where((value) => value.isNotEmpty)
          .toSet();
      final selected = Set<String>.from(current);
      final search = TextEditingController();
      var query = '';
      if (!mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = apps.where((app) {
              final needle = query.toLowerCase();
              return needle.isEmpty ||
                  (app['label'] as String).toLowerCase().contains(needle) ||
                  (app['package'] as String).toLowerCase().contains(needle);
            }).toList();
            return AlertDialog(
              title: const Text('Quick-launch apps'),
              content: SizedBox(
                width: double.maxFinite,
                height: 480,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search apps',
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final app = filtered[index];
                          final packageName = app['package'] as String;
                          final icon = app['icon'] as String?;
                          return CheckboxListTile(
                            value: selected.contains(packageName),
                            secondary: icon == null || icon.isEmpty
                                ? const Icon(Icons.apps)
                                : Image.memory(
                                    base64Decode(icon),
                                    width: 40,
                                    height: 40,
                                    gaplessPlayback: true,
                                  ),
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
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );
      search.dispose();
      if (save == true) {
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
  void _liveNetworkSetting(String key, Object value) {
    _networkHealthRefresh?.cancel();
    _previewSetting(key, value);
    _visualRequestId++; // An older response must not rewind the local thumb.
    _pendingNetworkUpdate = MapEntry(key, value);
    if (!_networkUpdateRunning) unawaited(_flushNetworkSettings());
  }

  Future<void> _flushNetworkSettings() async {
    _networkUpdateRunning = true;
    try {
      while (_pendingNetworkUpdate != null) {
        final update = _pendingNetworkUpdate!;
        _pendingNetworkUpdate = null;
        await _apply(update.key, update.value);
      }
    } finally {
      _networkUpdateRunning = false;
      _networkHealthRefresh?.cancel();
      if (mounted) {
        _networkHealthRefresh = Timer(const Duration(seconds: 1), () {
          if (mounted && !_networkUpdateRunning) {
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
    unawaited(_run('probe', quiet: true));
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
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
                  onPressed: _busy
                      ? null
                      : () => _restoreSetup(scope: saveScope),
                  icon: const Icon(Icons.restore_rounded),
                ),
              if (saveScope == null) _setupMenu(),
              IconButton(
                tooltip: 'Refresh',
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
            child: ValueListenableBuilder<int>(
              valueListenable: _featureRevision,
              builder: (context, _, _) {
                final controls = ListView(
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [content(_data)],
                );
                if (title != 'Network speed') return controls;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: NetworkIndicatorPreview(
                        config: _section('config'),
                        onPositionChanged: _busy
                            ? null
                            : (value) => _liveNetworkSetting(
                                'horizontalPosition',
                                value,
                              ),
                      ),
                    ),
                    Expanded(child: controls),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
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

  Widget _tuningSlider({
    required String title,
    required String keyName,
    required int min,
    required int max,
    required int fallback,
    String suffix = ' dp',
  }) {
    final value = ((_section('config')[keyName] as num?)?.toInt() ?? fallback)
        .clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text('$value$suffix'),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value$suffix',
          onChanged: _busy
              ? null
              : (v) => _liveNetworkKeys.contains(keyName)
                    ? _liveNetworkSetting(keyName, v.round())
                    : _previewSetting(keyName, v.round()),
          onChangeEnd: _busy
              ? null
              : (v) {
                  if (_liveNetworkKeys.contains(keyName)) {
                    _liveNetworkSetting(keyName, v.round());
                  } else {
                    _apply(keyName, v.round());
                  }
                },
        ),
      ],
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
          update ? 'Update Tunisia 5G backend?' : 'Install Tunisia 5G backend?',
        ),
        content: Text(
          update
              ? 'This keeps the proven cfgdb mapping, adds managed health checks, and fixes file permissions. The current override remains in use until you reboot.'
              : 'This installs a KernelSU module that maps Tunisie Telecom and Orange Tunisia to the existing wildcard_5g modem profile. The vendor partition remains untouched. A reboot is required.',
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

  Future<void> _setCarrierEnabled(bool enabled) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          enabled ? 'Enable Tunisia 5G fix?' : 'Restore stock behavior?',
        ),
        content: Text(
          enabled
              ? 'KernelSU will expose the validated cfgdb override after the next reboot. Both supported Tunisian carriers are detected automatically.'
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

  Widget _card(
    String title,
    List<Widget> children, {
    IconData icon = Icons.info_outline,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
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
    final requirementsMet = edgePanelFeature.requirement.satisfied(
      ((data['capabilities'] as List?) ?? []).cast<String>().toSet(),
    );
    final quickApps = ((config['edgePanelApps'] as String?) ?? '')
        .split(',')
        .where((value) => value.isNotEmpty)
        .length;
    return _card('Edge panel', [
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
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Complete Setup assistant before enabling this feature.'),
        ),
      const Divider(height: 30),
      const SizedBox(height: 10),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apps),
        title: const Text('Quick-launch apps'),
        subtitle: Text(
          quickApps == 0 ? 'No apps selected' : '$quickApps selected',
        ),
        trailing: const Icon(Icons.add),
        onTap: _busy ? null : _selectEdgeApps,
      ),
      _tuningSlider(
        title: 'Panel width',
        keyName: 'edgePanelWidth',
        min: 120,
        max: 360,
        fallback: 260,
      ),
      _tuningSlider(
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
            _liveNetworkSetting('edgePanelTextTone', v),
      ),
      NativeLiquidControls(
        raw: (config['edgePanelNativeGlass'] as String?) ?? '{}',
        onChanged: (value) => _liveNetworkSetting('edgePanelNativeGlass', value),
      ),
      _tuningSlider(
        title: 'Vertical position',
        keyName: 'edgePanelPosition',
        min: 5,
        max: 95,
        fallback: 50,
        suffix: '%',
      ),
      _tuningSlider(
        title: 'Handle height',
        keyName: 'edgeHandleHeight',
        min: 40,
        max: 120,
        fallback: 72,
      ),
      const SizedBox(height: 8),
    ], icon: Icons.view_sidebar_outlined);
  }

  Widget _networkOptions(
    String title,
    String key,
    Map<String, String> options,
  ) {
    final current = (_section('config')[key] ?? options.keys.first).toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key-$current'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
        ),
        items: options.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) {
                  _liveNetworkSetting(
                    key,
                    key == 'decimals' || key == 'intervalMs'
                        ? int.parse(value)
                        : value,
                  );
                }
              },
      ),
    );
  }

  Widget _networkToggle(
    String title,
    String key, {
    bool fallback = false,
    String? subtitle,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: (_section('config')[key] as bool?) ?? fallback,
    onChanged: _busy ? null : (value) => _liveNetworkSetting(key, value),
  );

  Widget _networkSpeedFeature(Map<String, dynamic> data) {
    final config = healthSection(data, 'config');
    final enabled = config['enabled'] == true;
    final stacked = config['layout'] != 'inline';
    final requirementsMet = networkSpeedFeature.requirement.satisfied(
      ((data['capabilities'] as List?) ?? []).cast<String>().toSet(),
    );
    return _card('Preferences', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show in status bar'),
        subtitle: Text(indicatorStatus(data)),
        value: enabled,
        onChanged:
            _busy ||
                (!enabled && (data['canEnable'] != true || !requirementsMet))
            ? null
            : (value) => _apply('enabled', value),
      ),
      if (data['hookUpdateRequired'] == true)
        const Text('Restart System UI once to load the new renderer.'),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const Divider(),
      ExpansionTile(
        key: const PageStorageKey('network-appearance'),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        title: const Text('Appearance'),
        subtitle: const Text('Design, layout and weight'),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children:
                const {
                      'plain': 'Classic',
                      'pill': 'Pill',
                      'outline': 'Outline',
                      'mono': 'Monospace',
                      'glass': 'Glass',
                      'box': 'Box',
                      'split': 'Split',
                      'badge': 'Badge',
                    }.entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected:
                            (config['indicatorDesign'] ?? 'plain') == entry.key,
                        onSelected: _busy
                            ? null
                            : (_) => _liveNetworkSetting(
                                'indicatorDesign',
                                entry.key,
                              ),
                      ),
                    )
                    .toList(),
          ),
          _networkOptions('Layout', 'layout', const {
            'stacked': 'Value above unit',
            'inline': 'Value beside unit',
          }),
          _networkToggle('Bold values', 'boldValue'),
          _networkToggle('Bold labels and arrows', 'boldText'),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('network-units'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Text and units'),
        subtitle: const Text('Labels, precision and spacing'),
        children: [
          _networkOptions('Measure', 'units', const {
            'bytes': 'Bytes per second',
            'bits': 'Bits per second',
          }),
          _networkOptions('Unit label', 'unitLabel', const {
            'full': 'Full · KB/s',
            'unit': 'Without /s · KB',
            'prefix': 'Prefix only · K',
            'none': 'Hidden · value only',
            'custom': 'Custom suffix',
          }),
          if (config['unitLabel'] == 'custom')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextFormField(
                key: const ValueKey('network-unit-suffix'),
                initialValue: config['unitSuffix'] as String? ?? 'B/s',
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'Suffix after K, M or G',
                  hintText: 'B/s',
                  helperText: 'Example: B gives KB, MB or GB.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _liveNetworkSetting('unitSuffix', value),
              ),
            ),
          _networkOptions('Decimal places', 'decimals', const {
            '0': '0',
            '1': '1',
            '2': '2',
          }),
          if (config['unitLabel'] != 'none') ...[
            _tuningSlider(
              title: 'Value / unit gap',
              keyName: 'unitGap',
              min: -4,
              max: 8,
              fallback: 1,
            ),
            const Text(
              'Negative values tighten spacing; a minimum clearance keeps characters readable.',
            ),
            _tuningSlider(
              title: 'Unit size',
              keyName: 'unitScale',
              min: 50,
              max: 120,
              fallback: 100,
              suffix: '%',
            ),
          ],
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('network-layout'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Position and sizing'),
        subtitle: const Text('Drag the preview; sizes fit available space'),
        children: [
          _networkOptions('Restore an anchored position', 'position', const {
            'left': 'After clock',
            'right': 'Before system icons',
          }),
          _tuningSlider(
            title: stacked ? 'Maximum two-line size' : 'Maximum one-line size',
            keyName: stacked ? 'stackedTextSize' : 'textSize',
            min: stacked ? 4 : 8,
            max: stacked ? 12 : 18,
            fallback: stacked ? 8 : 10,
            suffix: ' sp',
          ),
          _tuningSlider(
            title: 'Indicator height',
            keyName: 'indicatorHeight',
            min: 13,
            max: 20,
            fallback: 16,
          ),
          _tuningSlider(
            title: 'Rate column width',
            keyName: 'rateWidth',
            min: 26,
            max: 64,
            fallback: 38,
          ),
          _tuningSlider(
            title: 'Vertical offset',
            keyName: 'verticalOffset',
            min: -3,
            max: 3,
            fallback: 0,
          ),
          _tuningSlider(
            title: 'Outer padding',
            keyName: 'iconGap',
            min: 0,
            max: 12,
            fallback: 6,
          ),
          if (config['showUpload'] != false)
            _tuningSlider(
              title: 'Download / upload gap',
              keyName: 'directionGap',
              min: 0,
              max: 12,
              fallback: 6,
            ),
          if (config['showArrows'] != false) ...[
            _tuningSlider(
              title: 'Arrow size',
              keyName: 'arrowScale',
              min: 60,
              max: 200,
              fallback: 140,
              suffix: '%',
            ),
            _tuningSlider(
              title: 'Arrow / value gap',
              keyName: 'arrowGap',
              min: -3,
              max: 6,
              fallback: 0,
            ),
          ],
          const Text(
            'Maximum text sizes shrink automatically when the status bar has less room. Each layout remembers its size.',
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('network-traffic'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Traffic and visibility'),
        subtitle: const Text('Directions, idle behavior and update rate'),
        children: [
          _networkToggle('Show upload speed', 'showUpload', fallback: true),
          _networkToggle('Direction arrows', 'showArrows', fallback: true),
          _networkToggle('Hide when idle', 'hideIdle', fallback: true),
          if (config['hideIdle'] != false)
            _tuningSlider(
              title: 'Idle threshold',
              keyName: 'thresholdKB',
              min: 0,
              max: 1024,
              fallback: 1,
              suffix: ' KB/s',
            ),
          _networkOptions('Traffic update interval', 'intervalMs', const {
            '500': '0.5 seconds',
            '1000': '1 second',
            '2000': '2 seconds',
            '5000': '5 seconds',
          }),
          const Text(
            'Appearance and position apply immediately, independently of the traffic update interval. Fullscreen apps can hide the status bar.',
          ),
        ],
      ),
    ], icon: Icons.speed);
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
    return _card('Tunisia 5G profile', [
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
      _line('Mode', 'Automatic'),
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
            ? 'Staged · verifies after reboot'
            : carrier['configurationValid'] == true
            ? 'Validated'
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
            'No supported Tunisian carrier is currently detected. The backend will remain ready for TUNTEL 60502 or Orange Tunisia 60501.',
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
              onPressed: _busy ? null : () => _setCarrierEnabled(true),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Enable fix'),
            ),
          if (carrier['installed'] == true &&
              carrier['updateRequired'] != true &&
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
        'Known mappings: 1731 → wildcard_5g and 1936 → wildcard_5g. No modem binaries, UE capabilities, or other carrier profiles are changed.',
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
    final hookReady = _hookReady(hook);
    return vector['installed'] == true &&
        (xp['connected'] == true || hookReady) &&
        (scope.contains('com.android.systemui') || hookReady) &&
        root['authorized'] == true &&
        root['moduleState'] == 'healthy';
  }

  String _setupSummary(Map<String, dynamic> data) {
    if (_setupComplete(data)) {
      return 'Vector, root access and recovery are ready';
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
    final hookReady = _hookReady(hook);
    final moduleReady = xp['connected'] == true || hookReady;
    final scope = (xp['scope'] as List?) ?? const [];
    final scopeReady = hookReady || scope.contains('com.android.systemui');
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

    return _card('Guided setup', [
      Text(
        firstIncomplete == 6
            ? 'Setup is complete. Phone customization can now use its required safety backends.'
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
        title: '2. Enable Node Cockpit',
        detail: moduleReady
            ? 'Vector module connected'
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
            : 'Add System UI to Node Cockpit’s scope',
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
            : 'Approve Node Cockpit when KernelSU asks',
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
    final hookReady =
        hook['fresh'] == true &&
        hook['state'] != 'unsupported' &&
        hook['state'] != 'error';
    final frameworkReady = xp['connected'] == true || hookReady;
    final recoveryReady = root['moduleState'] == 'healthy';
    if (vector['installed'] != true && !frameworkReady) {
      return 'Vector installation required';
    }
    if (frameworkReady && recoveryReady) return 'Vector and recovery ready';
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
    final frameworkReady = frameworkConnected || hookReady;
    final scope = (xp['scope'] as List?)?.cast<Object?>() ?? const [];
    final systemUiScoped = scope.contains('com.android.systemui');
    final String vectorGuidance;
    if (!vectorInstalled && !frameworkReady) {
      vectorGuidance = 'Vector is not installed. Install it first; Vector will discover Node Cockpit automatically from this app.';
    } else if (!frameworkReady) {
      vectorGuidance = 'Vector found Node Cockpit, but the module is inactive. Enable it and keep System UI in its scope.';
    } else if (frameworkConnected && !systemUiScoped) {
      vectorGuidance = 'Node Cockpit is enabled, but System UI is outside its scope. Add System UI in Vector.';
    } else if (!hookReady) {
      vectorGuidance = 'Node Cockpit is configured in Vector. Restart System UI or reboot to activate the hook.';
    } else {
      vectorGuidance = 'Node Cockpit is active in Vector for System UI.';
    }
    return Column(
      children: [
        _card('Backends', [
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
        _card('Recovery', [
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
        title: const Text('Node Cockpit'),
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
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CameraRingScreen())),
            ),
            _featureLink(
              title: 'Notification Undo',
              subtitle: 'Undo with a button or shake · drawer and lock screen',
              icon: Icons.undo,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationUndoScreen())),
            ),
            _featureLink(
              title: 'Root file explorer',
              subtitle: 'Read-only browsing · protected, temporary folder writes',
              icon: Icons.folder_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RootFilesScreen())),
            ),
            _featureLink(
              title: 'Network speed',
              subtitle: indicatorStatus(_data),
              icon: Icons.speed,
              onTap: () => _openFeature(
                'Network speed',
                _networkSpeedFeature,
                saveScope: 'network',
              ),
            ),
            _featureLink(
              title: 'Tunisia 5G profile',
              subtitle: _carrierSummary(_section('carrier')),
              icon: Icons.network_cell_outlined,
              onTap: () => _openFeature('Tunisia 5G profile', _carrierFeature),
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
