import 'dart:convert';

import '../models/remote_command.dart';

String encodeCommandTransfer(RemoteCommand command) => jsonEncode({
  'format': 'remote_control.command',
  'version': 1,
  'command': command.toJson(),
});

RemoteCommand decodeCommandTransfer(String text) {
  final data = jsonDecode(text);
  if (data is! Map ||
      data['format'] != 'remote_control.command' ||
      data['version'] != 1 ||
      data['command'] is! Map) {
    throw const FormatException('Clipboard does not contain a copied command.');
  }
  return RemoteCommand.fromJson(
    Map<String, dynamic>.from(data['command'] as Map),
  );
}

RemoteCommand cloneCommand(
  RemoteCommand command,
  Iterable<RemoteCommand> existing, {
  bool rename = false,
}) {
  final usedIds = existing.map((item) => item.id).toSet();
  final base = DateTime.now().microsecondsSinceEpoch.toString();
  var id = base;
  var suffix = 2;
  while (id == command.id || usedIds.contains(id)) {
    id = '${base}_${suffix++}';
  }
  var name = command.name;
  if (rename) {
    final usedNames = existing.map((item) => item.name.toLowerCase()).toSet();
    name = '${command.name} (copy)';
    var number = 2;
    while (usedNames.contains(name.toLowerCase())) {
      name = '${command.name} (copy ${number++})';
    }
  }
  // Round-trip nested parameters, targets and states so the copy is independent.
  return RemoteCommand.fromJson(command.toJson()).copyWith(id: id, name: name);
}
