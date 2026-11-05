import 'package:flutter/material.dart';

class StatefulExecutionSection
    extends StatelessWidget {
  final String executionMode;

  final String shellStyle;

  final bool requiresSudo;

  final ValueChanged<String>
      onExecutionModeChanged;

  final ValueChanged<bool>
      onRequiresSudoChanged;

  const StatefulExecutionSection({
    super.key,
    required this.executionMode,
    required this.shellStyle,
    required this.requiresSudo,
    required this.onExecutionModeChanged,
    required this.onRequiresSudoChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final allowInteractive =
        shellStyle != 'linux';

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,

      children: [
        Text(
          'Execution',
          style:
              Theme.of(
                    context,
                  )
                  .textTheme
                  .titleMedium,
        ),

        const SizedBox(
          height:
              8,
        ),

        DropdownButtonFormField<
            String>(
          initialValue:
              executionMode,

          decoration:
              const InputDecoration(
            labelText:
                'Execution mode',
          ),

          items: [
            const DropdownMenuItem(
              value:
                  'standard',

              child:
                  Text(
                'Standard SSH',
              ),
            ),

            if (allowInteractive)
              const DropdownMenuItem(
                value:
                    'interactive',

                child:
                    Text(
                  'Interactive desktop',
                ),
              ),
          ],

          onChanged:
              (
            value,
          ) {
            if (value != null) {
              onExecutionModeChanged(
                value,
              );
            }
          },
        ),

        if (shellStyle ==
            'linux') ...[
          const SizedBox(
            height:
                8,
          ),

          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,

            title:
                const Text(
              'Run with sudo',
            ),

            subtitle:
                const Text(
              'Applies to switch commands '
              'and the status command.',
            ),

            value:
                requiresSudo,

            onChanged:
                onRequiresSudoChanged,
          ),
        ],
      ],
    );
  }
}