import 'dart:convert';

import 'package:flutter/material.dart';

import 'card_optical_controls.dart';
import 'search_overlay_size_controls.dart';

/// Settings only. SystemUI owns rendering, input and synchronized material layers.
class NativeLiquidControls extends StatelessWidget {
  const NativeLiquidControls({
    super.key,
    required this.raw,
    required this.onChanged,
  });
  final String raw;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> config;
    try {
      config = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      config = {};
    }
    void change(String key, Object value) =>
        onChanged(jsonEncode({...config, key: value}));
    final native = config['backend'] == 'native';
    final card = native && config['engine'] == 'card';
    final preset = (config['preset'] as num?)?.toInt() ?? 3;
    const defaults = [
      [0.0, 0.0, 0.0, 0.0, 0.0],
      [.6, 5.0, .025, .32, .45],
      [6.0, 2.5, .055, .28, .70],
      [2.2, 4.0, .035, .42, .60],
    ];
    final initial = defaults[preset.clamp(0, 3)];
    Widget slider(String key, String title, double value, double max) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title · ${value.toStringAsFixed(2)}'),
        Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: 60,
          onChanged: (v) => change(key, v),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rendering backend',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'native', label: Text('Native Glass')),
              ButtonSegment(value: 'card', label: Text('Card Glass')),
            ],
            emptySelectionAllowed: !native,
            selected: native
                ? {
                    card
                        ? 'card'
                        : native
                        ? 'native'
                        : 'native',
                  }
                : <String>{},
            onSelectionChanged: (v) => onChanged(
              jsonEncode({
                ...config,
                'backend': 'native',
                'engine': v.first == 'card' ? 'card' : 'classic',
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a native edge-panel material. Unsupported material uses the standard panel appearance.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Live Native Glass on collapsed handle'),
          subtitle: const Text(
            'Off uses a lightweight tinted handle so scrolling apps avoid continuous compositor glass. The expanded panel keeps its selected material. Enable only if its GPU cost is acceptable.',
          ),
          value: config['liveHandle'] == true,
          onChanged: (v) => change('liveHandle', v),
        ),
        const Text(
          'Vector yields its overlays to permission, installer and Android Settings screens. Your saved configuration is retained.',
        ),
        if (native) ...[
          if (card)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Performance overlay'),
              subtitle: const Text(
                'Reports edge panel draw cadence and CPU submission time.',
              ),
              value: config['performanceOverlay'] == true,
              onChanged: (v) => change('performanceOverlay', v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expanded panel material'),
            value: config['panel'] != false,
            onChanged: (v) => change('panel', v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Handle material'),
            value: config['handle'] == true,
            subtitle: config['liveHandle'] == true
                ? null
                : const Text(
                    'Enable live handle glass above to use this material.',
                  ),
            onChanged: config['liveHandle'] == true
                ? (v) => change('handle', v)
                : null,
          ),
          if (card) ...[
            CardOpticalControls(
              config: Map<String, dynamic>.from(
                config['cardMaterial'] as Map? ?? {},
              ),
              onChanged: (k, v) => change('cardMaterial', {
                ...Map<String, dynamic>.from(
                  config['cardMaterial'] as Map? ?? {},
                ),
                k: v,
              }),
            ),
            const Text(
              'Uses the shared engine optics with native panel foreground. Text and icons follow the selected foreground styling.',
            ),
          ] else ...[
            DropdownButtonFormField<int>(
              initialValue: preset,
              decoration: const InputDecoration(labelText: 'Material preset'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Pass-through')),
                DropdownMenuItem(value: 1, child: Text('Clear Glass')),
                DropdownMenuItem(value: 2, child: Text('Frosted Glass')),
                DropdownMenuItem(value: 3, child: Text('Hybrid Glass')),
              ],
              onChanged: (v) {
                if (v == null) return;
                const defaults = [
                  [0, 0, 0, 0, 0],
                  [.6, 5, .025, .32, .45],
                  [6, 2.5, .055, .28, .70],
                  [2.2, 4, .035, .42, .60],
                ];
                final d = defaults[v];
                onChanged(
                  jsonEncode({
                    ...config,
                    'preset': v,
                    'blur': d[0],
                    'refraction': d[1],
                    'tint': d[2],
                    'edge': d[3],
                    'contrast': d[4],
                  }),
                );
              },
            ),
            slider(
              'blur',
              'Diffusion strength',
              (config['blur'] as num?)?.toDouble() ?? initial[0],
              12,
            ),
            slider(
              'refraction',
              'Refraction',
              (config['refraction'] as num?)?.toDouble() ?? initial[1],
              12,
            ),
            slider(
              'tint',
              'Tint',
              (config['tint'] as num?)?.toDouble() ?? initial[2],
              .6,
            ),
            slider(
              'edge',
              'Edge highlight',
              (config['edge'] as num?)?.toDouble() ?? initial[3],
              1,
            ),
            slider(
              'contrast',
              'Contrast support',
              (config['contrast'] as num?)?.toDouble() ?? initial[4],
              1,
            ),
            const Text(
              'Contrast support combines gentle local material compression with small native label backings. No background-driven text polarity changes. Native foreground stays stable. Existing text shade and feature Save/Restore controls remain available. System glass has independent controls.',
            ),
          ],
        ],
        SearchOverlaySizeControls(
          config: config,
          onChanged: (v) => onChanged(jsonEncode(v)),
        ),
      ],
    );
  }
}
