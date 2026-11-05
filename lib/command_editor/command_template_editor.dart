import 'package:flutter/material.dart';

String parameterPlaceholder(
  String key,
) {
  return '{{param:$key}}';
}

void insertParameterPlaceholder({
  required TextEditingController commandController,
  required String key,
  required TextSelection selection,
}) {
  final placeholder =
      parameterPlaceholder(
    key,
  );

  final text =
      commandController.text;

  if (text.contains(
    placeholder,
  )) {
    return;
  }

  int start;
  int end;

  if (selection.isValid &&
      selection.start >= 0 &&
      selection.end >=
          selection.start &&
      selection.end <=
          text.length) {
    start = selection.start;
    end = selection.end;
  } else {
    start = text.length;
    end = text.length;
  }

  var before =
      text.substring(
    0,
    start,
  );

  var after =
      text.substring(
    end,
  );

  if (before.isNotEmpty &&
      !RegExp(
        r'\s$',
      ).hasMatch(
        before,
      )) {
    before += ' ';
  }

  var inserted =
      placeholder;

  if (after.isNotEmpty &&
      !RegExp(
        r'^\s',
      ).hasMatch(
        after,
      )) {
    inserted += ' ';
  }

  final newText =
      '$before'
      '$inserted'
      '$after';

  commandController.value =
      TextEditingValue(
    text: newText,
    selection:
        TextSelection.collapsed(
      offset:
          before.length +
          placeholder.length,
    ),
  );
}

void renameParameterPlaceholder({
  required TextEditingController commandController,
  required TextEditingController verificationController,
  required String oldKey,
  required String newKey,
}) {
  if (oldKey == newKey) {
    return;
  }

  final oldPlaceholder =
      parameterPlaceholder(
    oldKey,
  );

  final newPlaceholder =
      parameterPlaceholder(
    newKey,
  );

  final oldSelection =
      commandController.selection;

  final newCommand =
      commandController.text
          .replaceAll(
    oldPlaceholder,
    newPlaceholder,
  );

  final newVerification =
      verificationController.text
          .replaceAll(
    oldPlaceholder,
    newPlaceholder,
  );

  commandController.value =
      TextEditingValue(
    text: newCommand,
    selection:
        TextSelection.collapsed(
      offset:
          oldSelection.isValid
              ? oldSelection
                  .extentOffset
                  .clamp(
                    0,
                    newCommand.length,
                  )
              : newCommand.length,
    ),
  );

  verificationController.text =
      newVerification;
}

void removeParameterPlaceholder({
  required TextEditingController commandController,
  required TextEditingController verificationController,
  required String key,
}) {
  final placeholder =
      parameterPlaceholder(
    key,
  );

  String clean(
    String value,
  ) {
    var result =
        value.replaceAll(
      placeholder,
      '',
    );

    result = result.replaceAll(
      RegExp(
        r'[ \t]{2,}',
      ),
      ' ',
    );

    result = result.replaceAll(
      RegExp(
        r'[ \t]+\n',
      ),
      '\n',
    );

    return result.trim();
  }

  final newCommand =
      clean(
    commandController.text,
  );

  final newVerification =
      clean(
    verificationController.text,
  );

  commandController.value =
      TextEditingValue(
    text: newCommand,
    selection:
        TextSelection.collapsed(
      offset:
          newCommand.length,
    ),
  );

  verificationController.text =
      newVerification;
}