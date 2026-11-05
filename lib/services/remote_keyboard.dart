import 'dart:convert';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

const remoteKeys = <String, String>{
  'Enter': 'Return',
  'Tab': 'Tab',
  'Escape': 'Escape',
  'Backspace': 'BackSpace',
  'Delete': 'Delete',
  'Left': 'Left',
  'Right': 'Right',
  'Up': 'Up',
  'Down': 'Down',
  'Home': 'Home',
  'End': 'End',
  'Page Up': 'Prior',
  'Page Down': 'Next',
  'Copy': 'ctrl+c',
  'Paste': 'ctrl+v',
  'Select all': 'ctrl+a',
  'Undo': 'ctrl+z',
  'Switch window': 'alt+Tab',
  'F5': 'F5',
  'F11': 'F11',
  'F1': 'F1',
  'F2': 'F2',
  'F3': 'F3',
  'F4': 'F4',
  'F6': 'F6',
  'F7': 'F7',
  'F8': 'F8',
  'F9': 'F9',
  'F10': 'F10',
  'F12': 'F12',
  'Insert': 'Insert',
  'Space': 'space',
  'Print screen': 'Print',
  'Pause': 'Pause',
};

String normalizeRemoteChord(String chord) {
  final parts = chord.trim().split(RegExp(r'\s*\+\s*'));
  if (parts.length < 2) {
    throw const FormatException(
      'Use a modifier and key, such as Ctrl+Shift+Esc.',
    );
  }
  final modifiers = <String>[];
  for (final raw in parts.take(parts.length - 1)) {
    final mod = switch (raw.toLowerCase()) {
      'ctrl' || 'control' => 'ctrl',
      'alt' => 'alt',
      'shift' => 'shift',
      'win' || 'super' || 'meta' => 'super',
      _ => '',
    };
    if (mod.isEmpty || modifiers.contains(mod)) {
      throw const FormatException(
        'Use Ctrl, Alt, Shift, or Win as shortcut modifiers.',
      );
    }
    modifiers.add(mod);
  }
  final rawKey = parts.last.trim();
  final aliases = <String, String>{
    'esc': 'Escape',
    'return': 'Enter',
    'spacebar': 'Space',
    'pgup': 'Page Up',
    'pageup': 'Page Up',
    'pgdn': 'Page Down',
    'pagedown': 'Page Down',
    'printscreen': 'Print screen',
  };
  final key =
      aliases[rawKey.toLowerCase()] ??
      remoteKeys.keys.cast<String?>().firstWhere(
        (candidate) => candidate?.toLowerCase() == rawKey.toLowerCase(),
        orElse: () => rawKey,
      )!;
  final supported =
      (remoteKeys.containsKey(key) &&
          ![
            'Copy',
            'Paste',
            'Select all',
            'Undo',
            'Switch window',
          ].contains(key)) ||
      RegExp(r'^[A-Za-z0-9]$').hasMatch(key) ||
      RegExp(r'^F(?:[1-9]|1[0-2])$', caseSensitive: false).hasMatch(key);
  if (!supported) {
    throw const FormatException('Unsupported key. Example: Ctrl+Alt+R.');
  }
  final xkey = remoteKeys[key] ?? key.toLowerCase();
  final prefix = modifiers.map((m) => m == 'super' ? 'super' : m).join('+');
  return '$prefix+$xkey';
}

String sendKeysLiteral(String text) {
  final out = StringBuffer();
  for (final ch in text.replaceAll('\r\n', '\n').split('')) {
    out.write(switch (ch) {
      '\n' => '{ENTER}',
      '\t' => '{TAB}',
      '\r' => '',
      '{' => '{{}',
      '}' => '{}}',
      '+' || '^' || '%' || '~' || '(' || ')' || '[' || ']' => '{$ch}',
      _ => ch,
    });
  }
  return out.toString();
}

String keyboardCommand({
  required bool windows,
  String? text,
  String? key,
  String? shortcut,
}) {
  if ([text, key, shortcut].where((item) => item != null).length != 1) {
    throw ArgumentError('Choose text, key, or shortcut.');
  }
  if (key != null && !remoteKeys.containsKey(key)) {
    throw ArgumentError('Unknown key');
  }
  final chord = shortcut == null ? null : normalizeRemoteChord(shortcut);
  if (windows) {
    const keys = <String, String>{
      'Enter': '{ENTER}',
      'Tab': '{TAB}',
      'Escape': '{ESC}',
      'Backspace': '{BACKSPACE}',
      'Delete': '{DELETE}',
      'Left': '{LEFT}',
      'Right': '{RIGHT}',
      'Up': '{UP}',
      'Down': '{DOWN}',
      'Home': '{HOME}',
      'End': '{END}',
      'Page Up': '{PGUP}',
      'Page Down': '{PGDN}',
      'Copy': '^c',
      'Paste': '^v',
      'Select all': '^a',
      'Undo': '^z',
      'Switch window': '%{TAB}',
      'F5': '{F5}',
      'F11': '{F11}',
      'F1': '{F1}',
      'F2': '{F2}',
      'F3': '{F3}',
      'F4': '{F4}',
      'F6': '{F6}',
      'F7': '{F7}',
      'F8': '{F8}',
      'F9': '{F9}',
      'F10': '{F10}',
      'F12': '{F12}',
      'Insert': '{INSERT}',
      'Space': ' ',
      'Print screen': '{PRTSC}',
      'Pause': '{PAUSE}',
    };
    final action = text != null
        ? sendKeysLiteral(text)
        : shortcut != null
        ? _windowsChord(shortcut)
        : keys[key] ?? '{${remoteKeys[key]!.toUpperCase()}}';
    final encoded = base64Encode(utf8.encode(action));
    return "\$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); \$s=New-Object -ComObject WScript.Shell; \$s.SendKeys(\$k); 'Keys sent'";
  }
  String quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
  final action = text != null
      ? 'type --clearmodifiers -- ${quote(text)}'
      : 'key --clearmodifiers ${quote(chord ?? remoteKeys[key]!)}';
  return 'command -v xdotool >/dev/null || { echo "Install xdotool on the Linux device first." >&2; exit 1; }; DISPLAY=\${DISPLAY:-:0} xdotool $action && printf "__RC_KEYS_SENT__\\n"';
}

Future<void> sendRemoteKeyboard(
  Device device,
  SshSession session, {
  required bool windows,
  String? text,
  String? key,
  String? shortcut,
}) async {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device first.');
  }
  final bytes = await session.runCommand(
    keyboardCommand(windows: windows, text: text, key: key, shortcut: shortcut),
    executionMode: windows ? 'interactive' : 'standard',
    timeout: const Duration(seconds: 30),
  );
  final output = utf8.decode(bytes, allowMalformed: true).trim();
  if (windows && output != 'Keys sent') {
    throw StateError(output.isEmpty ? 'No keyboard acknowledgement.' : output);
  }
  if (!windows && output != '__RC_KEYS_SENT__') {
    throw StateError(output.isEmpty ? 'No keyboard acknowledgement.' : output);
  }
}

String _windowsChord(String chord) {
  final parts = chord.split(RegExp(r'\s*\+\s*'));
  final modifiers = parts
      .take(parts.length - 1)
      .map(
        (m) => switch (m.toLowerCase()) {
          'ctrl' || 'control' => '^',
          'alt' => '%',
          'shift' => '+',
          'win' || 'super' || 'meta' => '#',
          _ => '',
        },
      )
      .join();
  final raw = parts.last;
  final key = switch (raw.toLowerCase()) {
    'escape' => '{ESC}',
    'enter' => '{ENTER}',
    'tab' => '{TAB}',
    'backspace' => '{BACKSPACE}',
    'delete' => '{DELETE}',
    'left' => '{LEFT}',
    'right' => '{RIGHT}',
    'up' => '{UP}',
    'down' => '{DOWN}',
    'home' => '{HOME}',
    'end' => '{END}',
    'page up' => '{PGUP}',
    'page down' => '{PGDN}',
    'insert' => '{INSERT}',
    'print screen' => '{PRTSC}',
    'pause' => '{PAUSE}',
    _ when RegExp(r'^f(?:[1-9]|1[0-2])$', caseSensitive: false).hasMatch(raw) =>
      '{$raw}',
    _ => raw.length == 1 ? '{${raw.toLowerCase()}}' : '{${raw.toUpperCase()}}',
  };
  return '$modifiers$key';
}
