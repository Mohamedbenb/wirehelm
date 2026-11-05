import 'package:flutter/material.dart';

/// Geometry only: all optics continue to come from the edge panel configuration.
class SearchOverlaySizeControls extends StatelessWidget {
  const SearchOverlaySizeControls({
    super.key,
    required this.config,
    required this.onChanged,
  });
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  @override
  Widget build(BuildContext context) {
    final search = Map<String, dynamic>.from(
      config['searchTray'] as Map? ?? {},
    );
    final width = (search['width'] as num?)?.toInt() ?? 0;
    final height = (search['height'] as num?)?.toInt() ?? 0;
    final custom = width > 0 || height > 0;
    void change(int w, int h) => onChanged({
      ...config,
      'searchTray': {...search, 'width': w, 'height': h},
    });
    Widget dimension(
      String label,
      String key,
      int value,
      int min,
      int max,
      ValueChanged<int> set,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · $value dp'),
        Slider(
          key: ValueKey(key),
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ 10,
          label: '$value dp',
          onChanged: (v) => set(v.round()),
        ),
      ],
    );
    final w = (width > 0 ? width : 220).clamp(140, 600);
    final h = (height > 0 ? height : 540).clamp(180, 1200);
    return ExpansionTile(
      title: const Text('Search overlay size'),
      subtitle: const Text('Uses the edge panel’s material settings'),
      tilePadding: EdgeInsets.zero,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Custom search dimensions'),
          value: custom,
          onChanged: (v) => change(v ? w : 0, v ? h : 0),
        ),
        if (custom) ...[
          dimension(
            'Search width',
            'search-overlay-width',
            w,
            140,
            600,
            (v) => change(v, h),
          ),
          dimension(
            'Search height',
            'search-overlay-height',
            h,
            180,
            1200,
            (v) => change(w, v),
          ),
        ],
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Dimensions fit the available screen and keyboard space. Turn custom dimensions off to restore automatic sizing. Material and text styling stay linked to the edge panel.',
          ),
        ),
      ],
    );
  }
}
