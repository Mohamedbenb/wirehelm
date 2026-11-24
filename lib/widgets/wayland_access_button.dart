import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/wayland_access.dart';
import '../ssh/ssh_session.dart';

class WaylandAccessButton extends StatelessWidget {
  const WaylandAccessButton({
    super.key,
    required this.device,
    required this.session,
    required this.mode,
    required this.enabled,
    this.onChanged,
  });

  final Device device;
  final SshSession session;
  final WaylandAccessMode mode;
  final bool enabled;
  final Future<void> Function()? onChanged;

  Future<void> _edit(BuildContext context) async {
    try {
      final access = await WaylandAccess.read(device, session, mode);
      if (!context.mounted) return;
      if (!access.available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connect to the PC through SSH first.')),
        );
        return;
      }
      final remember = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remember ${mode.label} access'),
          content: Text(
            access.remember
                ? access.token != null
                      ? 'KDE approval is saved for this phone. Turning this off '
                            'forgets it, so KDE asks again next time.'
                      : 'Waiting for saved approval. Start a session and select '
                            'the option to skip future prompts in KDE’s dialog on the PC.'
                : 'On the PC, check “Allow the application to do this without asking next time” when KDE prompts you. '
                      'Future sessions from this phone can reuse that approval.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, !access.remember),
              child: Text(access.remember ? 'Turn off and forget' : 'Turn on'),
            ),
          ],
        ),
      );
      if (remember == null || !context.mounted) return;
      await access.setRemember(remember);
      await onChanged?.call();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change saved KDE approval.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Remember ${mode.label} access',
      onPressed: enabled ? () => _edit(context) : null,
      icon: const Icon(Icons.verified_user_outlined),
    );
  }
}
