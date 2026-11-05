import 'package:flutter/material.dart';

import '../models/device.dart';

class DeviceCard extends StatelessWidget {
  final Device device;

  final bool connected;
  final bool connecting;
  final bool interactionDisabled;

  final bool showConnectionEndpoint;

  final bool installIdentityEnabled;

  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onInstallIdentity;
  final VoidCallback? onDisconnect;
  final VoidCallback onDelete;

  const DeviceCard({
    super.key,
    required this.device,
    required this.connected,
    required this.connecting,
    required this.interactionDisabled,
    required this.showConnectionEndpoint,
    required this.installIdentityEnabled,
    required this.onOpen,
    required this.onEdit,
    required this.onInstallIdentity,
    this.onDisconnect,
    required this.onDelete,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Card(
        child: ListTile(
          leading: const Icon(
            Icons.computer,
            size: 36,
          ),

          title: Text(
            device.name,
          ),

          subtitle: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (showConnectionEndpoint) ...[
                Text(
                  '${device.username}@'
                  '${device.host}:'
                  '${device.port}',
                ),

                const SizedBox(
                  height: 4,
                ),
              ],

              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: connected
                        ? Colors.green
                        : Colors.grey,
                  ),

                  const SizedBox(
                    width: 6,
                  ),

                  Text(
                    connected
                        ? 'Connected'
                        : 'Disconnected',
                  ),
                ],
              ),
            ],
          ),

          onTap:
              interactionDisabled
                  ? null
                  : onOpen,

          trailing:
              connecting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : PopupMenuButton<String>(
                      tooltip:
                          'Device options',

                      onSelected: (
                        value,
                      ) {
                        switch (value) {
                          case 'edit':
                            onEdit();
                            break;

                          case 'install_identity':
                            onInstallIdentity();
                            break;

                          case 'disconnect':
                            onDisconnect
                                ?.call();
                            break;

                          case 'delete':
                            onDelete();
                            break;
                        }
                      },

                      itemBuilder: (
                        context,
                      ) {
                        return [
                          const PopupMenuItem(
                            value:
                                'edit',

                            child:
                                Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                ),

                                SizedBox(
                                  width: 12,
                                ),

                                Text(
                                  'Edit',
                                ),
                              ],
                            ),
                          ),

                          PopupMenuItem(
                            value:
                                'install_identity',

                            enabled:
                                installIdentityEnabled,

                            child:
                                const Row(
                              children: [
                                Icon(
                                  Icons.key,
                                ),

                                SizedBox(
                                  width: 12,
                                ),

                                Text(
                                  'Install identity',
                                ),
                              ],
                            ),
                          ),

                          if (connected &&
                              onDisconnect !=
                                  null) ...[
                            const PopupMenuDivider(),

                            const PopupMenuItem(
                              value:
                                  'disconnect',

                              child:
                                  Row(
                                children: [
                                  Icon(
                                    Icons.link_off,
                                  ),

                                  SizedBox(
                                    width: 12,
                                  ),

                                  Text(
                                    'Disconnect',
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const PopupMenuDivider(),

                          const PopupMenuItem(
                            value:
                                'delete',

                            child:
                                Row(
                              children: [
                                Icon(
                                  Icons.delete,
                                ),

                                SizedBox(
                                  width: 12,
                                ),

                                Text(
                                  'Delete',
                                ),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
        ),
      ),
    );
  }
}