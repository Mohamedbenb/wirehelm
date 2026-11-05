import 'file_size.dart';

String fileOwnerLabel(Object? id, {bool group = false}) {
  const names = {
    0: 'root',
    1000: 'system',
    1001: 'radio',
    1002: 'bluetooth',
    1013: 'media',
    1023: 'media_rw',
    2000: 'shell',
    9999: 'nobody',
  };
  if (id is! int) return 'Unknown';
  return names[id] ?? '${group ? 'GID' : 'UID'} $id';
}

String filePermissionSymbols(Object? mode) {
  final bits = int.tryParse('$mode', radix: 8);
  if (bits == null) return 'Unknown';
  final out = StringBuffer();
  for (final shift in [6, 3, 0]) {
    out.write(bits & (4 << shift) != 0 ? 'r' : '-');
    out.write(bits & (2 << shift) != 0 ? 'w' : '-');
    final execute = bits & (1 << shift) != 0;
    final special =
        bits &
            (shift == 6
                ? 0x800
                : shift == 3
                ? 0x400
                : 0x200) !=
        0;
    out.write(
      special
          ? (shift == 0 ? (execute ? 't' : 'T') : (execute ? 's' : 'S'))
          : execute
          ? 'x'
          : '-',
    );
  }
  return out.toString();
}

String filePermissionDescription(
  Object? mode,
  int shift, {
  required bool directory,
}) {
  final bits = int.tryParse('$mode', radix: 8);
  if (bits == null) return 'Unknown';
  final permissions = [
    if (bits & (4 << shift) != 0) 'read',
    if (bits & (2 << shift) != 0) 'write',
    if (bits & (1 << shift) != 0) directory ? 'enter' : 'execute',
  ];
  return permissions.isEmpty ? 'No access' : permissions.join(', ');
}

String fileEntrySubtitle(Map<String, dynamic> entry) {
  if (entry['error'] != null) return '${entry['error']}';
  final type = entry['link'] == true
      ? 'Symbolic link'
      : entry['directory'] == true
      ? 'Folder'
      : formatFileSize(entry['size'] as num?);
  return '$type · Owner: ${fileOwnerLabel(entry['uid'])}';
}

String fileParentPath(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? '/' : path.substring(0, index);
}
