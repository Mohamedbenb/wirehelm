import 'package:flutter/material.dart';

import 'glass_tint_color_picker.dart';

/// Shared settings contract for the card-derived compositor optics.
class CardOpticalControls extends StatelessWidget {
  const CardOpticalControls({
    super.key,
    required this.config,
    this.notificationMaterial = false,
    required this.onChanged,
  });
  final Map<String, dynamic> config;
  final bool notificationMaterial;
  final void Function(String, dynamic) onChanged;
  @override
  Widget build(BuildContext context) {
    double n(String k, double d) => (config[k] as num?)?.toDouble() ?? d;
    Widget slider(String k, String label, double lo, double hi, double d) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label · ${n(k, d).toStringAsFixed(2)}'),
            Slider(
              key: ValueKey('optical-$k'),
              value: n(k, d).clamp(lo, hi),
              min: lo,
              max: hi,
              divisions: 100,
              onChanged: (v) => onChanged(k, v),
            ),
          ],
        );
    Widget toggle(String k, String label, {bool initial = false}) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: config[k] as bool? ?? initial,
          onChanged: (v) => onChanged(k, v),
        );
    final tint = config['glassTintColor'] as String? ?? '#FFFFFF';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: config['material'] as String? ?? 'clear',
          decoration: const InputDecoration(labelText: 'Card material'),
          items: const [
            DropdownMenuItem(value: 'clear', child: Text('Clear')),
            DropdownMenuItem(value: 'regular', child: Text('Regular')),
          ],
          onChanged: (v) {
            if (v != null) onChanged('material', v);
          },
        ),
        slider('blurStrength', 'Blur', 0, 100, 12),
        slider('dimming', 'Dimming', 0, 100, 0),
        if (config['material'] != 'regular')
          slider('baseVeil', 'White veil', 0, 100, 0),
        if (config['material'] == 'regular')
          slider(
            'regularToneStrength',
            'Neutral contrast compression (Regular)',
            0,
            100,
            0,
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tint color'),
          subtitle: Text(tint),
          trailing: IconButton(
            key: const ValueKey('optical-tint-picker'),
            icon: const Icon(Icons.palette_outlined),
            onPressed: () async {
              final color = await showGlassTintPicker(context, tint);
              if (color != null) onChanged('glassTintColor', color);
            },
          ),
        ),
        slider('glassTintStrength', 'Tint strength', 0, 1, 0),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Optics and lighting'),
          children: [
            slider('bevel', 'Bevel thickness', 4, 160, 48),
            slider('refraction', 'Refraction', 0, 240, 160),
            slider('dispersion', 'Chromatic dispersion', 0, .9, .1),
            slider('specular', 'Edge highlights', 0, 2, 1),
            slider('saturation', 'Saturation', 0, 200, 140),
            slider('softness', 'Rim softness', 0, 24, 0),
            slider('falloff', 'Refraction falloff', 0, 6, 2),
            toggle('outward', 'Outward refraction'),
            toggle('sensorLighting', 'Sensor lighting', initial: true),
            if (!notificationMaterial)
              toggle('pressEffects', 'Touch and press effects', initial: true),
          ],
        ),
        toggle('reactionEnabled', 'Restrained reaction'),
        if (config['reactionEnabled'] == true)
          slider('reactionIntensity', 'Reaction intensity', 0, 1, .25),
        if (!notificationMaterial) toggle('touchRipples', 'Touch ripples'),
        if (!notificationMaterial && config['touchRipples'] == true) ...[
          slider('rippleStrength', 'Ripple strength', 0, 1, .5),
          slider('rippleSpeed', 'Ripple speed', .25, 2.5, 1),
          slider('rippleDamping', 'Ripple damping', .3, 3, 1.4),
          const Text(
            'Press and release send waves outward. The rounded border absorbs them.',
          ),
        ],
      ],
    );
  }
}
