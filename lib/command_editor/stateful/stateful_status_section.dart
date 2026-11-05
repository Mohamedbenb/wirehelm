import 'package:flutter/material.dart';

import '../../utils/stateful_command_templates.dart';
import '../replace_from_clipboard_button.dart';

class StatefulStatusSection
    extends StatefulWidget {
  final TextEditingController
      statusCommandController;

  final bool targetEnabled;

  final String targetKey;

  final String statusExecutionMode;

  final ValueChanged<String>
      onStatusExecutionModeChanged;

  final VoidCallback? onTestStatus;

  final bool isTestingStatus;

  const StatefulStatusSection({
    super.key,
    required this.statusCommandController,
    required this.targetEnabled,
    required this.targetKey,
    required this.statusExecutionMode,
    required this.onStatusExecutionModeChanged,
    this.onTestStatus,
    this.isTestingStatus = false,
  });

  @override
  State<StatefulStatusSection>
      createState() =>
          _StatefulStatusSectionState();
}

class _StatefulStatusSectionState
    extends State<StatefulStatusSection> {
  @override
  void initState() {
    super.initState();

    widget.statusCommandController
        .addListener(
      _onStatusCommandChanged,
    );
  }

  @override
  void didUpdateWidget(
    StatefulStatusSection oldWidget,
  ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (oldWidget
            .statusCommandController !=
        widget.statusCommandController) {
      oldWidget.statusCommandController
          .removeListener(
        _onStatusCommandChanged,
      );

      widget.statusCommandController
          .addListener(
        _onStatusCommandChanged,
      );
    }
  }

  @override
  void dispose() {
    widget.statusCommandController
        .removeListener(
      _onStatusCommandChanged,
    );

    super.dispose();
  }

  void _onStatusCommandChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final normalizedTargetKey =
        widget.targetKey.trim();

    final hasStatusCommand =
        widget.statusCommandController.text
            .trim()
            .isNotEmpty;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Text(
          'Status',
          style:
              Theme.of(
                    context,
                  )
                  .textTheme
                  .titleMedium,
        ),

        const SizedBox(
          height: 4,
        ),

        Text(
          'Optional. If no status command is configured, '
          'the switch actions remain usable but the app '
          'will not claim to know the current state.',
          style:
              Theme.of(
                    context,
                  )
                  .textTheme
                  .bodySmall,
        ),

        const SizedBox(
          height: 12,
        ),

        TextFormField(
          controller:
              widget.statusCommandController,
          minLines: 3,
          maxLines: 8,
          style:
              const TextStyle(
            fontFamily: 'monospace',
          ),
          decoration:
              InputDecoration(
            labelText:
                'Status command (optional)',
            helperText:
                widget.targetEnabled &&
                        normalizedTargetKey
                            .isNotEmpty
                    ? 'Target placeholder: '
                        '${statefulTargetPlaceholder(
                        normalizedTargetKey,
                      )}'
                    : 'The output must match one '
                        'state\'s expected status.',
            alignLabelWithHint:
                true,
            suffixIcon:
                ReplaceFromClipboardButton(
              controller:
                  widget
                      .statusCommandController,
            ),
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        DropdownButtonFormField<String>(
          initialValue:
              widget.statusExecutionMode,
          decoration:
              const InputDecoration(
            labelText:
                'Status execution mode',
            helperText:
                'Choose how the status command '
                'is executed.',
          ),
          items:
              const [
            DropdownMenuItem(
              value: 'standard',
              child: Text(
                'Standard SSH',
              ),
            ),
            DropdownMenuItem(
              value: 'interactive',
              child: Text(
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

            widget
                .onStatusExecutionModeChanged(
              value,
            );
          },
        ),

        const SizedBox(
          height: 12,
        ),

        Align(
          alignment:
              Alignment.centerLeft,
          child:
              FilledButton.tonalIcon(
            onPressed:
                widget.isTestingStatus ||
                        !hasStatusCommand ||
                        widget.onTestStatus ==
                            null
                    ? null
                    : widget.onTestStatus,
            icon:
                widget.isTestingStatus
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
                Text(
              widget.isTestingStatus
                  ? 'Testing...'
                  : 'Test status',
            ),
          ),
        ),
      ],
    );
  }
}