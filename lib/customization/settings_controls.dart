import 'package:flutter/material.dart';

class CustomizationCard extends StatelessWidget {
  const CustomizationCard(
    this.title,
    this.children, {
    super.key,
    required this.icon,
  });

  final String title;
  final List<Widget> children;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
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
}

class CustomizationSlider extends StatelessWidget {
  const CustomizationSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final int value, min, max;
  final String suffix;
  final ValueChanged<int>? onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) {
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
          onChanged: onChanged == null ? null : (v) => onChanged!(v.round()),
          onChangeEnd: onChangeEnd == null
              ? null
              : (v) => onChangeEnd!(v.round()),
        ),
      ],
    );
  }
}

class CustomizationDetail extends StatelessWidget {
  const CustomizationDetail(this.label, this.value, {super.key});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Padding(
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
}
