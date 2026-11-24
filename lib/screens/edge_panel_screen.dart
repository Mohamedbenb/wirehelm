import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/customization_health.dart';
import '../customization/local_customization.dart';
import '../customization/native_liquid_controls.dart';
import '../customization/settings_controls.dart';
import '../customization/text_tone_control.dart';
import '../services/app_shortcut_navigation.dart';
import 'edge_actions_screen.dart';

String edgePanelSummary(Map<String, dynamic> data) {
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

bool _hookReady(Map<String, dynamic> hook) =>
    hook['fresh'] == true &&
    hook['state'] != 'unsupported' &&
    hook['state'] != 'error';

class EdgePanelScreen extends StatefulWidget {
  EdgePanelScreen({
    super.key,
    required this.report,
    required this.busy,
    required this.onApply,
    required this.onPreview,
    required this.onLiveChange,
    required this.onError,
  }) : config = healthSection(report, 'config');

  final Map<String, dynamic> report;
  final Map<String, dynamic> config;
  final bool busy;
  final Future<void> Function(String key, Object value) onApply;
  final void Function(String key, Object value) onPreview;
  final void Function(String key, Object value) onLiveChange;
  final ValueChanged<Object> onError;

  @override
  State<EdgePanelScreen> createState() => _EdgePanelScreenState();
}

class _EdgePanelScreenState extends State<EdgePanelScreen> {
  Map<String, String> _edgeAppRules() => Map<String, String>.from(
    jsonDecode(widget.config['edgePanelAppRules'] as String? ?? '{}') as Map,
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
      if (!mounted) return;
      final rules = _edgeAppRules();
      final defaultApps = widget.config['edgePanelApps'] as String? ?? '';
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
        await widget.onApply('edgePanelAppRules', jsonEncode(updated));
      } else if (response == true) {
        final groups = ((widget.config['edgePanelApps'] as String?) ?? '')
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
        await widget.onApply('edgePanelApps', items.join(','));
      }
    } catch (e) {
      if (mounted) widget.onError(e);
    }
  }

  Widget _edgeSlider({
    required String title,
    required String keyName,
    required int min,
    required int max,
    required int fallback,
    String suffix = ' dp',
  }) {
    final value = ((widget.config[keyName] as num?)?.toInt() ?? fallback).clamp(
      min,
      max,
    );
    return CustomizationSlider(
      title: title,
      value: value,
      min: min,
      max: max,
      suffix: suffix,
      onChanged: widget.busy ? null : (v) => widget.onPreview(keyName, v),
      onChangeEnd: widget.busy ? null : (v) => widget.onApply(keyName, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.report;
    final config = widget.config;
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
        onChanged: widget.busy
            ? null
            : (value) => widget.onApply('edgePanelEnabled', value),
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
        onTap: widget.busy ? null : _selectEdgeApps,
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
        onTap: widget.busy ? null : () => _selectEdgeApps(chooseContext: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune),
        title: const Text('Panel actions'),
        subtitle: const Text('Buttons, order, columns, icon size and labels'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.busy
            ? null
            : () async {
                final raw = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: edgeActionsRoute),
                    builder: (_) => const EdgeActionsScreen(),
                  ),
                );
                if (raw != null && mounted) {
                  widget.onPreview('edgePanelActions', raw);
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
        onChanged: widget.busy
            ? null
            : (value) {
                if (value != null) widget.onApply('edgePanelSide', value);
              },
      ),
      TextToneControl(
        value: (config['edgePanelTextTone'] as num?)?.toInt() ?? -1,
        busy: widget.busy,
        onChanged: (v, transient) =>
            widget.onLiveChange('edgePanelTextTone', v),
      ),
      NativeLiquidControls(
        raw: (config['edgePanelNativeGlass'] as String?) ?? '{}',
        onChanged: (value) =>
            widget.onLiveChange('edgePanelNativeGlass', value),
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
}
