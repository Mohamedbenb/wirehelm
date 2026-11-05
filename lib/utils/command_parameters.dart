import 'package:flutter/material.dart';

import '../models/remote_command.dart';

//
// Parameters must use an explicit namespace.
//
// Examples:
//
// {{param:host}}
// {{param:count}}
// {{param:adapter}}
//
// Ordinary brace syntax remains completely literal:
//
// {F15}
// @{ ... }
// ${env:USERNAME}
//
// This avoids accidentally interpreting PowerShell,
// keyboard-key names, script blocks, etc. as parameters.
//
final RegExp _placeholderPattern = RegExp(
  r'\{\{param:([A-Za-z_][A-Za-z0-9_-]*)\}\}',
);

//
// We store a valued flag's runtime
// argument separately from the switch.
//
// Example:
//
// countFlag         -> "true"
// countFlag__value  -> "4"
//
String flagValueKey(String parameterKey) {
  return '${parameterKey}__value';
}

Set<String> commandPlaceholders(String template) {
  return _placeholderPattern
      .allMatches(template)
      .map((match) => match.group(1)!)
      .toSet();
}

Set<String> unknownCommandParameters(RemoteCommand command) {
  final defined = command.parameters.map((parameter) => parameter.key).toSet();

  final used = <String>{
    ...commandPlaceholders(command.command),
    if (command.verificationCommand != null)
      ...commandPlaceholders(command.verificationCommand!),
  };

  return used.difference(defined);
}

String renderCommandTemplate(
  String template,
  RemoteCommand command,
  Map<String, String> values,
) {
  var result = template;

  for (final parameter in command.parameters) {
    final rawValue = values[parameter.key] ?? parameter.defaultValue ?? '';

    String replacement;

    if (parameter.type == 'boolean') {
      final enabled = rawValue.toLowerCase() == 'true';

      if (!enabled) {
        replacement = '';
      } else {
        final flag = parameter.trueValue ?? '';

        if (parameter.takesValue) {
          final argument =
              values[flagValueKey(parameter.key)] ??
              parameter.flagValueDefault ??
              '';

          if (flag.isEmpty) {
            replacement = argument;
          } else if (argument.isEmpty) {
            replacement = flag;
          } else {
            replacement = '$flag $argument';
          }
        } else {
          //
          // Preserve the existing
          // fixed-flag behavior.
          //
          replacement = flag.isEmpty ? 'true' : flag;
        }
      }
    } else {
      replacement = rawValue;
      // wakeonlan accepts colon-separated MACs; Windows displays hyphens.
      // Normalize at execution so existing saved Wake PC commands also work.
      if (parameter.key == 'mac' &&
          RegExp(r'\bwakeonlan\b').hasMatch(template) &&
          RegExp(r'^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$')
              .hasMatch(rawValue.trim())) {
        replacement = rawValue.trim().replaceAll('-', ':');
      }
    }

    result = result.replaceAll('{{param:${parameter.key}}}', replacement);
  }

  //
  // Disabled flags can leave:
  //
  // ping   127.0.0.1
  //
  // Normalize horizontal whitespace only.
  //
  result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

  return result.trim();
}

Future<Map<String, String>?> promptCommandParameters(
  BuildContext context,
  RemoteCommand command, {
  String actionLabel = 'Run',
}) async {
  if (command.parameters.isEmpty) {
    return const {};
  }

  return showDialog<Map<String, String>>(
    context: context,

    builder: (context) {
      return _CommandParameterDialog(
        command: command,

        actionLabel: actionLabel,
      );
    },
  );
}

class _CommandParameterDialog extends StatefulWidget {
  final RemoteCommand command;
  final String actionLabel;

  const _CommandParameterDialog({
    required this.command,
    required this.actionLabel,
  });

  @override
  State<_CommandParameterDialog> createState() =>
      _CommandParameterDialogState();
}

class _CommandParameterDialogState extends State<_CommandParameterDialog> {
  final _formKey = GlobalKey<FormState>();

  final Map<String, String> _values = {};

  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();

    for (final parameter in widget.command.parameters) {
      final initial =
          parameter.defaultValue ??
          (parameter.type == 'boolean' ? 'false' : '');

      _values[parameter.key] = initial;

      if (parameter.type == 'text' || parameter.type == 'integer') {
        _controllers[parameter.key] = TextEditingController(text: initial);
      }

      //
      // A boolean flag can optionally
      // have its own value.
      //
      if (parameter.type == 'boolean' && parameter.takesValue) {
        final valueKey = flagValueKey(parameter.key);

        final valueInitial = parameter.flagValueDefault ?? '';

        _values[valueKey] = valueInitial;

        if (parameter.flagValueType == 'text' ||
            parameter.flagValueType == 'integer') {
          _controllers[valueKey] = TextEditingController(text: valueInitial);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _setValue(String key, String value) {
    setState(() {
      _values[key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = renderCommandTemplate(
      widget.command.command,
      widget.command,
      _values,
    );

    return AlertDialog(
      title: Text(widget.command.name),

      content: SizedBox(
        width: double.maxFinite,

        child: Form(
          key: _formKey,

          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                for (final parameter in widget.command.parameters) ...[
                  _buildParameterField(parameter),

                  const SizedBox(height: 14),
                ],

                const SizedBox(height: 4),

                Text(
                  'Command preview',
                  style: Theme.of(context).textTheme.labelLarge,
                ),

                const SizedBox(height: 8),

                Container(
                  width: double.infinity,

                  padding: const EdgeInsets.all(12),

                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,

                    borderRadius: BorderRadius.circular(12),
                  ),

                  child: SelectableText(
                    preview,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },

          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.pop(context, Map<String, String>.from(_values));
          },

          child: Text(widget.actionLabel),
        ),
      ],
    );
  }

  Widget _buildParameterField(CommandParameter parameter) {
    switch (parameter.type) {
      case 'boolean':
        return _buildBooleanField(parameter);

      case 'choice':
        return _buildChoiceField(parameter);

      case 'integer':
        return _buildIntegerField(parameter);

      default:
        return _buildTextField(parameter);
    }
  }

  Widget _buildTextField(CommandParameter parameter) {
    return TextFormField(
      controller: _controllers[parameter.key],

      decoration: InputDecoration(
        labelText: parameter.label,

        helperText: parameter.description,
      ),

      validator: (value) {
        if (parameter.required && (value == null || value.trim().isEmpty)) {
          return 'Required';
        }

        return null;
      },

      onChanged: (value) {
        _setValue(parameter.key, value);
      },
    );
  }

  Widget _buildIntegerField(CommandParameter parameter) {
    return TextFormField(
      controller: _controllers[parameter.key],

      keyboardType: const TextInputType.numberWithOptions(signed: true),

      decoration: InputDecoration(
        labelText: parameter.label,

        helperText: parameter.description,
      ),

      validator: (value) {
        final text = value?.trim() ?? '';

        if (parameter.required && text.isEmpty) {
          return 'Required';
        }

        if (text.isNotEmpty && int.tryParse(text) == null) {
          return 'Enter an integer';
        }

        return null;
      },

      onChanged: (value) {
        _setValue(parameter.key, value);
      },
    );
  }

  Widget _buildChoiceField(CommandParameter parameter) {
    final current = _values[parameter.key];

    return DropdownButtonFormField<String>(
      initialValue: parameter.options.contains(current) ? current : null,

      decoration: InputDecoration(
        labelText: parameter.label,

        helperText: parameter.description,
      ),

      items: parameter.options
          .map(
            (option) =>
                DropdownMenuItem<String>(value: option, child: Text(option)),
          )
          .toList(),

      validator: (value) {
        if (parameter.required && (value == null || value.isEmpty)) {
          return 'Required';
        }

        return null;
      },

      onChanged: (value) {
        _setValue(parameter.key, value ?? '');
      },
    );
  }

  Widget _buildBooleanField(CommandParameter parameter) {
    final enabled = _values[parameter.key]?.toLowerCase() == 'true';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,

          title: Text(parameter.label),

          subtitle:
              parameter.description == null || parameter.description!.isEmpty
              ? null
              : Text(parameter.description!),

          value: enabled,

          onChanged: (value) {
            _setValue(parameter.key, value.toString());
          },
        ),

        //
        // Only show the argument while
        // the flag is enabled.
        //
        if (enabled && parameter.takesValue) ...[
          const SizedBox(height: 8),

          _buildFlagValueField(parameter),
        ],
      ],
    );
  }

  Widget _buildFlagValueField(CommandParameter parameter) {
    final valueKey = flagValueKey(parameter.key);

    final label = parameter.flagValueLabel ?? 'Value';

    switch (parameter.flagValueType) {
      case 'integer':
        return TextFormField(
          controller: _controllers[valueKey],

          keyboardType: const TextInputType.numberWithOptions(signed: true),

          decoration: InputDecoration(labelText: label),

          validator: (value) {
            final enabled = _values[parameter.key]?.toLowerCase() == 'true';

            if (!enabled) {
              return null;
            }

            final text = value?.trim() ?? '';

            if (text.isEmpty) {
              return 'Required';
            }

            if (int.tryParse(text) == null) {
              return 'Enter an integer';
            }

            return null;
          },

          onChanged: (value) {
            _setValue(valueKey, value);
          },
        );

      case 'choice':
        final current = _values[valueKey];

        return DropdownButtonFormField<String>(
          initialValue: parameter.flagValueOptions.contains(current)
              ? current
              : null,

          decoration: InputDecoration(labelText: label),

          items: parameter.flagValueOptions
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,

                  child: Text(option),
                ),
              )
              .toList(),

          validator: (value) {
            final enabled = _values[parameter.key]?.toLowerCase() == 'true';

            if (!enabled) {
              return null;
            }

            if (value == null || value.isEmpty) {
              return 'Required';
            }

            return null;
          },

          onChanged: (value) {
            _setValue(valueKey, value ?? '');
          },
        );

      default:
        return TextFormField(
          controller: _controllers[valueKey],

          decoration: InputDecoration(labelText: label),

          validator: (value) {
            final enabled = _values[parameter.key]?.toLowerCase() == 'true';

            if (!enabled) {
              return null;
            }

            if (value == null || value.trim().isEmpty) {
              return 'Required';
            }

            return null;
          },

          onChanged: (value) {
            _setValue(valueKey, value);
          },
        );
    }
  }
}
