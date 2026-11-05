import 'package:flutter/material.dart';

import '../models/device.dart';

Future<bool> showDeleteDeviceDialog({
  required BuildContext context,
  required Device device,
}) async {
  final confirmed =
      await showDialog<bool>(
    context: context,

    builder: (
      dialogContext,
    ) {
      return AlertDialog(
        title:
            const Text(
          'Delete Device',
        ),

        content:
            Text(
          'Delete "${device.name}"?',
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                false,
              );
            },

            child:
                const Text(
              'Cancel',
            ),
          ),

          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                true,
              );
            },

            child:
                const Text(
              'Delete',
            ),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}