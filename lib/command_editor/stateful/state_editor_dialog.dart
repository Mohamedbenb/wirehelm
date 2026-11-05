import 'package:flutter/material.dart';

import '../../models/remote_command.dart';
import '../../utils/stateful_command_templates.dart';
import '../replace_from_clipboard_button.dart';

Future<StatefulCommandState?>
    showStateEditorDialog({
  required BuildContext context,
  StatefulCommandState? state,
  int? index,
  required List<StatefulCommandState> states,
  required bool targetEnabled,
  required String targetKey,
}) async {
  final idController =
      TextEditingController(
    text: state?.id ?? '',
  );

  final labelController =
      TextEditingController(
    text: state?.label ?? '',
  );

  final expectedController =
      TextEditingController(
    text:
        state?.expectedStatus ??
        '',
  );

  final commandController =
      TextEditingController(
    text: state?.command ?? '',
  );

  final formKey =
      GlobalKey<FormState>();

  var executionMode =
      state?.executionMode ??
      'standard';

  StatefulCommandState? result;

  try {
    result =
        await showDialog<
            StatefulCommandState>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title:
                  Text(
                index == null
                    ? 'Add state'
                    : 'Edit state',
              ),
              content:
                  SizedBox(
                width:
                    double.maxFinite,
                child:
                    Form(
                  key: formKey,
                  child:
                      SingleChildScrollView(
                    child:
                        Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller:
                              idController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'State ID',
                            helperText:
                                'Example: enabled, '
                                'disabled, extend',
                          ),
                          validator: (
                            value,
                          ) {
                            final text =
                                value
                                        ?.trim() ??
                                    '';

                            if (text.isEmpty) {
                              return 'Enter a state ID';
                            }

                            if (!RegExp(
                              r'^[A-Za-z_][A-Za-z0-9_-]*$',
                            ).hasMatch(
                              text,
                            )) {
                              return 'Use letters, numbers, '
                                  '_ or -';
                            }

                            for (var i = 0;
                                i <
                                    states.length;
                                i++) {
                              if (index != null &&
                                  i ==
                                      index) {
                                continue;
                              }

                              if (states[i]
                                      .id
                                      .toLowerCase() ==
                                  text
                                      .toLowerCase()) {
                                return 'State ID already exists';
                              }
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                              labelController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Label',
                            helperText:
                                'Text shown on the switch.',
                          ),
                          validator: (
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
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                              expectedController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Expected status',
                            helperText:
                                'Exact status value that '
                                'identifies this state.',
                          ),
                          validator: (
                            value,
                          ) {
                            final text =
                                value
                                        ?.trim() ??
                                    '';

                            if (text.isEmpty) {
                              return 'Enter the expected status';
                            }

                            for (var i = 0;
                                i <
                                    states.length;
                                i++) {
                              if (index != null &&
                                  i ==
                                      index) {
                                continue;
                              }

                              if (states[i]
                                      .expectedStatus
                                      .trim()
                                      .toLowerCase() ==
                                  text
                                      .toLowerCase()) {
                                return 'Expected status already used';
                              }
                            }

                            return null;
                          },
                        ),

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
                                'Switch command',
                            helperText:
                                targetEnabled &&
                                        targetKey
                                            .trim()
                                            .isNotEmpty
                                    ? 'Target placeholder: '
                                        '${statefulTargetPlaceholder(
                                        targetKey.trim(),
                                      )}'
                                    : 'Command executed when '
                                        'this state is selected.',
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
                              return 'Enter a switch command';
                            }

                            return null;
                          },
                        ),

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
                            helperText:
                                'Choose how this state '
                                'command is executed.',
                          ),
                          items:
                              const [
                            DropdownMenuItem(
                              value:
                                  'standard',
                              child:
                                  Text(
                                'Standard SSH',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                                  'interactive',
                              child:
                                  Text(
                                'Interactive desktop',
                              ),
                            ),
                          ],
                          onChanged: (
                            value,
                          ) {
                            if (value == null) {
                              return;
                            }

                            setDialogState(
                              () {
                                executionMode =
                                    value;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      const Text(
                    'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey
                        .currentState!
                        .validate()) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      StatefulCommandState(
                        id:
                            idController
                                .text
                                .trim(),
                        label:
                            labelController
                                .text
                                .trim(),
                        command:
                            commandController
                                .text
                                .trim(),
                        expectedStatus:
                            expectedController
                                .text
                                .trim(),
                        executionMode:
                            executionMode,
                      ),
                    );
                  },
                  child:
                      const Text(
                    'Save',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    //
    // showDialog() can complete before the
    // dialog's TextFormFields have completely
    // left the widget tree.
    //
    // Give Flutter one frame to finish route
    // teardown before disposing controllers.
    //
    await WidgetsBinding.instance.endOfFrame;

    return result;
  } finally {
    idController.dispose();
    labelController.dispose();
    expectedController.dispose();
    commandController.dispose();
  }
}