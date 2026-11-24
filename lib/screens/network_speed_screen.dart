import 'package:flutter/material.dart';

import '../customization/customization_health.dart';
import '../customization/network_indicator_preview.dart';
import '../customization/settings_controls.dart';

class NetworkSpeedScreen extends StatelessWidget {
  NetworkSpeedScreen({
    super.key,
    required this.report,
    required this.busy,
    required this.error,
    required this.onEnabledChanged,
    required this.onSettingChanged,
  }) : config = healthSection(report, 'config');

  final Map<String, dynamic> report;
  final Map<String, dynamic> config;
  final bool busy;
  final String? error;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(String key, Object value) onSettingChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: NetworkIndicatorPreview(
          config: config,
          onPositionChanged: busy
              ? null
              : (v) => onSettingChanged('horizontalPosition', v),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [_preferences(context)],
        ),
      ),
    ],
  );

  Widget _slider({
    required String title,
    required String keyName,
    required int min,
    required int max,
    required int fallback,
    String suffix = ' dp',
  }) {
    final value = ((config[keyName] as num?)?.toInt() ?? fallback).clamp(
      min,
      max,
    );
    return CustomizationSlider(
      title: title,
      value: value,
      min: min,
      max: max,
      suffix: suffix,
      onChanged: busy ? null : (v) => onSettingChanged(keyName, v),
      onChangeEnd: busy ? null : (v) => onSettingChanged(keyName, v),
    );
  }

  Widget _networkOptions(
    String title,
    String key,
    Map<String, String> options,
  ) {
    final current = (config[key] ?? options.keys.first).toString();
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
        onChanged: busy
            ? null
            : (value) {
                if (value != null) {
                  onSettingChanged(
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
    value: (config[key] as bool?) ?? fallback,
    onChanged: busy ? null : (value) => onSettingChanged(key, value),
  );

  Widget _preferences(BuildContext context) {
    final enabled = config['enabled'] == true;
    final stacked = config['layout'] != 'inline';
    final requirementsMet = hasSystemUiCapabilities(report);
    final blocked =
        !enabled && (report['canEnable'] != true || !requirementsMet);
    final blocker = (report['blockers'] as List?)
        ?.whereType<String>()
        .firstOrNull;
    return CustomizationCard('Preferences', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show in status bar'),
        subtitle: Text(
          blocked
              ? blocker ?? 'Checking SystemUI and the recovery watchdog…'
              : indicatorStatus(report),
        ),
        value: enabled,
        onChanged: busy || blocked ? null : onEnabledChanged,
      ),
      if (report['hookUpdateRequired'] == true)
        const Text('Restart System UI once to load the new renderer.'),
      if (error != null)
        Text(
          error!,
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
                        onSelected: busy
                            ? null
                            : (_) => onSettingChanged(
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
                onChanged: (value) => onSettingChanged('unitSuffix', value),
              ),
            ),
          _networkOptions('Decimal places', 'decimals', const {
            '0': '0',
            '1': '1',
            '2': '2',
          }),
          if (config['unitLabel'] != 'none') ...[
            _slider(
              title: 'Value / unit gap',
              keyName: 'unitGap',
              min: -4,
              max: 8,
              fallback: 1,
            ),
            const Text(
              'Negative values tighten spacing; a minimum clearance keeps characters readable.',
            ),
            _slider(
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
          _slider(
            title: stacked ? 'Maximum two-line size' : 'Maximum one-line size',
            keyName: stacked ? 'stackedTextSize' : 'textSize',
            min: stacked ? 4 : 8,
            max: stacked ? 12 : 18,
            fallback: stacked ? 8 : 10,
            suffix: ' sp',
          ),
          _slider(
            title: 'Indicator height',
            keyName: 'indicatorHeight',
            min: 13,
            max: 20,
            fallback: 16,
          ),
          _slider(
            title: 'Rate column width',
            keyName: 'rateWidth',
            min: 26,
            max: 64,
            fallback: 38,
          ),
          _slider(
            title: 'Vertical offset',
            keyName: 'verticalOffset',
            min: -3,
            max: 3,
            fallback: 0,
          ),
          _slider(
            title: 'Outer padding',
            keyName: 'iconGap',
            min: 0,
            max: 12,
            fallback: 6,
          ),
          if (config['showUpload'] != false)
            _slider(
              title: 'Download / upload gap',
              keyName: 'directionGap',
              min: 0,
              max: 12,
              fallback: 6,
            ),
          if (config['showArrows'] != false) ...[
            _slider(
              title: 'Arrow size',
              keyName: 'arrowScale',
              min: 60,
              max: 200,
              fallback: 140,
              suffix: '%',
            ),
            _slider(
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
            _slider(
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
}
