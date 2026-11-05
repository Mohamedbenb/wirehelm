import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../utils/command_icons.dart';
import 'replace_from_clipboard_button.dart';

class CommandBasicFields
    extends StatelessWidget {
  final TextEditingController
      nameController;

  final TextEditingController
      categoryController;

  final TextEditingController
      commandController;

  final String selectedIcon;

  final String executionMode;

  final String shellStyle;

  final bool requiresSudo;

  //
  // Normal action commands show:
  //
  // - execution mode
  // - sudo
  // - shell command
  //
  // Stateful commands still use the common:
  //
  // - name
  // - category
  // - icon
  //
  // but their executable commands live inside
  // their individual states instead.
  //
  final bool showCommandFields;

  final ValueChanged<String>
      onIconChanged;

  final ValueChanged<String>
      onExecutionModeChanged;

  final ValueChanged<bool>
      onRequiresSudoChanged;

  const CommandBasicFields({
    super.key,
    required this.nameController,
    required this.categoryController,
    required this.commandController,
    required this.selectedIcon,
    required this.executionMode,
    required this.shellStyle,
    required this.requiresSudo,
    this.showCommandFields = true,
    required this.onIconChanged,
    required this.onExecutionModeChanged,
    required this.onRequiresSudoChanged,
  });

  String _commandHint() {
    switch (shellStyle) {
      case 'windows':
        return 'Example: ping {{param:host}}';

      case 'linux':
        return 'Example: ping -c {{param:count}} '
            '{{param:host}}';

      default:
        return 'Example: command {{param:value}}';
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final allowInteractive =
        shellStyle != 'linux';

    return Column(
      children: [
        TextFormField(
          controller: nameController,
          decoration:
              const InputDecoration(
            labelText: 'Name',
          ),
          validator: (
            value,
          ) {
            if (value == null ||
                value.trim().isEmpty) {
              return 'Enter a name';
            }

            return null;
          },
        ),

        const SizedBox(
          height: 16,
        ),

        TextFormField(
          controller: categoryController,
          decoration:
              const InputDecoration(
            labelText: 'Category',
          ),
          validator: (
            value,
          ) {
            if (value == null ||
                value.trim().isEmpty) {
              return 'Enter a category';
            }

            return null;
          },
        ),

        const SizedBox(
          height: 16,
        ),

        DropdownButtonFormField<String>(
          initialValue:
              selectedIcon,
          decoration:
              const InputDecoration(
            labelText: 'Icon',
          ),
          items:
              commandIcons.entries
                  .map(
                    (
                      entry,
                    ) =>
                        DropdownMenuItem<
                            String>(
                      value:
                          entry.key,
                      child:
                          Row(
                        children: [
                          Icon(
                            entry.value,
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Text(
                            entry.key,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (
            value,
          ) {
            if (value != null) {
              onIconChanged(
                value,
              );
            }
          },
        ),

        if (showCommandFields) ...[
          const SizedBox(
            height: 16,
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
                value: 'standard',
                child: Text(
                  'Standard SSH',
                ),
              ),
              if (allowInteractive)
                const DropdownMenuItem(
                  value:
                      'interactive',
                  child: Text(
                    'Interactive desktop',
                  ),
                ),
            ],
            onChanged: (
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
              height: 8,
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
                'Prompt for the sudo password '
                'when this command runs.',
              ),
              value:
                  requiresSudo,
              onChanged:
                  onRequiresSudoChanged,
            ),
          ],

          const SizedBox(
            height: 16,
          ),

          TextFormField(
            controller:
                commandController,
            minLines: 4,
            maxLines: 10,
            style:
                const TextStyle(
              fontFamily:
                  'monospace',
            ),
            decoration:
                InputDecoration(
              labelText:
                  'Shell command',
              hintText:
                  _commandHint(),
              helperText:
                  'Use {{param:name}} placeholders.',
              alignLabelWithHint:
                  true,
              suffixIcon:
                  ReplaceFromClipboardButton(
                controller:
                    commandController,
              ),
            ),
            validator: (
              value,
            ) {
              if (value == null ||
                  value
                      .trim()
                      .isEmpty) {
                return 'Enter a command';
              }

              return null;
            },
          ),
        ],
      ],
    );
  }
}

class CommandParametersSection
    extends StatelessWidget {
  final List<CommandParameter>
      parameters;

  final VoidCallback onAdd;

  final void Function(
    CommandParameter parameter,
    int index,
  ) onEdit;

  final ValueChanged<int>
      onDelete;

  const CommandParametersSection({
    super.key,
    required this.parameters,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  IconData _iconFor(
    CommandParameter parameter,
  ) {
    switch (parameter.type) {
      case 'boolean':
        return Icons.toggle_on;

      case 'choice':
        return Icons.list;

      case 'integer':
        return Icons.numbers;

      default:
        return Icons.text_fields;
    }
  }

  String _subtitle(
    CommandParameter parameter,
  ) {
    final parts =
        <String>[
      '{{param:${parameter.key}}}',
      parameter.type,
    ];

    if (parameter.defaultValue !=
        null) {
      parts.add(
        'default: ${parameter.defaultValue}',
      );
    }

    if (parameter.type ==
            'boolean' &&
        parameter.trueValue !=
            null) {
      parts.add(
        parameter.trueValue!,
      );
    }

    if (parameter.type ==
            'boolean' &&
        parameter.takesValue) {
      final valueInfo =
          parameter.flagValueLabel ??
          'value';

      parts.add(
        '$valueInfo (${parameter.flagValueType})',
      );
    }

    return parts.join(
      ' • ',
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      children: [
        Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    'Parameters',
                    style:
                        Theme.of(
                              context,
                            )
                            .textTheme
                            .titleMedium,
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    'Place the cursor in the command '
                    'where the parameter should be inserted.',
                    style:
                        Theme.of(
                              context,
                            )
                            .textTheme
                            .bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(
              width: 12,
            ),

            FilledButton.tonalIcon(
              onPressed:
                  onAdd,
              icon:
                  const Icon(
                Icons.add,
              ),
              label:
                  const Text(
                'Add',
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 8,
        ),

        if (parameters.isEmpty)
          const Card(
            child:
                Padding(
              padding:
                  EdgeInsets.all(
                16,
              ),
              child:
                  Text(
                'No parameters. The command will run '
                'immediately when tapped.',
              ),
            ),
          )
        else
          for (var i = 0;
              i < parameters.length;
              i++)
            Card(
              margin:
                  const EdgeInsets.only(
                bottom: 8,
              ),
              child:
                  ListTile(
                leading:
                    Icon(
                  _iconFor(
                    parameters[i],
                  ),
                ),
                title:
                    Text(
                  parameters[i].label,
                ),
                subtitle:
                    Text(
                  _subtitle(
                    parameters[i],
                  ),
                ),
                onTap: () {
                  onEdit(
                    parameters[i],
                    i,
                  );
                },
                trailing:
                    IconButton(
                  tooltip:
                      'Delete parameter',
                  icon:
                      const Icon(
                    Icons.delete_outline,
                  ),
                  onPressed:
                      () {
                    onDelete(
                      i,
                    );
                  },
                ),
              ),
            ),
      ],
    );
  }
}

class CommandVerificationSection
    extends StatelessWidget {
  final TextEditingController
      verificationController;

  final TextEditingController
      expectedOutputController;

  final bool testing;

  final String? testResult;

  final VoidCallback onTest;

  const CommandVerificationSection({
    super.key,
    required this.verificationController,
    required this.expectedOutputController,
    required this.testing,
    required this.testResult,
    required this.onTest,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      children: [
        TextFormField(
          controller:
              verificationController,
          minLines: 3,
          maxLines: 7,
          style:
              const TextStyle(
            fontFamily:
                'monospace',
          ),
          decoration:
              InputDecoration(
            labelText:
                'Verification command (optional)',
            helperText:
                'The same {{param:name}} parameters '
                'can be used here.',
            alignLabelWithHint:
                true,
            suffixIcon:
                ReplaceFromClipboardButton(
              controller:
                  verificationController,
            ),
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        TextFormField(
          controller:
              expectedOutputController,
          style:
              const TextStyle(
            fontFamily:
                'monospace',
          ),
          decoration:
              const InputDecoration(
            labelText:
                'Expected output (optional)',
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        OutlinedButton.icon(
          onPressed:
              testing
                  ? null
                  : onTest,
          icon:
              testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.play_arrow,
                    ),
          label:
              const Text(
            'Test Command',
          ),
        ),

        if (testResult != null) ...[
          const SizedBox(
            height: 12,
          ),

          Card(
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                12,
              ),
              child:
                  SelectableText(
                testResult!,
                style:
                    const TextStyle(
                  fontFamily:
                      'monospace',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}