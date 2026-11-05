import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'download_store.dart';

class RemoteScreenshotCapture {
  final Uint8List preview;
  final String originalPath;
  final bool windows;

  const RemoteScreenshotCapture({
    required this.preview,
    required this.originalPath,
    required this.windows,
  });
}

/// Decodes the legacy inline PNG response, retained for saved templates and
/// compatibility with earlier screenshot helpers.
Uint8List decodeScreenshot(String output) {
  final match = RegExp(r'__COCKPIT_PNG__([A-Za-z0-9+/=]+)').firstMatch(output);
  if (match == null) throw StateError('Screenshot failed: ${output.trim()}');
  final bytes = base64Decode(match.group(1)!);
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length ||
      List.generate(
        signature.length,
        (i) => bytes[i] == signature[i],
      ).contains(false)) {
    throw const FormatException(
      'The remote device did not return a PNG image.',
    );
  }
  return bytes;
}

const windowsScreenshotScript = r'''
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class CockpitDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][CockpitDpi]::SetProcessDPIAware()
$staleBefore=(Get-Date).AddHours(-24)
Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'NodeCockpit_Screenshot_*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $staleBefore -and $_.Name -match '^NodeCockpit_Screenshot_[a-f0-9]{32}$' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$root=Join-Path $env:TEMP ('NodeCockpit_Screenshot_'+[Guid]::NewGuid().ToString('N'))
$acl=[Security.AccessControl.DirectorySecurity]::new(); $acl.SetAccessRuleProtection($true,$false)
$inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) { $rule=[Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow); [void]$acl.AddAccessRule($rule) }
[void][IO.Directory]::CreateDirectory($root,$acl)
$original=Join-Path $root 'original.png'; $preview=Join-Path $root 'preview.jpg'
$r=[System.Windows.Forms.SystemInformation]::VirtualScreen
$b=New-Object System.Drawing.Bitmap($r.Width,$r.Height); $g=[System.Drawing.Graphics]::FromImage($b)
try {
 $g.CopyFromScreen($r.Left,$r.Top,0,0,$r.Size); $b.Save($original,[System.Drawing.Imaging.ImageFormat]::Png)
 $scale=[Math]::Min(1.0,1280.0/[double]$b.Width); $w=[Math]::Max(1,[int]($b.Width*$scale)); $h=[Math]::Max(1,[int]($b.Height*$scale))
 $small=New-Object System.Drawing.Bitmap($w,$h); $sg=[System.Drawing.Graphics]::FromImage($small)
 try { $sg.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $sg.DrawImage($b,0,0,$w,$h); $small.Save($preview,[System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $sg.Dispose(); $small.Dispose() }
 '__COCKPIT_PATH__'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($original))
 '__COCKPIT_PREVIEW__'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($preview))
} finally { $g.Dispose(); $b.Dispose() }
''';

const linuxScreenshotScript = r'''
set -e
stale_before=$(date -d '24 hours ago' +%s 2>/dev/null || echo 0)
for old in /tmp/NodeCockpit_Screenshot_*; do
  [ -d "$old" ] || continue
  name=${old##*/}; suffix=${name#NodeCockpit_Screenshot_}; [ "${#suffix}" = 32 ] || continue
  case "$suffix" in *[!A-Za-z0-9]*) continue ;; esac
  [ "$(stat -c %Y "$old" 2>/dev/null || echo 0)" -lt "$stale_before" ] && rm -rf -- "$old"
done
d=$(mktemp -d /tmp/NodeCockpit_Screenshot_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX)
chmod 700 "$d"
f="$d/original.png"
export DISPLAY=${DISPLAY:-:0}
if command -v grim >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then grim "$f"
elif command -v scrot >/dev/null 2>&1; then scrot "$f"
elif command -v gnome-screenshot >/dev/null 2>&1; then gnome-screenshot -f "$f"
else rmdir "$d"; echo 'Install scrot (X11) or grim (Wayland), and connect as the desktop user.' >&2; exit 1; fi
test -s "$f" || { rm -rf -- "$d"; echo 'Screenshot tool returned no image.' >&2; exit 1; }
if command -v ffmpeg >/dev/null 2>&1; then ffmpeg -loglevel error -y -i "$f" -vf 'scale=1280:-2:force_original_aspect_ratio=decrease' -q:v 8 "$d/preview.jpg"
elif command -v convert >/dev/null 2>&1; then convert "$f" -resize '1280x1280>' -quality 55 "$d/preview.jpg"
else cp "$f" "$d/preview.jpg"; fi
printf '__COCKPIT_PATH__'; printf %s "$f" | base64 | tr -d '\n'; printf '\n'
printf '__COCKPIT_PREVIEW__'; base64 "$d/preview.jpg" | tr -d '\n'; printf '\n'
''';

Future<bool> _isWindows(Device device, SshSession session) async =>
    device.shellStyle == 'auto'
    ? !utf8
          .decode(
            await session.run('uname -s', timeout: const Duration(seconds: 10)),
            allowMalformed: true,
          )
          .toLowerCase()
          .contains('linux')
    : device.shellStyle == 'windows';

Future<RemoteScreenshotCapture> takeRemoteScreenshot(
  Device device,
  SshSession session,
) async {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device first.');
  }
  final windows = await _isWindows(device, session);
  final result = await session.runCommand(
    windows ? windowsScreenshotScript : linuxScreenshotScript,
    executionMode: windows ? 'interactive' : 'standard',
    timeout: const Duration(seconds: 60),
  );
  final output = utf8.decode(result, allowMalformed: true);
  final pathMatch = RegExp(r'__COCKPIT_PATH__([A-Za-z0-9+/=]+)')
      .firstMatch(output);
  final previewMatch = RegExp(r'__COCKPIT_PREVIEW__([A-Za-z0-9+/=]+)')
      .firstMatch(output);
  if (pathMatch == null || previewMatch == null) {
    throw StateError('Screenshot preview failed: ${output.trim()}');
  }
  final path = utf8.decode(base64Decode(pathMatch.group(1)!));
  final safePath = windows
      ? RegExp(
          r'^[A-Za-z]:[/\\]Users[/\\][^/\\]+[/\\]AppData[/\\]Local[/\\]Temp[/\\]NodeCockpit_Screenshot_[a-f0-9]{32}[/\\]original\.png$',
          caseSensitive: false,
        ).hasMatch(path)
      : RegExp(r'^/tmp/NodeCockpit_Screenshot_[A-Za-z0-9]{32}/original\.png$')
            .hasMatch(path);
  if (!safePath) {
    throw const FormatException('The remote screenshot path was invalid.');
  }
  return RemoteScreenshotCapture(
    preview: base64Decode(previewMatch.group(1)!),
    originalPath: path,
    windows: windows,
  );
}

Future<int> downloadOriginalScreenshot(
  SshSession session,
  RemoteScreenshotCapture capture,
  void Function(int received)? onProgress,
) async {
  final sftp = await session.client!.sftp().timeout(
    const Duration(seconds: 20),
  );
  SftpFile? file;
  var saved = false;
  try {
    file = await sftp
        .open(capture.originalPath.replaceAll('\\', '/'))
        .timeout(const Duration(seconds: 20));
    final size = (await file.stat().timeout(const Duration(seconds: 20))).size;
    if (size == null || size <= 0 || size > 300 * 1024 * 1024) {
      throw StateError('Screenshot must be between 1 byte and 300 MB.');
    }
    await DownloadStore.save(
      'Screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
      file.read(length: size, chunkSize: 256 * 1024, maxPendingRequests: 8),
      onProgress: onProgress,
    );
    saved = true;
    return size;
  } finally {
    await file?.close();
    await sftp.close();
    if (saved) await cleanupRemoteScreenshot(session, capture);
  }
}

Future<void> cleanupRemoteScreenshot(
  SshSession session,
  RemoteScreenshotCapture capture,
) async {
  if (!session.isConnected) return;
  try {
    if (capture.windows) {
      final root = capture.originalPath.substring(
        0,
        capture.originalPath.lastIndexOf(RegExp(r'[/\\]')),
      );
      final escaped = root.replaceAll("'", "''");
      await session.runPowerShell(
        "Remove-Item -LiteralPath '$escaped' -Recurse -Force -ErrorAction SilentlyContinue",
        desktop: true,
        label: 'Screenshot cleanup',
        timeout: const Duration(seconds: 8),
      );
    } else {
      final root = capture.originalPath.substring(
        0,
        capture.originalPath.lastIndexOf('/'),
      );
      await session.run(
        'rm -rf -- ${_shellQuote(root)}',
        timeout: const Duration(seconds: 8),
      );
    }
  } catch (_) {
    /* The 24-hour stale sweep is the fallback. */
  }
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
