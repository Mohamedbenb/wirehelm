import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/remote_command.dart';
import '../../ssh/ssh_session.dart';
import '../../utils/command_parameters.dart';
import '../../utils/sudo_command.dart';

//
// Runs and verifies an ordinary Action command.
//
// This contains no screen state. The caller only needs
// to handle:
// - whether testing is in progress
// - displaying the returned message
//
Future<String> testActionCommand({
  required BuildContext context,
  required RemoteCommand command,
  SshSession? session,
}) async {
  if (command.command.trim().isEmpty) {
    return 'Enter a command first.';
  }

  final targetSession = session ?? sshSession;
  if (!targetSession.isConnected) {
    return 'Not connected to the device.';
  }

  final unknown = unknownCommandParameters(command);

  if (unknown.isNotEmpty) {
    return 'Undefined parameter(s): '
        '${unknown.map((key) => '{{param:$key}}').join(', ')}';
  }

  //
  // Resolve runtime parameters before execution.
  //
  final values = await promptCommandParameters(
    context,
    command,
    actionLabel: 'Test',
  );

  if (values == null) {
    return 'Cancelled.';
  }

  if (!context.mounted) {
    return 'Cancelled.';
  }

  final commandText = renderCommandTemplate(command.command, command, values);

  final verificationText = command.verificationCommand == null
      ? null
      : renderCommandTemplate(command.verificationCommand!, command, values);

  try {
    final result = await runCommandWithPrivileges(
      session: targetSession,
      context: context,

      command: command,

      commandText: commandText,
    );

    if (result == null) {
      return 'Cancelled.';
    }

    if (!context.mounted) {
      return 'Cancelled.';
    }

    final output = utf8.decode(result, allowMalformed: true).trim();

    //
    // No verification configured.
    //
    if (verificationText == null || verificationText.trim().isEmpty) {
      if (output.isEmpty) {
        return 'Command sent successfully.\n'
            'No verification configured.';
      }

      return 'Command output:\n'
          '$output';
    }

    //
    // Give commands that change state asynchronously
    // a short moment before checking them.
    //
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) {
      return 'Cancelled.';
    }

    final verificationResult = await runCommandWithPrivileges(
      session: targetSession,
      context: context,

      command: command,

      commandText: verificationText,
    );

    if (verificationResult == null) {
      return 'Cancelled.';
    }

    if (!context.mounted) {
      return 'Cancelled.';
    }

    final verificationOutput = utf8
        .decode(verificationResult, allowMalformed: true)
        .trim();

    final expected = command.expectedOutput?.trim();

    //
    // A verification command without expected output
    // simply reports whatever the verification returned.
    //
    if (expected == null || expected.isEmpty) {
      return 'Verification output:\n'
          '$verificationOutput';
    }

    if (verificationOutput.contains(expected)) {
      return '✓ Verified successfully\n'
          '$verificationOutput';
    }

    return '✗ Verification failed\n'
        'Expected: $expected\n'
        'Received: $verificationOutput';
  } catch (e) {
    return 'Error: $e';
  }
}
