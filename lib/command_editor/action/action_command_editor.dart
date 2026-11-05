import 'package:flutter/material.dart';

import '../../models/remote_command.dart';
import '../command_editor_sections.dart';

class ActionCommandEditor
    extends StatelessWidget {
  final List<CommandParameter>
      parameters;

  final VoidCallback onAddParameter;

  final void Function(
    CommandParameter parameter,
    int index,
  ) onEditParameter;

  final ValueChanged<int>
      onDeleteParameter;

  final TextEditingController
      verificationController;

  final TextEditingController
      expectedOutputController;

  final bool testing;

  final String? testResult;

  final VoidCallback onTest;

  const ActionCommandEditor({
    super.key,
    required this.parameters,
    required this.onAddParameter,
    required this.onEditParameter,
    required this.onDeleteParameter,
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
      crossAxisAlignment:
          CrossAxisAlignment.stretch,

      children: [
        CommandParametersSection(
          parameters:
              parameters,

          onAdd:
              onAddParameter,

          onEdit:
              onEditParameter,

          onDelete:
              onDeleteParameter,
        ),

        const SizedBox(
          height:
              20,
        ),

        CommandVerificationSection(
          verificationController:
              verificationController,

          expectedOutputController:
              expectedOutputController,

          testing:
              testing,

          testResult:
              testResult,

          onTest:
              onTest,
        ),
      ],
    );
  }
}