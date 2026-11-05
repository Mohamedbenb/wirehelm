class SshIdentity {
  final String id;
  final String name;
  final String publicKey;

  const SshIdentity({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  SshIdentity copyWith({
    String? id,
    String? name,
    String? publicKey,
  }) {
    return SshIdentity(
      id: id ?? this.id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
    };
  }

  factory SshIdentity.fromJson(
    Map<String, dynamic> json,
  ) {
    return SshIdentity(
      id: json['id'] as String,
      name: json['name'] as String,
      publicKey: json['publicKey'] as String,
    );
  }
}