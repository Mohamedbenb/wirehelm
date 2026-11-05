import 'package:flutter/material.dart';

/// A manual black-to-white shade; -1 leaves the renderer's default intact.
class TextToneControl extends StatelessWidget {
  const TextToneControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });
  final int value;
  final bool busy;
  final void Function(int value, bool transient) onChanged;
  @override
  Widget build(BuildContext context) {
    final tone = value.clamp(0, 100), channel = (tone * 255 / 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Custom text colour'),
          subtitle: const Text(
            'Choose black, white or a shade between them. Off restores the default.',
          ),
          value: value >= 0,
          onChanged: busy ? null : (v) => onChanged(v ? 0 : -1, false),
        ),
        if (value >= 0) ...[
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : () => onChanged(0, false),
                child: const Text('Black'),
              ),
              Expanded(
                child: Slider(
                  semanticFormatterCallback: (v) => '${v.round()}% white',
                  value: tone.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$tone% white',
                  onChanged: busy ? null : (v) => onChanged(v.round(), true),
                  onChangeEnd: busy ? null : (v) => onChanged(v.round(), false),
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => onChanged(100, false),
                child: const Text('White'),
              ),
            ],
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xff454545), Color(0xffeeeeee)],
                ),
              ),
              child: Text(
                'Aa · $tone% white',
                style: TextStyle(
                  fontSize: 20,
                  color: Color.fromARGB(255, channel, channel, channel),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
