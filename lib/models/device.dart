import 'remote_command.dart';

class Device {
  final String id;
  final String name;
  final String host;
  final String localHost;
  final int refreshSeconds;
  final int port;
  final String username;

  // auto | windows | linux
  final String shellStyle;

  // key | password
  final String authType;

  // Used in the next stage for multiple identities.
  final String? identityId;

  // Used in the next stage for securely stored passwords.
  final String? passwordId;

  final List<RemoteCommand> commands;

  const Device({
    required this.id,
    required this.name,
    required this.host,
    this.localHost = '',
    this.refreshSeconds = 20,
    required this.port,
    required this.username,
    this.shellStyle = 'auto',
    this.authType = 'key',
    this.identityId,
    this.passwordId,
    required this.commands,
  });

  Device copyWith({
    String? id,
    String? name,
    String? host,
    String? localHost,
    int? refreshSeconds,
    int? port,
    String? username,
    String? shellStyle,
    String? authType,
    String? identityId,
    String? passwordId,
    List<RemoteCommand>? commands,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      localHost: localHost ?? this.localHost,
      refreshSeconds: refreshSeconds ?? this.refreshSeconds,
      port: port ?? this.port,
      username: username ?? this.username,
      shellStyle: shellStyle ?? this.shellStyle,
      authType: authType ?? this.authType,
      identityId: identityId ?? this.identityId,
      passwordId: passwordId ?? this.passwordId,
      commands: commands ?? this.commands,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'localHost': localHost,
      'refreshSeconds': refreshSeconds,
      'port': port,
      'username': username,
      'shellStyle': shellStyle,
      'authType': authType,
      'identityId': identityId,
      'passwordId': passwordId,
      'commands': commands.map((command) => command.toJson()).toList(),
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    final commandList = json['commands'] as List<dynamic>? ?? [];

    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      localHost: json['localHost'] as String? ?? '',
      refreshSeconds: (json['refreshSeconds'] as int? ?? 20).clamp(5, 300),
      port: json['port'] as int,
      username: json['username'] as String,

      // Backward-compatible with devices
      // already saved on your phone.
      shellStyle: json['shellStyle'] as String? ?? 'auto',

      authType: json['authType'] as String? ?? 'key',

      identityId: json['identityId'] as String?,

      passwordId: json['passwordId'] as String?,

      commands: commandList
          .map(
            (item) => RemoteCommand.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}
