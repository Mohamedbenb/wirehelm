import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../services/sudo_credentials.dart';
import '../ssh/ssh_session.dart';

Future<Uint8List?> runCommandWithPrivileges({
  required BuildContext context,
  required RemoteCommand command,
  required String commandText,
  SshSession? session,
  bool allowPrompt = true,
  Duration? timeout,
}) async {
  final targetSession =
      session ??
      sshSession;

  //
  // Normal command path.
  //
  if (!command.requiresSudo) {
    return targetSession.runCommand(
      commandText,
      executionMode:
          command.executionMode,
      timeout: timeout,
    );
  }

  //
  // sudo only uses the standard SSH
  // exec path in this app.
  //
  if (command.executionMode !=
      'standard') {
    throw Exception(
      'sudo commands must use '
      'Standard SSH execution.',
    );
  }

  final deviceId =
      targetSession.deviceId;

  if (deviceId == null) {
    throw Exception(
      'No active SSH device.',
    );
  }

  var password =
      sudoCredentials.passwordFor(
    deviceId,
  );

  //
  // Maximum two authentication attempts:
  //
  // 1. cached password, if available,
  //    otherwise prompt immediately
  //
  // 2. fresh prompt if the first
  //    password is rejected
  //
  for (var attempt = 0;
      attempt < 2;
      attempt++) {
    if (password == null) {
      if (!allowPrompt) {
        throw StateError('Status needs sudo credentials. Refresh manually to authenticate.');
      }
      //
      // We may have reached this point after
      // an async sudo attempt failed.
      //
      // The caller's widget could have been
      // disposed while that was happening.
      //
      if (!context.mounted) {
        return null;
      }

      password =
          await showSudoPasswordDialog(
        context,
        commandName:
            command.name,
      );

      if (!context.mounted) {
        return null;
      }

      if (password == null) {
        return null;
      }
    }

    try {
      final operation = targetSession.runSudoCommand(
        commandText,
        password:
            password,
      );
      final result = await (timeout == null ? operation : operation.timeout(timeout));

      //
      // Only remember a password after
      // successful sudo authentication.
      //
      sudoCredentials.remember(
        deviceId:
            deviceId,
        password:
            password,
      );

      return result;
    } on SudoAuthenticationException {
      //
      // The password was wrong.
      //
      // Remove any cached copy and force
      // a fresh prompt on the next loop.
      //
      sudoCredentials.clearDevice(
        deviceId,
      );

      password = null;

      if (attempt == 1) {
        rethrow;
      }
    }
  }

  return null;
}

Future<String?> showSudoPasswordDialog(
  BuildContext context, {
  required String commandName,
}) {
  return showDialog<String>(
    context:
        context,
    builder: (
      context,
    ) {
      return _SudoPasswordDialog(
        commandName:
            commandName,
      );
    },
  );
}

class _SudoPasswordDialog
    extends StatefulWidget {
  final String commandName;

  const _SudoPasswordDialog({
    required this.commandName,
  });

  @override
  State<_SudoPasswordDialog>
      createState() =>
          _SudoPasswordDialogState();
}

class _SudoPasswordDialogState
    extends State<_SudoPasswordDialog> {
  final _controller =
      TextEditingController();

  bool _visible = false;

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  void _submit() {
    final password =
        _controller.text;

    if (password.isEmpty) {
      return;
    }

    Navigator.of(
      context,
    ).pop(
      password,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      title:
          const Text(
        'sudo password',
      ),

      content:
          Column(
        mainAxisSize:
            MainAxisSize.min,

        crossAxisAlignment:
            CrossAxisAlignment
                .stretch,

        children: [
          Text(
            '${widget.commandName} requires '
            'administrator privileges.',
          ),

          const SizedBox(
            height: 16,
          ),

          TextField(
            controller:
                _controller,

            autofocus:
                true,

            obscureText:
                !_visible,

            textInputAction:
                TextInputAction.done,

            onSubmitted:
                (_) {
              _submit();
            },

            decoration:
                InputDecoration(
              labelText:
                  'Password',

              suffixIcon:
                  IconButton(
                tooltip:
                    _visible
                        ? 'Hide password'
                        : 'Show password',

                onPressed:
                    () {
                  setState(() {
                    _visible =
                        !_visible;
                  });
                },

                icon:
                    Icon(
                  _visible
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Text(
            'Stored only in memory until '
            'this SSH connection ends.',
            style:
                Theme.of(
                      context,
                    )
                    .textTheme
                    .bodySmall,
          ),
        ],
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
              _submit,

          child:
              const Text(
            'Continue',
          ),
        ),
      ],
    );
  }
}
