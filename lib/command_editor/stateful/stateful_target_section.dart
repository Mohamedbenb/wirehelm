import 'package:flutter/material.dart';

import '../../utils/stateful_command_templates.dart';

class StatefulTargetSection
    extends StatelessWidget {
  final bool enabled;

  final TextEditingController
      keyController;

  final TextEditingController
      labelController;

  final TextEditingController
      valueController;

  final ValueChanged<bool>
      onEnabledChanged;

  const StatefulTargetSection({
    super.key,
    required this.enabled,
    required this.keyController,
    required this.labelController,
    required this.valueController,
    required this.onEnabledChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final targetKey =
        keyController.text.trim();

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,

      children: [
        SwitchListTile(
          contentPadding:
              EdgeInsets.zero,

          title:
              const Text(
            'Target / object',
          ),

          subtitle:
              const Text(
            'Use this when the same control can point at a specific adapter, service, device, or other object.',
          ),

          value:
              enabled,

          onChanged:
              onEnabledChanged,
        ),

        if (enabled) ...[
          const SizedBox(
            height:
                8,
          ),

          TextFormField(
            controller:
                keyController,

            decoration:
                const InputDecoration(
              labelText:
                  'Target key',

              helperText:
                  'Example: adapter',
            ),

            validator:
                (
              value,
            ) {
              if (!enabled) {
                return null;
              }

              final text =
                  value?.trim() ??
                  '';

              if (text.isEmpty) {
                return 'Enter a target key';
              }

              if (!RegExp(
                r'^[A-Za-z_][A-Za-z0-9_-]*$',
              ).hasMatch(
                text,
              )) {
                return 'Use letters, numbers, _ or -';
              }

              return null;
            },
          ),

          const SizedBox(
            height:
                12,
          ),

          TextFormField(
            controller:
                labelController,

            decoration:
                const InputDecoration(
              labelText:
                  'Target label',

              helperText:
                  'Example: Adapter',
            ),

            validator:
                (
              value,
            ) {
              if (!enabled) {
                return null;
              }

              if (value == null ||
                  value.trim().isEmpty) {
                return 'Enter a target label';
              }

              return null;
            },
          ),

          const SizedBox(
            height:
                12,
          ),

          TextFormField(
            controller:
                valueController,

            decoration:
                const InputDecoration(
              labelText:
                  'Target value',

              helperText:
                  'Example: Ethernet or eth4',
            ),

            validator:
                (
              value,
            ) {
              if (!enabled) {
                return null;
              }

              if (value == null ||
                  value.trim().isEmpty) {
                return 'Enter a target value';
              }

              return null;
            },
          ),

          const SizedBox(
            height:
                8,
          ),

          SelectableText(
            targetKey.isEmpty
                ? 'Set a target key to create its placeholder.'
                : 'Use ${statefulTargetPlaceholder(
                    targetKey,
                  )} inside the status and switch commands.',
            style:
                Theme.of(
                      context,
                    )
                    .textTheme
                    .bodySmall,
          ),
        ],
      ],
    );
  }
}