import 'package:flutter/material.dart';

import '../../models/remote_command.dart';
import '../command_template_editor.dart';
import '../parameter_editor_dialog.dart';

class ActionParameterController {
  final BuildContext context;

  final TextEditingController
      commandController;

  final TextEditingController
      verificationController;

  final List<CommandParameter>
      parameters;

  const ActionParameterController({
    required this.context,
    required this.commandController,
    required this.verificationController,
    required this.parameters,
  });

  Future<ActionParameterEditResult?>
      editParameter({
    CommandParameter? parameter,
    int? index,
  }) async {
    //
    // Capture the command cursor before opening
    // the dialog because the command field loses
    // focus while the dialog is displayed.
    //
    final insertionSelection =
        commandController.selection;

    final oldKey =
        parameter?.key;

    final existingKeys =
        <String>{};

    for (var i = 0;
        i < parameters.length;
        i++) {
      if (index != null &&
          i == index) {
        continue;
      }

      existingKeys.add(
        parameters[i].key,
      );
    }

    final result =
        await showParameterEditorDialog(
      context:
          context,

      parameter:
          parameter,

      existingKeys:
          existingKeys,
    );

    if (result == null) {
      return null;
    }

    //
    // New parameter.
    //
    if (index == null) {
      insertParameterPlaceholder(
        commandController:
            commandController,

        key:
            result.key,

        selection:
            insertionSelection,
      );

      return ActionParameterEditResult(
        parameter:
            result,

        index:
            null,
      );
    }

    //
    // Existing parameter was renamed.
    //
    if (oldKey != null &&
        oldKey != result.key) {
      renameParameterPlaceholder(
        commandController:
            commandController,

        verificationController:
            verificationController,

        oldKey:
            oldKey,

        newKey:
            result.key,
      );
    }

    return ActionParameterEditResult(
      parameter:
          result,

      index:
          index,
    );
  }

  void removeParameter(
    int index,
  ) {
    final parameter =
        parameters[index];

    //
    // Remove the matching placeholder from both
    // templates before the caller removes the model.
    //
    removeParameterPlaceholder(
      commandController:
          commandController,

      verificationController:
          verificationController,

      key:
          parameter.key,
    );
  }
}

class ActionParameterEditResult {
  final CommandParameter parameter;

  //
  // null means this is a new parameter.
  //
  // non-null means replace the existing
  // parameter at this index.
  //
  final int? index;

  const ActionParameterEditResult({
    required this.parameter,
    required this.index,
  });

  bool get isNew =>
      index == null;
}