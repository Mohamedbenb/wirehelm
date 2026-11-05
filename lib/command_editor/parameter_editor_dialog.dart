import 'package:flutter/material.dart';

import '../models/remote_command.dart';

Future<CommandParameter?>
    showParameterEditorDialog({
  required BuildContext context,
  CommandParameter? parameter,
  required Set<String> existingKeys,
}) {
  return showDialog<
      CommandParameter>(
    context:
        context,

    builder: (
      context,
    ) {
      return ParameterEditorDialog(
        parameter:
            parameter,

        existingKeys:
            existingKeys,
      );
    },
  );
}

class ParameterEditorDialog
    extends StatefulWidget {
  final CommandParameter? parameter;

  final Set<String> existingKeys;

  const ParameterEditorDialog({
    super.key,
    this.parameter,
    required this.existingKeys,
  });

  @override
  State<ParameterEditorDialog>
      createState() =>
          _ParameterEditorDialogState();
}

class _ParameterEditorDialogState
    extends State<ParameterEditorDialog> {
  final _formKey =
      GlobalKey<FormState>();

  late final TextEditingController
      _keyController;

  late final TextEditingController
      _labelController;

  late final TextEditingController
      _defaultController;

  late final TextEditingController
      _descriptionController;

  late final TextEditingController
      _optionsController;

  late final TextEditingController
      _trueValueController;

  //
  // Valued flag configuration.
  //
  late final TextEditingController
      _flagValueLabelController;

  late final TextEditingController
      _flagValueDefaultController;

  late final TextEditingController
      _flagValueOptionsController;

  late String _type;

  late bool _required;

  late bool _defaultBoolean;

  late bool _takesValue;

  late String _flagValueType;

  bool get _editing =>
      widget.parameter != null;

  @override
  void initState() {
    super.initState();

    final parameter =
        widget.parameter;

    _keyController =
        TextEditingController(
      text:
          parameter?.key ?? '',
    );

    _labelController =
        TextEditingController(
      text:
          parameter?.label ?? '',
    );

    _defaultController =
        TextEditingController(
      text:
          parameter?.defaultValue ??
          '',
    );

    _descriptionController =
        TextEditingController(
      text:
          parameter?.description ??
          '',
    );

    _optionsController =
        TextEditingController(
      text:
          parameter?.options
              .join('\n') ??
          '',
    );

    _trueValueController =
        TextEditingController(
      text:
          parameter?.trueValue ??
          '',
    );

    _flagValueLabelController =
        TextEditingController(
      text:
          parameter?.flagValueLabel ??
          '',
    );

    _flagValueDefaultController =
        TextEditingController(
      text:
          parameter
                  ?.flagValueDefault ??
              '',
    );

    _flagValueOptionsController =
        TextEditingController(
      text:
          parameter
                  ?.flagValueOptions
                  .join('\n') ??
              '',
    );

    _type =
        parameter?.type ??
        'text';

    _required =
        parameter?.required ??
        false;

    _defaultBoolean =
        parameter
                ?.defaultValue
                ?.toLowerCase() ==
            'true';

    _takesValue =
        parameter?.takesValue ??
        false;

    _flagValueType =
        parameter
                ?.flagValueType ??
            'text';
  }

  @override
  void dispose() {
    _keyController.dispose();
    _labelController.dispose();
    _defaultController.dispose();
    _descriptionController.dispose();
    _optionsController.dispose();
    _trueValueController.dispose();

    _flagValueLabelController
        .dispose();

    _flagValueDefaultController
        .dispose();

    _flagValueOptionsController
        .dispose();

    super.dispose();
  }

  List<String> _choices() {
    return _optionsController.text
        .split('\n')
        .map(
          (value) =>
              value.trim(),
        )
        .where(
          (value) =>
              value.isNotEmpty,
        )
        .toList();
  }

  List<String> _flagChoices() {
    return _flagValueOptionsController
        .text
        .split('\n')
        .map(
          (value) =>
              value.trim(),
        )
        .where(
          (value) =>
              value.isNotEmpty,
        )
        .toList();
  }

  void _save() {
    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final defaultValue =
        _type == 'boolean'
            ? _defaultBoolean
                .toString()
            : _defaultController
                    .text
                    .trim()
                    .isEmpty
                ? null
                : _defaultController
                    .text
                    .trim();

    final parameter =
        CommandParameter(
      key:
          _keyController.text
              .trim(),

      label:
          _labelController.text
              .trim(),

      type:
          _type,

      required:
          _type == 'boolean'
              ? false
              : _required,

      defaultValue:
          defaultValue,

      options:
          _type == 'choice'
              ? _choices()
              : const [],

      trueValue:
          _type == 'boolean' &&
                  _trueValueController
                      .text
                      .trim()
                      .isNotEmpty
              ? _trueValueController
                  .text
                  .trim()
              : null,

      takesValue:
          _type == 'boolean'
              ? _takesValue
              : false,

      flagValueType:
          _type == 'boolean'
              ? _flagValueType
              : 'text',

      flagValueLabel:
          _type == 'boolean' &&
                  _takesValue &&
                  _flagValueLabelController
                      .text
                      .trim()
                      .isNotEmpty
              ? _flagValueLabelController
                  .text
                  .trim()
              : null,

      flagValueDefault:
          _type == 'boolean' &&
                  _takesValue &&
                  _flagValueDefaultController
                      .text
                      .trim()
                      .isNotEmpty
              ? _flagValueDefaultController
                  .text
                  .trim()
              : null,

      flagValueOptions:
          _type == 'boolean' &&
                  _takesValue &&
                  _flagValueType ==
                      'choice'
              ? _flagChoices()
              : const [],

      description:
          _descriptionController
                  .text
                  .trim()
                  .isEmpty
              ? null
              : _descriptionController
                  .text
                  .trim(),
    );

    Navigator.of(
      context,
    ).pop(
      parameter,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      title:
          Text(
        _editing
            ? 'Edit parameter'
            : 'Add parameter',
      ),

      content:
          SizedBox(
        width:
            double.maxFinite,

        child:
            Form(
          key:
              _formKey,

          child:
              SingleChildScrollView(
            child:
                Column(
              mainAxisSize:
                  MainAxisSize.min,

              children: [
                TextFormField(
                  controller:
                      _keyController,

                  decoration:
                      const InputDecoration(
                    labelText:
                        'Key',

                    hintText:
                        'host',

                    helperText:
                        'Used as {host} in the command.',
                  ),

                  validator:
                      (
                    value,
                  ) {
                    final key =
                        value?.trim() ??
                        '';

                    if (key.isEmpty) {
                      return 'Enter a key';
                    }

                    if (!RegExp(
                      r'^[A-Za-z_][A-Za-z0-9_]*$',
                    ).hasMatch(
                      key,
                    )) {
                      return 'Use letters, numbers and _ only.';
                    }

                    if (widget
                        .existingKeys
                        .contains(
                      key,
                    )) {
                      return 'That key already exists.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 14,
                ),

                TextFormField(
                  controller:
                      _labelController,

                  decoration:
                      const InputDecoration(
                    labelText:
                        'Label',
                    hintText:
                        'Host',
                  ),

                  validator:
                      (
                    value,
                  ) {
                    if (value == null ||
                        value
                            .trim()
                            .isEmpty) {
                      return 'Enter a label';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 14,
                ),

                DropdownButtonFormField<
                    String>(
                  initialValue:
                      _type,

                  decoration:
                      const InputDecoration(
                    labelText:
                        'Type',
                  ),

                  items:
                      const [
                    DropdownMenuItem(
                      value:
                          'text',
                      child:
                          Text(
                        'Text',
                      ),
                    ),

                    DropdownMenuItem(
                      value:
                          'integer',
                      child:
                          Text(
                        'Integer',
                      ),
                    ),

                    DropdownMenuItem(
                      value:
                          'choice',
                      child:
                          Text(
                        'Choice',
                      ),
                    ),

                    DropdownMenuItem(
                      value:
                          'boolean',
                      child:
                          Text(
                        'Boolean / flag',
                      ),
                    ),
                  ],

                  onChanged:
                      (
                    value,
                  ) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _type =
                          value;

                      if (_type ==
                          'boolean') {
                        _required =
                            false;
                      }
                    });
                  },
                ),

                const SizedBox(
                  height: 14,
                ),

                if (_type !=
                    'boolean')
                  SwitchListTile(
                    contentPadding:
                        EdgeInsets.zero,

                    title:
                        const Text(
                      'Required',
                    ),

                    value:
                        _required,

                    onChanged:
                        (
                      value,
                    ) {
                      setState(() {
                        _required =
                            value;
                      });
                    },
                  ),

                //
                // Boolean / flag editor.
                //
                if (_type ==
                    'boolean') ...[
                  SwitchListTile(
                    contentPadding:
                        EdgeInsets.zero,

                    title:
                        const Text(
                      'Enabled by default',
                    ),

                    value:
                        _defaultBoolean,

                    onChanged:
                        (
                      value,
                    ) {
                      setState(() {
                        _defaultBoolean =
                            value;
                      });
                    },
                  ),

                  TextFormField(
                    controller:
                        _trueValueController,

                    decoration:
                        const InputDecoration(
                      labelText:
                          'Flag',

                      hintText:
                          '--verbose',

                      helperText:
                          'Inserted when the switch is enabled.',
                    ),

                    validator:
                        (
                      value,
                    ) {
                      if (_type !=
                          'boolean') {
                        return null;
                      }

                      if (value == null ||
                          value
                              .trim()
                              .isEmpty) {
                        return 'Enter the flag.';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  SwitchListTile(
                    contentPadding:
                        EdgeInsets.zero,

                    title:
                        const Text(
                      'Flag takes a value',
                    ),

                    subtitle:
                        const Text(
                      'Examples: -c 4, --port 22',
                    ),

                    value:
                        _takesValue,

                    onChanged:
                        (
                      value,
                    ) {
                      setState(() {
                        _takesValue =
                            value;
                      });
                    },
                  ),

                  if (_takesValue) ...[
                    const SizedBox(
                      height: 8,
                    ),

                    TextFormField(
                      controller:
                          _flagValueLabelController,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Value label',

                        hintText:
                            'Count',
                      ),

                      validator:
                          (
                        value,
                      ) {
                        if (_type !=
                                'boolean' ||
                            !_takesValue) {
                          return null;
                        }

                        if (value == null ||
                            value
                                .trim()
                                .isEmpty) {
                          return 'Enter a value label.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    DropdownButtonFormField<
                        String>(
                      initialValue:
                          _flagValueType,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Value type',
                      ),

                      items:
                          const [
                        DropdownMenuItem(
                          value:
                              'text',
                          child:
                              Text(
                            'Text',
                          ),
                        ),

                        DropdownMenuItem(
                          value:
                              'integer',
                          child:
                              Text(
                            'Integer',
                          ),
                        ),

                        DropdownMenuItem(
                          value:
                              'choice',
                          child:
                              Text(
                            'Choice',
                          ),
                        ),
                      ],

                      onChanged:
                          (
                        value,
                      ) {
                        if (value ==
                            null) {
                          return;
                        }

                        setState(() {
                          _flagValueType =
                              value;
                        });
                      },
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    TextFormField(
                      controller:
                          _flagValueDefaultController,

                      keyboardType:
                          _flagValueType ==
                                  'integer'
                              ? const TextInputType
                                  .numberWithOptions(
                                  signed:
                                      true,
                                )
                              : null,

                      decoration:
                          const InputDecoration(
                        labelText:
                            'Default value',
                      ),

                      validator:
                          (
                        value,
                      ) {
                        if (_type !=
                                'boolean' ||
                            !_takesValue) {
                          return null;
                        }

                        final text =
                            value?.trim() ??
                            '';

                        if (text.isEmpty) {
                          return 'Enter a default value.';
                        }

                        if (_flagValueType ==
                                'integer' &&
                            int.tryParse(
                                  text,
                                ) ==
                                null) {
                          return 'Enter an integer.';
                        }

                        return null;
                      },
                    ),

                    if (_flagValueType ==
                        'choice') ...[
                      const SizedBox(
                        height: 14,
                      ),

                      TextFormField(
                        controller:
                            _flagValueOptionsController,

                        minLines:
                            3,

                        maxLines:
                            7,

                        decoration:
                            const InputDecoration(
                          labelText:
                              'Choices',

                          helperText:
                              'One choice per line.',

                          alignLabelWithHint:
                              true,
                        ),

                        validator:
                            (
                          value,
                        ) {
                          if (_type !=
                                  'boolean' ||
                              !_takesValue ||
                              _flagValueType !=
                                  'choice') {
                            return null;
                          }

                          if (_flagChoices()
                              .isEmpty) {
                            return 'Add at least one choice.';
                          }

                          return null;
                        },
                      ),
                    ],
                  ],
                ] else ...[
                  //
                  // Normal text / integer /
                  // choice parameter.
                  //
                  TextFormField(
                    controller:
                        _defaultController,

                    keyboardType:
                        _type ==
                                'integer'
                            ? const TextInputType
                                .numberWithOptions(
                                signed:
                                    true,
                              )
                            : null,

                    decoration:
                        const InputDecoration(
                      labelText:
                          'Default value',
                    ),

                    validator:
                        (
                      value,
                    ) {
                      if (_type !=
                          'integer') {
                        return null;
                      }

                      final text =
                          value?.trim() ??
                          '';

                      if (text.isNotEmpty &&
                          int.tryParse(
                                text,
                              ) ==
                              null) {
                        return 'Enter an integer';
                      }

                      return null;
                    },
                  ),
                ],

                if (_type ==
                    'choice') ...[
                  const SizedBox(
                    height: 14,
                  ),

                  TextFormField(
                    controller:
                        _optionsController,

                    minLines:
                        3,
                    maxLines:
                        7,

                    decoration:
                        const InputDecoration(
                      labelText:
                          'Choices',

                      helperText:
                          'One choice per line.',

                      alignLabelWithHint:
                          true,
                    ),

                    validator:
                        (
                      value,
                    ) {
                      if (_type !=
                          'choice') {
                        return null;
                      }

                      if (_choices()
                          .isEmpty) {
                        return 'Add at least one choice.';
                      }

                      return null;
                    },
                  ),
                ],

                const SizedBox(
                  height: 14,
                ),

                TextFormField(
                  controller:
                      _descriptionController,

                  minLines:
                      2,
                  maxLines:
                      4,

                  decoration:
                      const InputDecoration(
                    labelText:
                        'Description',

                    hintText:
                        'Optional help text',

                    alignLabelWithHint:
                        true,
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
            Navigator.of(
              context,
            ).pop();
          },

          child:
              const Text(
            'Cancel',
          ),
        ),

        FilledButton(
          onPressed:
              _save,

          child:
              Text(
            _editing
                ? 'Save'
                : 'Add',
          ),
        ),
      ],
    );
  }
}