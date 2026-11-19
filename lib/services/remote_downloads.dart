import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'remote_download_worker.dart';
import 'remote_ota_worker.dart';

class RemoteDownload {
  final String id, name, folder, phase, error, expectedSha256, actualSha256;
  final int bytes;
  final int? total;

  RemoteDownload.fromJson(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      folder = data['folder'] as String,
      phase = data['phase'] as String,
      error = data['error'] as String? ?? '',
      expectedSha256 = data['expectedSha256'] as String? ?? '',
      actualSha256 = data['actualSha256'] as String? ?? '',
      bytes = data['bytes'] as int? ?? 0,
      total = data['total'] as int?;

  bool get active => const {
    'starting',
    'downloading',
    'verifying',
    'publishing',
    'stopping',
  }.contains(phase);

  bool get canResume =>
      const {'paused', 'interrupted', 'failed'}.contains(phase);
  bool get canCancel => phase != 'complete' && phase != 'cancelled';

  String get label => switch (phase) {
    'starting' => 'Starting',
    'downloading' => 'Downloading',
    'verifying' => 'Checking SHA-256',
    'publishing' => 'Finishing',
    'stopping' => 'Stopping',
    'paused' => 'Paused',
    'interrupted' => 'Interrupted · ready to resume',
    'failed' => 'Download failed',
    'complete' =>
      expectedSha256.isEmpty ? 'Complete' : 'Complete · SHA-256 verified',
    'cancelled' => 'Cancelled',
    _ => 'Unknown status',
  };
}

class RemoteDownloads {
  final Device device;
  final SshSession session;
  final Set<String> _installed = {};
  bool? _windows;
  String? _python;

  RemoteDownloads(this.device, this.session);

  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String? validateUrl(String text) {
    final url = Uri.tryParse(text.trim());
    if (url == null ||
        !const {'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        RegExp(r'[\x00-\x1f]').hasMatch(text)) {
      return 'Enter an HTTP or HTTPS download URL.';
    }
    return null;
  }

  static String suggestedName(String text) {
    try {
      final uri = Uri.parse(text.trim());
      final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      return name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    } on FormatException {
      return '';
    }
  }

  static String quotePowerShell(String value) =>
      "'${value.replaceAll("'", "''")}'";

  Future<Map<String, dynamic>> list() async => _call({'action': 'list'});

  Future<void> start({
    required String id,
    required String url,
    required String name,
    required String folder,
    required String sha256,
  }) async {
    await _call({
      'action': 'start',
      'id': id,
      'url': url.trim(),
      'name': name.trim(),
      'folder': folder.trim(),
      'sha256': sha256.trim(),
    });
  }

  Future<void> action(RemoteDownload job, String action) async {
    await _call({'action': action, 'id': job.id});
  }

  Future<Map<String, dynamic>> ota(
    String action, [
    Map<String, dynamic> values = const {},
  ]) => _call({'action': action, ...values}, ota: true);

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> request, {
    bool ota = false,
  }) async {
    if (!session.isConnected || session.deviceId != device.id) {
      throw StateError('Reconnect to ${device.name} to manage its downloads.');
    }
    final client = session.client;
    if (_windows == null) {
      if (device.shellStyle == 'auto') {
        final probe = await session.run(
          'uname -s',
          timeout: const Duration(seconds: 10),
        );
        final os = utf8.decode(probe, allowMalformed: true).trim();
        _windows = !RegExp(r'^(Linux|Darwin|FreeBSD|OpenBSD|NetBSD)\s*$')
            .hasMatch(os);
      } else {
        _windows = device.shellStyle == 'windows';
      }
    }
    final windows = _windows!;
    if (windows && _python == null) {
      final result = await session.runPowerShell(r'''
$candidates=[Collections.Generic.List[string]]::new()
foreach($name in @('python3','python','py')) {
 foreach($cmd in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) {
  if($cmd.Source -and $cmd.Source -notmatch '\\Microsoft\\WindowsApps\\'){$candidates.Add($cmd.Source)}
 }
}
foreach($registry in @('HKCU:\Software\Python\PythonCore','HKLM:\Software\Python\PythonCore','HKLM:\Software\WOW6432Node\Python\PythonCore')) {
 foreach($version in @(Get-ChildItem -LiteralPath $registry -ErrorAction SilentlyContinue)) {
  $install=Get-Item -LiteralPath ($version.PSPath+'\InstallPath') -ErrorAction SilentlyContinue
  if($install) {
   $exe=[string]$install.GetValue('ExecutablePath')
   if(-not $exe){$exe=Join-Path ([string]$install.GetValue('')) 'python.exe'}
   if($exe){$candidates.Add($exe)}
  }
 }
}
$found=$null
foreach($exe in @($candidates | Select-Object -Unique)) {
 $process=$null
 try {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$exe
  $prefix=if([IO.Path]::GetFileName($exe) -ieq 'py.exe'){'-3 '}else{''}
  $info.Arguments=$prefix+'-c "import sys; sys.exit(1) if sys.version_info < (3,9) else None; print(sys.executable)"'
  $info.UseShellExecute=$false
  $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true
  $info.RedirectStandardError=$true
  $process=[Diagnostics.Process]::Start($info)
  $output=$process.StandardOutput.ReadToEndAsync()
  $errors=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(5000)){$process.Kill();continue}
  $probe=$output.GetAwaiter().GetResult().Trim()
  [void]$errors.GetAwaiter().GetResult()
  if($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $probe -PathType Leaf)){$found=$probe;break}
 } catch {
  # A failed alias or obsolete installation must not stop the remaining probes.
 } finally {
  if($process){$process.Dispose()}
 }
}
if(-not $found){throw 'Install Python 3.9 or newer for this Windows account to use Remote downloads.'}
$found
''', label: 'Remote download support');
      _python = utf8.decode(result, allowMalformed: true).trim();
      if (_python!.isEmpty) {
        throw StateError('Python 3.9 or newer is required on this device.');
      }
    }
    final payload = base64Encode(utf8.encode(jsonEncode(request)));
    final bootstrap = StringBuffer('import sys, pathlib, base64, os, runpy\n')
      ..writeln(
        'if sys.version_info < (3,9): raise RuntimeError("Python 3.9 or newer is required.")',
      )
      ..writeln('root = pathlib.Path.home() / ".wirehelm" / "remote-downloads"')
      ..writeln('root.mkdir(mode=0o700, parents=True, exist_ok=True)')
      ..writeln(
        'if root.is_symlink(): raise RuntimeError("The download journal directory must not be a symbolic link.")',
      )
      ..writeln('path = root / "${ota ? 'ota-worker-1.py' : 'worker-1.py'}"');
    final sources = {
      'worker-1.py': remoteDownloadWorker,
      if (ota) 'ota-worker-1.py': remoteOtaWorker,
    };
    for (final entry in sources.entries) {
      if (_installed.contains(entry.key)) continue;
      final script = base64Encode(utf8.encode(entry.value));
      bootstrap
        ..writeln('destination = root / "${entry.key}"')
        ..writeln('source = base64.b64decode("$script")')
        ..writeln(
          'if not destination.exists() or destination.read_bytes() != source:',
        )
        ..writeln(
          '    temp = root / ("worker-" + os.urandom(8).hex() + ".tmp")',
        )
        ..writeln('    temp.write_bytes(source)')
        ..writeln('    os.replace(temp, destination)');
    }
    bootstrap
      ..writeln('sys.argv = [str(path), "$payload"]')
      ..writeln('runpy.run_path(str(path), run_name="__main__")');
    final encoded = base64Encode(utf8.encode(bootstrap.toString()));
    // The persistent Windows helper journals requests to disk. OTA requests
    // contain passphrases, so send them through a fresh SSH channel's stdin.
    final privateLauncher =
        '[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([Console]::In.ReadLine())) | & ${quotePowerShell(_python ?? '')} -';
    final launcherBytes = Uint8List.fromList(
      privateLauncher.codeUnits
          .expand((unit) => [unit & 255, unit >> 8])
          .toList(),
    );
    final timeout = Duration(
      seconds: ota && request['action'] == 'browse' ? 12 : 25,
    );
    final raw = windows
        ? ota
              ? await session.run(
                  'powershell.exe -NoProfile -NonInteractive -EncodedCommand ${base64Encode(launcherBytes)}',
                  input: Uint8List.fromList(utf8.encode('$encoded\n')),
                  timeout: timeout,
                )
              : await session.runPowerShell(
                  "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | & ${quotePowerShell(_python!)} -",
                  label: 'Remote downloads',
                  timeout: timeout,
                )
        : await session.run(
            'python3 -',
            input: Uint8List.fromList(utf8.encode(bootstrap.toString())),
            timeout: timeout,
          );
    if (!identical(client, session.client)) {
      throw StateError(
        'The connection changed. Refresh to check the download result.',
      );
    }
    final lines = const LineSplitter().convert(
      utf8.decode(raw, allowMalformed: true),
    );
    const prefix = '__WIREHELM_DOWNLOAD__';
    final marked = lines.where((line) => line.startsWith(prefix));
    if (marked.isEmpty) {
      _installed.clear();
      throw StateError(
        'Remote downloads could not respond. Check that Python 3.9 or newer is available on this device.',
      );
    }
    _installed.addAll(sources.keys);
    final reply = jsonDecode(
      marked.last.substring(prefix.length),
    ) as Map<String, dynamic>;
    if (reply['ok'] != true) {
      throw StateError(reply['error'] as String? ?? 'The operation failed.');
    }
    return Map<String, dynamic>.from(reply['result'] as Map);
  }
}
