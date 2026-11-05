import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/known_host_storage.dart';

class HostKeyDialogs {
  final KnownHostStorage _knownHostStorage;

  HostKeyDialogs({
    KnownHostStorage? knownHostStorage,
  }) : _knownHostStorage =
            knownHostStorage ??
            KnownHostStorage();

  Future<bool> verifyHostKey({
    required BuildContext context,
    required Device device,
    required String keyType,
    required Uint8List fingerprintBytes,
  }) async {
    final fingerprint =
        String.fromCharCodes(
      fingerprintBytes,
    );

    final known =
        await _knownHostStorage
            .getKnownHost(
      host:
          device.host,
      port:
          device.port,
    );

    //
    // Already trusted and unchanged.
    //
    if (known != null &&
        known.keyType ==
            keyType &&
        known.fingerprint ==
            fingerprint) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    //
    // First connection.
    //
    if (known == null) {
      final trusted =
          await _showNewHostDialog(
        context:
            context,
        device:
            device,
        keyType:
            keyType,
        fingerprint:
            fingerprint,
      );

      if (trusted != true) {
        return false;
      }

      await _knownHostStorage
          .trustHost(
        host:
            device.host,
        port:
            device.port,
        keyType:
            keyType,
        fingerprint:
            fingerprint,
      );

      return true;
    }

    //
    // Host exists, but the key changed.
    //
    final trustedReplacement =
        await _showChangedHostDialog(
      context:
          context,
      device:
          device,
      oldKeyType:
          known.keyType,
      oldFingerprint:
          known.fingerprint,
      newKeyType:
          keyType,
      newFingerprint:
          fingerprint,
    );

    if (trustedReplacement !=
        true) {
      return false;
    }

    await _knownHostStorage
        .trustHost(
      host:
          device.host,
      port:
          device.port,
      keyType:
          keyType,
      fingerprint:
          fingerprint,
    );

    return true;
  }

  Future<bool?>
      _showNewHostDialog({
    required BuildContext context,
    required Device device,
    required String keyType,
    required String fingerprint,
  }) {
    return showDialog<bool>(
      context:
          context,

      barrierDismissible:
          false,

      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          icon:
              const Icon(
            Icons.security,
          ),

          title:
              const Text(
            'New SSH Host',
          ),

          content:
              SingleChildScrollView(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              mainAxisSize:
                  MainAxisSize.min,

              children: [
                Text(
                  'This is the first time '
                  'this app has connected to '
                  '${device.host}:${device.port}.',
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'Host key type',

                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                SelectableText(
                  keyType,

                  style:
                      const TextStyle(
                    fontFamily:
                        'monospace',
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'SHA256 fingerprint',

                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                SelectableText(
                  fingerprint,

                  style:
                      const TextStyle(
                    fontFamily:
                        'monospace',
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'Trust this host only if '
                  'you recognize the server.',
                ),
              ],
            ),
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

            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },

              icon:
                  const Icon(
                Icons.verified_user,
              ),

              label:
                  const Text(
                'Trust Host',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?>
      _showChangedHostDialog({
    required BuildContext context,
    required Device device,
    required String oldKeyType,
    required String oldFingerprint,
    required String newKeyType,
    required String newFingerprint,
  }) {
    return showDialog<bool>(
      context:
          context,

      barrierDismissible:
          false,

      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          icon:
              const Icon(
            Icons.warning_amber_rounded,
          ),

          title:
              const Text(
            'SSH Host Key Changed',
          ),

          content:
              SingleChildScrollView(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              mainAxisSize:
                  MainAxisSize.min,

              children: [
                Text(
                  'The SSH host key for '
                  '${device.host}:${device.port} '
                  'is different from the key '
                  'you previously trusted.',
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'Previously trusted',

                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                SelectableText(
                  '$oldKeyType\n'
                  '$oldFingerprint',

                  style:
                      const TextStyle(
                    fontFamily:
                        'monospace',
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'Presented now',

                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                SelectableText(
                  '$newKeyType\n'
                  '$newFingerprint',

                  style:
                      const TextStyle(
                    fontFamily:
                        'monospace',
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'A host-key change can be '
                  'legitimate after reinstalling '
                  'the server or regenerating its '
                  'SSH keys. It can also mean you '
                  'are connecting to a different '
                  'machine.',
                ),

                const SizedBox(
                  height: 12,
                ),

                const Text(
                  'Only trust the new key if you '
                  'expected this change.',

                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
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
                'Trust New Key',
              ),
            ),
          ],
        );
      },
    );
  }
}