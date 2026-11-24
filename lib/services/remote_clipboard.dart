import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'background_keep_alive.dart';
import 'linux_desktop.dart';

String _ps(String s) => "'${s.replaceAll("'", "''")}'";
String _sh(String s) => "'${s.replaceAll("'", "'\\''")}'";

String clipboardRootScript(String id) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
    throw ArgumentError('Invalid transfer ID');
  }
  return r'''
$ErrorActionPreference='Stop'
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
Get-ChildItem -LiteralPath $temp -Directory -Filter 'Wirehelm_Clipboard_*' | Where-Object { $_.Name -match '^Wirehelm_Clipboard_[a-f0-9]{32}$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Select-Object -First 20 | ForEach-Object {
 if ([IO.Path]::GetDirectoryName($_.FullName).TrimEnd('\') -eq $temp) {
  try { [IO.File]::Delete((Join-Path $_.FullName 'payload.bin')); [IO.Directory]::Delete($_.FullName,$false) } catch { }
 }
}
$root=Join-Path $temp 'Wirehelm_Clipboard_ID'
[void](New-Item -ItemType Directory -Path $root -ErrorAction Stop)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
icacls.exe $root /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect clipboard transfer folder.' }
'__WH_CLIP_ROOT__'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root))
'''
      .replaceAll('Clipboard_ID', 'Clipboard_$id');
}

String windowsClipboardScript(String root, String id, {required bool image}) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
    throw ArgumentError('Invalid transfer ID');
  }
  final encoded = base64Encode(utf8.encode(root));
  return r'''
$ErrorActionPreference='Stop'
$root=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('ROOT64'))
$root=[IO.Path]::GetFullPath($root)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
if ([IO.Path]::GetDirectoryName($root).TrimEnd('\') -ne $temp -or [IO.Path]::GetFileName($root) -ne 'Wirehelm_Clipboard_ID') { throw 'Invalid clipboard transfer folder.' }
$file=Join-Path $root 'payload.bin'
try {
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Clipboard requires an STA desktop session.' }
 $bitmap=$null
 try {
  if (IMAGE) {
   $original=[Drawing.Image]::FromFile($file)
   try { $bitmap=[Drawing.Bitmap]::new($original) } finally { $original.Dispose() }
  } else { $text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) }
  for ($attempt=0;$attempt -lt 5;$attempt++) {
   try {
    if (IMAGE) { [Windows.Forms.Clipboard]::SetImage($bitmap) } else { [Windows.Forms.Clipboard]::SetText($text,[Windows.Forms.TextDataFormat]::UnicodeText) }
    break
   } catch { if ($attempt -eq 4) { throw }; Start-Sleep -Milliseconds 150 }
  }
 } finally { if ($bitmap) { $bitmap.Dispose() } }
 '__WH_CLIP_OK__'
} finally {
 [IO.File]::Delete($file)
 [IO.Directory]::Delete($root,$false)
}
'''
      .replaceAll('ROOT64', encoded)
      .replaceAll('Clipboard_ID', 'Clipboard_$id')
      .replaceAll('IMAGE', image ? r'$true' : r'$false');
}

String clipboardCleanupScript(String root, String id) =>
    '''
\$ErrorActionPreference='Stop'
\$root=${_ps(root)}
\$root=[IO.Path]::GetFullPath(\$root)
\$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\\')
if ([IO.Path]::GetDirectoryName(\$root).TrimEnd('\\') -eq \$temp -and [IO.Path]::GetFileName(\$root) -eq 'Wirehelm_Clipboard_$id') {
 [IO.File]::Delete((Join-Path \$root 'payload.bin'))
 if ([IO.Directory]::Exists(\$root)) { [IO.Directory]::Delete(\$root,\$false) }
}
''';

bool validClipboardRoot(String root, String id, bool windows) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
      root.contains(RegExp(r'[\r\n\x00]'))) {
    return false;
  }
  final normalized = root.replaceAll('\\', '/');
  return windows
      ? RegExp(r'^[A-Za-z]:/').hasMatch(normalized) &&
            normalized.endsWith('/Wirehelm_Clipboard_$id') &&
            !normalized.split('/').contains('..')
      : RegExp('^/tmp/Wirehelm_Clipboard_$id\\.[A-Za-z0-9]{6}\$')
            .hasMatch(root);
}

/// Only the selected clip crosses an existing authenticated SSH/SFTP connection.
/// Payload is a private temporary file, never embedded in shell command text.
Future<void> sendClipboardToPc(
  Device device,
  SshSession session,
  Uint8List payload, {
  required bool image,
  required String mime,
}) => backgroundKeepAlive.protect('Send clipboard to PC', () async {
  if (!session.isConnected ||
      session.deviceId != device.id ||
      session.client == null) {
    throw StateError('Connect to this PC in Devices first.');
  }
  if (payload.isEmpty || payload.length > 8 * 1024 * 1024) {
    throw StateError('Clipboard item exceeds the transfer limit.');
  }
  if (image && !RegExp(r'^image/[A-Za-z0-9.+-]+$').hasMatch(mime)) {
    throw StateError('Unsupported image type.');
  }
  final windows =
      device.shellStyle == 'windows' ||
      device.shellStyle == 'auto' &&
          !utf8
              .decode(
                await session.run(
                  'uname -s',
                  timeout: const Duration(seconds: 10),
                ),
                allowMalformed: true,
              )
              .toLowerCase()
              .contains('linux');
  final random = Random.secure();
  final id = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? root;
  SftpClient? sftp;
  SftpFile? file;
  try {
    final output = utf8
        .decode(
          windows
              ? await session.runPowerShell(
                  clipboardRootScript(id),
                  label: 'Prepare clipboard transfer',
                )
              : await session.run(
                  'umask 077; mktemp -d /tmp/Wirehelm_Clipboard_$id.XXXXXX',
                ),
          allowMalformed: true,
        )
        .trim();
    if (windows) {
      final match = RegExp(r'__WH_CLIP_ROOT__([A-Za-z0-9+/=]+)')
          .firstMatch(output);
      if (match == null) {
        throw StateError('Could not prepare a private PC transfer folder.');
      }
      root = utf8.decode(base64Decode(match.group(1)!));
    } else {
      root = output;
    }
    if (!validClipboardRoot(root, id, windows)) {
      root = null;
      throw StateError('PC returned an invalid transfer folder.');
    }
    final path = '${root.replaceAll('\\', '/')}/payload.bin';
    sftp = await session.client!.sftp().timeout(const Duration(seconds: 20));
    file = await sftp
        .open(
          path,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.exclusive,
        )
        .timeout(const Duration(seconds: 20));
    await file
        .write(Stream<Uint8List>.value(payload))
        .done
        .timeout(const Duration(seconds: 90));
    await file.close();
    file = null;
    String result;
    if (windows) {
      result = utf8.decode(
        await session.runPowerShell(
          windowsClipboardScript(root, id, image: image),
          desktop: true,
          label: 'Set PC clipboard',
          timeout: const Duration(seconds: 45),
        ),
        allowMalformed: true,
      );
    } else {
      final type = image ? mime : 'text/plain;charset=utf-8';
      final script =
          '''${linuxDesktopEnvironment}set -eu
f=${_sh(path)}
if [ -n "\$WAYLAND_DISPLAY" ] && [ -S "\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY" ]; then
 if command -v wl-copy >/dev/null 2>&1; then
  wl-copy --type ${_sh(type)} < "\$f" >/dev/null 2>&1
 elif [ ${image ? '1' : '0'} -eq 0 ]; then
  python3 -c 'import sys; from pathlib import Path; from gi.repository import Gio, GLib; bus = Gio.bus_get_sync(Gio.BusType.SESSION, None); bus.call_sync("org.kde.klipper", "/klipper", "org.kde.klipper.klipper", "setClipboardContents", GLib.Variant("(s)", (Path(sys.argv[1]).read_bytes().decode("utf-8"),)), None, Gio.DBusCallFlags.NONE, 4000, None)' "\$f"
 else
  echo 'Install wl-clipboard on the PC to send images to its Wayland clipboard.' >&2; exit 1
 fi
elif command -v xclip >/dev/null 2>&1; then
 export DISPLAY="\${DISPLAY:-:0}"
 xclip -selection clipboard -target ${_sh(image ? mime : 'UTF8_STRING')} -in "\$f" >/dev/null 2>&1
else
 echo 'Install xclip on the PC, and sign in to its desktop.' >&2; exit 1
fi
printf '__WH_CLIP_OK__'
''';
      result = utf8.decode(
        await session.run(
          'sh -c ${desktopShellQuote(script)}',
          timeout: const Duration(seconds: 30),
        ),
        allowMalformed: true,
      );
    }
    if (!result.contains('__WH_CLIP_OK__')) {
      throw StateError(
        'PC clipboard was not confirmed. Check that its desktop session is signed in.',
      );
    }
  } finally {
    try {
      await file?.close();
    } catch (_) {}
    sftp?.close();
    if (root != null && validClipboardRoot(root, id, windows)) {
      try {
        if (windows) {
          await session.runPowerShell(
            clipboardCleanupScript(root, id),
            label: 'Clipboard transfer cleanup',
          );
        } else {
          await session.run(
            'rm -f -- ${_sh('$root/payload.bin')}; rmdir -- ${_sh(root)}',
            timeout: const Duration(seconds: 10),
          );
        }
      } catch (_) {
        /* The next Windows send prunes strictly named stale payloads. */
      }
    }
  }
});
