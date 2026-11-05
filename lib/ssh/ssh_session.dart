import 'dart:async';

import 'dart:convert';

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../services/background_keep_alive.dart';
import '../services/sudo_credentials.dart';
import 'persistent_terminal.dart';
import 'windows_command_host.dart';

//
// Backward-compatible singleton.
//
// Existing screens continue using this until
// they are migrated to SshSessionManager.
//
final sshSession = SshSession();

class SudoAuthenticationException implements Exception {
  final String message;

  const SudoAuthenticationException(this.message);

  @override
  String toString() {
    return message;
  }
}

class SshSession extends ChangeNotifier {
  //
  // true
  //   -> legacy/global session controls the
  //      Android foreground keep-alive.
  //
  // false
  //   -> SshSessionManager controls it.
  //
  final bool manageBackgroundKeepAlive;

  SSHClient? _client;
  SSHSocket? _socket;

  String? _deviceId;
  String? _lastDeviceId;

  bool _connected = false;
  bool _checking = false;
  int _missedHealthChecks = 0;
  bool _appActive = true;

  Timer? _healthTimer;

  //
  // Persistent terminal belonging to this
  // device's SSH session.
  //
  PersistentTerminal? _persistentTerminal;
  WindowsCommandHost? _desktopHost, _standardHost;
  bool _desktopHelperUnavailable = false, _standardHelperUnavailable = false;
  DateTime? _helperRetryAt;
  String? connectionRoute;
  String? connectedHost;
  Duration? connectionDuration;
  final List<Map<String, dynamic>> commandTimings = [];
  void _recordTiming(String mode, Map<String, int> timing) {
    commandTimings.insert(0, {'mode': mode, 'at': DateTime.now(), ...timing});
    if (commandTimings.length > 30) commandTimings.removeLast();
    notifyListeners();
  }

  Future<Uint8List> runPowerShell(
    String script, {
    bool desktop = false,
    String label = 'Command',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    script = normalizeWindowsTypes(script);
    if (_helperRetryAt != null && DateTime.now().isAfter(_helperRetryAt!)) {
      _desktopHelperUnavailable = false;
      _standardHelperUnavailable = false;
      _helperRetryAt = null;
    }
    final client = _client;
    if (client == null || !_connected) throw StateError('Not connected.');
    Future<Uint8List> legacy() {
      final clock = Stopwatch()..start();
      if (desktop) {
        return _runInteractiveWindowsCommand(
          script,
          timeout: timeout,
        ).whenComplete(
          () => _recordTiming('Windows desktop fallback · $label', {
            'total': clock.elapsedMilliseconds,
            'execution': -1,
            'queue': 0,
            'startup': 0,
            'response': -1,
          }),
        );
      }
      const bootstrap =
          r"$s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))))";
      return run(
        'powershell.exe -NoProfile -NonInteractive -EncodedCommand ${_encodePowerShellCommand(bootstrap)}',
        input: Uint8List.fromList(
          utf8.encode('${base64Encode(utf8.encode(script))}\n'),
        ),
        timeout: timeout,
      ).whenComplete(
        () => _recordTiming('Windows SSH fallback · $label', {
          'total': clock.elapsedMilliseconds,
          'execution': -1,
          'queue': 0,
          'startup': 0,
          'response': -1,
        }),
      );
    }

    if (requiresFreshWindowsProcess(script) ||
        (desktop ? _desktopHelperUnavailable : _standardHelperUnavailable)) {
      return legacy();
    }
    final host = desktop
        ? (_desktopHost ??= WindowsCommandHost(
            client,
            desktop: true,
            onTiming: (name, t) => _recordTiming('Windows desktop · $name', t),
          ))
        : (_standardHost ??= WindowsCommandHost(
            client,
            desktop: false,
            onTiming: (name, t) => _recordTiming('Windows SSH · $name', t),
          ));
    try {
      return await host.run(cacheWindowsTypes(script), timeout, label: label);
    } on WindowsHostStartException catch (error) {
      debugPrint(
        'Node Cockpit Windows ${desktop ? 'desktop' : 'SSH'} helper startup: $error',
      );
      _helperRetryAt = DateTime.now().add(const Duration(seconds: 30));
      // Startup failed before submitting anything: legacy execution is safe.
      if (desktop) {
        _desktopHelperUnavailable = true;
      } else {
        _standardHelperUnavailable = true;
      }
      return legacy();
    }
  }

  SshSession({this.manageBackgroundKeepAlive = true});

  bool get isConnected => _connected;

  String? get deviceId => _deviceId;

  String? get lastDeviceId => _lastDeviceId;

  SSHClient? get client => _client;

  PersistentTerminal? get existingTerminal => _persistentTerminal;

  bool get hasTerminal => _persistentTerminal != null;

  //
  // Returns the terminal belonging to this
  // session.
  //
  // Navigating away from TerminalScreen does
  // not remove this object.
  //
  PersistentTerminal terminalFor({required bool isWindows}) {
    final existing = _persistentTerminal;

    if (existing != null) {
      return existing;
    }

    final terminal = PersistentTerminal(
      isWindows: isWindows,
      openShell: () =>
          openShell(command: isWindows ? windowsTerminalCommand : null),
    );

    _persistentTerminal = terminal;

    return terminal;
  }

  void attach({
    required SSHClient client,
    required SSHSocket socket,
    required String deviceId,
    String? route,
    String? host,
  }) {
    final previousDeviceId = _deviceId ?? _lastDeviceId;

    //
    // This matters mainly for the temporary
    // legacy singleton.
    //
    // Never carry a terminal from one physical
    // device into another device.
    //
    if (previousDeviceId != null && previousDeviceId != deviceId) {
      _destroyTerminal();
    }

    //
    // If this same SshSession is receiving a
    // replacement transport, close the old
    // transport first.
    //
    // Do NOT destroy terminal history here:
    // this path can be used by automatic
    // reconnection after transport loss.
    //
    if (_client != null && _client != client) {
      _closeCurrentConnection(clearLastDevice: false, destroyTerminal: false);
    }

    _client = client;

    _socket = socket;

    _deviceId = deviceId;
    connectionRoute = route;
    connectedHost = host;

    _lastDeviceId = deviceId;

    _connected = true;
    _desktopHelperUnavailable = false;
    _standardHelperUnavailable = false;
    _checking = false;
    _missedHealthChecks = 0;
    // Transport closure is authoritative; command failures are not.
    void transportClosed() {
      if (identical(_client, client)) _markDisconnected();
    }

    unawaited(
      client.done.then<void>(
        (_) => transportClosed(),
        onError: (Object _, StackTrace _) => transportClosed(),
      ),
    );

    if (manageBackgroundKeepAlive) {
      unawaited(backgroundKeepAlive.start());
    }

    _startHealthMonitor();

    notifyListeners();
  }

  void setAppActive(bool active) {
    _appActive = active;
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();

    _healthTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_appActive) {
        unawaited(healthCheck());
      }
    });
  }

  void _stopHealthMonitor() {
    _healthTimer?.cancel();

    _healthTimer = null;
  }

  Future<bool> healthCheck() async {
    final client = _client;
    if (client == null || !_connected) return false;
    if (client.isClosed) {
      _markDisconnected();
      return false;
    }
    if (_checking) return _connected;
    _checking = true;
    try {
      await client.ping().timeout(const Duration(seconds: 10));
      if (!identical(_client, client)) return _connected;
      _missedHealthChecks = 0;
      return _connected;
    } catch (_) {
      if (!identical(_client, client)) return _connected;
      if (client.isClosed || (_appActive && ++_missedHealthChecks >= 3)) {
        _markDisconnected();
        return false;
      }
      return _connected;
    } finally {
      if (identical(_client, client)) _checking = false;
    }
  }

  Future<Uint8List> run(
    String command, {
    Uint8List? input,
    Duration? timeout,
  }) async {
    final client = _client;
    if (client == null || !_connected) {
      throw Exception('No active SSH connection.');
    }
    SSHSession? channel;
    var expired = false;
    Future<Uint8List> execute() async {
      final opened = await client.execute(command);
      channel = opened;
      if (expired) {
        opened.close();
        throw TimeoutException('SSH command timed out.');
      }
      final stdout = _collectStream(opened.stdout);
      final stderr = _collectStream(opened.stderr);
      if (input != null) opened.stdin.add(input);
      await opened.stdin.close();
      await opened.done;
      return Uint8List.fromList([...await stdout, ...await stderr]);
    }

    try {
      final operation = execute();
      return timeout == null
          ? await operation
          : await operation.timeout(
              timeout,
              onTimeout: () {
                expired = true;
                throw TimeoutException('SSH command timed out.', timeout);
              },
            );
    } catch (_) {
      // A command timeout is a channel failure, not proof of transport loss.
      if (identical(_client, client) && client.isClosed) _markDisconnected();
      rethrow;
    } finally {
      channel?.close();
    }
  }

  Future<Uint8List> runSudoCommand(
    String command, {
    required String password,
  }) async {
    final client = _client;

    if (client == null || !_connected) {
      throw Exception('No active SSH connection.');
    }

    const authMarker = '__REMOTE_CONTROL_SUDO_OK__';

    final rootCommand =
        "printf '$authMarker\\\n'; "
        "exec sh -c "
        "${_shellQuote(command)}";

    final sudoCommand =
        "sudo -S -p '' -- "
        "sh -c "
        "${_shellQuote(rootCommand)}";

    try {
      final session = await client.execute(sudoCommand);

      final stdoutFuture = _collectStream(session.stdout);

      final stderrFuture = _collectStream(session.stderr);

      session.stdin.add(Uint8List.fromList(utf8.encode('$password\n')));

      await session.stdin.close();

      await session.done;

      final stdoutBytes = await stdoutFuture;

      final stderrBytes = await stderrFuture;

      final stdoutText = utf8.decode(stdoutBytes, allowMalformed: true);

      final stderrText = utf8.decode(stderrBytes, allowMalformed: true);

      if (!stdoutText.contains(authMarker)) {
        final message = stderrText.trim();

        throw SudoAuthenticationException(
          message.isEmpty ? 'sudo authentication failed.' : message,
        );
      }

      var cleanedOutput = stdoutText.replaceFirst('$authMarker\r\n', '');

      cleanedOutput = cleanedOutput.replaceFirst('$authMarker\n', '');

      final combined = StringBuffer();

      if (cleanedOutput.isNotEmpty) {
        combined.write(cleanedOutput);
      }

      if (stderrText.isNotEmpty) {
        if (combined.isNotEmpty && !combined.toString().endsWith('\n')) {
          combined.write('\n');
        }

        combined.write(stderrText);
      }

      return Uint8List.fromList(utf8.encode(combined.toString()));
    } on SudoAuthenticationException {
      rethrow;
    } catch (_) {
      final alive = await healthCheck();

      if (!alive) {
        _markDisconnected();
      }

      rethrow;
    }
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  Future<Uint8List> _collectStream(Stream<Uint8List> stream) async {
    final builder = BytesBuilder(copy: false);

    await for (final chunk in stream) {
      builder.add(chunk);
    }

    return builder.takeBytes();
  }

  Future<Uint8List> runCommand(
    String command, {
    String executionMode = 'standard',
    Duration? timeout,
  }) async {
    if (executionMode == 'interactive') {
      return runPowerShell(
        command,
        desktop: true,
        timeout: timeout ?? const Duration(seconds: 60),
      );
    }

    final body = RegExp(
      r'^\s*powershell\.exe\s+(?:(?:-NoProfile|-NonInteractive|-NoLogo)\s+)*-Command\s+"([^"]*)"\s*$',
      caseSensitive: false,
    ).firstMatch(command)?.group(1);
    if (body != null) {
      return runPowerShell(
        body,
        timeout: timeout ?? const Duration(seconds: 60),
      );
    }
    return run(command, timeout: timeout);
  }

  //
  // Opens a real interactive shell using the
  // already authenticated SSHClient.
  //
  Future<SSHSession> openShell({String? command}) async {
    final client = _client;

    if (client == null || !_connected) {
      throw Exception('No active SSH connection.');
    }

    try {
      const pty = SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24);
      return command == null
          ? await client.shell(pty: pty)
          : await client.execute(command, pty: pty);
    } catch (_) {
      await healthCheck();

      rethrow;
    }
  }

  Future<Uint8List> _runInteractiveWindowsCommand(
    String command, {
    Duration? timeout,
  }) async {
    if (timeout == null) {
      return _executeInteractiveWindowsCommand(command);
    }
    final channels = <SSHSession>[];
    var expired = false;
    final operation = _executeInteractiveWindowsCommand(
      command,
      desktopTimeoutSeconds: timeout.inSeconds > 5 ? timeout.inSeconds - 5 : 1,
      onSession: (channel) {
        if (expired) {
          channel.close();
        } else {
          channels.add(channel);
        }
      },
    );
    try {
      return await operation.timeout(
        timeout,
        onTimeout: () {
          expired = true;
          throw TimeoutException(
            'Interactive desktop status timed out. Check that the SSH user is '
            'signed into the Windows desktop, then use Test status.',
            timeout,
          );
        },
      );
    } finally {
      for (final channel in channels) {
        channel.close();
      }
    }
  }

  Future<Uint8List> _executeInteractiveWindowsCommand(
    String command, {
    int desktopTimeoutSeconds = 60,
    void Function(SSHSession)? onSession,
  }) async {
    final client = _client;

    if (client == null || !_connected) {
      throw Exception('No active SSH connection.');
    }

    final token = DateTime.now().microsecondsSinceEpoch.toString();

    final outputFileName = 'RemoteControl_$token.out';

    final doneFileName = 'RemoteControl_$token.done';

    final desktopLauncherFileName = 'RemoteControl_$token.js';

    final beginMarker = '__REMOTE_CONTROL_OUTPUT_BEGIN_${token}__';

    final endMarker = '__REMOTE_CONTROL_OUTPUT_END_${token}__';

    final okMarker = '__REMOTE_CONTROL_OK_${token}__';

    //
    // Runs inside the logged-in Windows desktop
    // session and captures stdout + stderr.
    //
    final targetScript =
        '''
param([string]\$root)
\$ProgressPreference = 'SilentlyContinue'
\$ErrorActionPreference = 'Continue'

\$outputPath = Join-Path \$root '$outputFileName'
\$donePath = Join-Path \$root '$doneFileName'

try {
    \$captured = & {
$command
    } 2>&1 | Out-String -Width 4096

    [System.IO.File]::WriteAllText(
        \$outputPath,
        \$captured,
        [System.Text.UTF8Encoding]::new(\$false)
    )
}
catch {
    \$errorText = \$_ | Out-String -Width 4096

    [System.IO.File]::WriteAllText(
        \$outputPath,
        \$errorText,
        [System.Text.UTF8Encoding]::new(\$false)
    )
}
finally {
    [System.IO.File]::WriteAllText(
        \$donePath,
        'done',
        [System.Text.UTF8Encoding]::new(\$false)
    )
}
''';

    final targetBase64 = base64Encode(utf8.encode(targetScript));
    final desktopTargetFileName = 'RemoteControl_$token.ps1';

    //
    // Runs through SSH. It creates a temporary
    // Scheduled Task with Interactive logon,
    // waits for completion, then prints the
    // captured output between unique markers.
    //
    final launcher =
        '''
\$ProgressPreference = 'SilentlyContinue'
\$ErrorActionPreference = 'Stop'

\$staleBefore = (Get-Date).AddHours(-24)
Get-ChildItem -LiteralPath \$env:TEMP -Directory -Filter 'NodeCockpit_*' -ErrorAction SilentlyContinue | ForEach-Object {
    if (\$_.Name -notmatch '^NodeCockpit_(?:(?:Desktop|Screenshot)_)?[a-fA-F0-9]{32}\$' -or \$_.LastWriteTime -ge \$staleBefore) { return }
    \$oldTask = Get-ScheduledTask -TaskName \$_.Name -ErrorAction SilentlyContinue
    if (\$oldTask -and \$oldTask.State -eq 'Running') { return }
    if (\$oldTask) { Unregister-ScheduledTask -TaskName \$_.Name -Confirm:\$false -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath \$_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -LiteralPath \$env:TEMP -File -ErrorAction SilentlyContinue | Where-Object {
    \$_.Name -match '^RemoteControl_[0-9]{16,}\\.(out|done|js|ps1)\$' -and \$_.LastWriteTime -lt \$staleBefore
} | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    \$_.TaskName -match '^RemoteControl_[0-9]{16,}\$' -and \$_.State -ne 'Running'
} | ForEach-Object {
    \$info = Get-ScheduledTaskInfo -TaskName \$_.TaskName -ErrorAction SilentlyContinue
    if (\$info -and \$info.LastRunTime -lt \$staleBefore) {
        Unregister-ScheduledTask -TaskName \$_.TaskName -Confirm:\$false -ErrorAction SilentlyContinue
    }
}
\$root = Join-Path \$env:TEMP ('NodeCockpit_' + [Guid]::NewGuid().ToString('N'))
\$taskName = Split-Path \$root -Leaf
\$acl = [Security.AccessControl.DirectorySecurity]::new()
\$acl.SetAccessRuleProtection(\$true, \$false)
\$inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
\$identities = @([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
foreach (\$sid in \$identities) {
    \$rule = [Security.AccessControl.FileSystemAccessRule]::new(\$sid, [Security.AccessControl.FileSystemRights]::FullControl, \$inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    [void]\$acl.AddAccessRule(\$rule)
}
[void][IO.Directory]::CreateDirectory(\$root, \$acl)
\$outputPath = Join-Path \$root '$outputFileName'
\$donePath = Join-Path \$root '$doneFileName'

try {
    Remove-Item `
        \$outputPath `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        \$donePath `
        -Force `
        -ErrorAction SilentlyContinue

    \$currentUser =
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    \$principal =
        New-ScheduledTaskPrincipal `
            -UserId \$currentUser `
            -LogonType Interactive `
            -RunLevel Limited

    # wscript is windowless. It starts PowerShell hidden before its console
    # can appear, while keeping the process in the interactive desktop.
    \$desktopLauncherPath = Join-Path \$root '$desktopLauncherFileName'
    \$desktopTargetPath = Join-Path \$root '$desktopTargetFileName'
    [System.IO.File]::WriteAllText(\$desktopTargetPath, [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$targetBase64')), [System.Text.UTF8Encoding]::new(\$true))
    \$desktopLauncher = @"
var shell = new ActiveXObject("WScript.Shell");
var root = shell.ExpandEnvironmentStrings('%TEMP%') + '\\\\__NC_TASK__';
var path = root + '\\\\$desktopTargetFileName';
var code = shell.Run('powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + path + '" -root "' + root + '"', 0, true);
WScript.Quit(code);
"@
    \$desktopLauncher = \$desktopLauncher.Replace('__NC_TASK__', \$taskName)
    [System.IO.File]::WriteAllText(
        \$desktopLauncherPath,
        \$desktopLauncher,
        [System.Text.UTF8Encoding]::new(\$false)
    )

    \$action =
        New-ScheduledTaskAction `
            -Execute (Join-Path \$env:SystemRoot 'System32\\wscript.exe') `
            -Argument ('//B //NoLogo "' + \$desktopLauncherPath + '"')
    \$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask `
        -TaskName \$taskName `
        -Action \$action `
        -Principal \$principal `
        -Settings \$settings `
        -Force |
        Out-Null

    Start-ScheduledTask `
        -TaskName \$taskName

    \$deadline =
        (Get-Date).AddSeconds($desktopTimeoutSeconds)

    while (
        -not (Test-Path \$donePath) -and
        (Get-Date) -lt \$deadline
    ) {
        Start-Sleep `
            -Milliseconds 100
    }

    if (-not (Test-Path \$donePath)) {
        throw 'Interactive command timed out.'
    }

    \$captured = ''

    if (Test-Path \$outputPath) {
        \$captured =
            [System.IO.File]::ReadAllText(
                \$outputPath
            )
        Remove-Item -LiteralPath \$outputPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath \$donePath -Force -ErrorAction SilentlyContinue

    [Console]::Out.WriteLine(
        '$beginMarker'
    )

    if (
        -not [string]::IsNullOrEmpty(
            \$captured
        )
    ) {
        [Console]::Out.Write(
            \$captured
        )

        if (
            -not \$captured.EndsWith(
                "`n"
            )
        ) {
            [Console]::Out.WriteLine()
        }
    }

    [Console]::Out.WriteLine(
        '$endMarker'
    )

    [Console]::Out.WriteLine(
        '$okMarker'
    )
}
finally {
    Stop-ScheduledTask `
        -TaskName \$taskName `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName \$taskName `
        -Confirm:\$false `
        -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath \$root -Recurse -Force -ErrorAction SilentlyContinue
}
''';

    // Stream the launcher and execute it in this same PowerShell process.
    // This avoids a second SSH exec and two extra PowerShell startups.
    const bootstrap =
        r"$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='Stop'; $s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))))";
    final encoded = _encodePowerShellCommand(bootstrap);
    try {
      final session = await client.execute(
        'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded',
      );
      onSession?.call(session);
      final stdoutFuture = _collectStream(session.stdout);
      final stderrFuture = _collectStream(session.stderr);
      session.stdin.add(
        Uint8List.fromList(
          utf8.encode([base64Encode(utf8.encode(launcher)), '\n'].join()),
        ),
      );
      await session.stdin.close();
      await session.done;
      final stdoutText = utf8.decode(await stdoutFuture, allowMalformed: true);

      final stderrText = utf8.decode(await stderrFuture, allowMalformed: true);

      if (!stdoutText.contains(okMarker)) {
        final details = StringBuffer();

        if (stdoutText.trim().isNotEmpty) {
          details.writeln('stdout:');

          details.writeln(stdoutText.trim());
        }

        if (stderrText.trim().isNotEmpty) {
          if (details.isNotEmpty) {
            details.writeln();
          }

          details.writeln('stderr:');

          details.writeln(stderrText.trim());
        }

        throw Exception(
          details.isEmpty
              ? 'Interactive command could not '
                    'be completed.'
              : 'Interactive command failed.\n\n'
                    '${details.toString().trim()}',
        );
      }

      final beginIndex = stdoutText.indexOf(beginMarker);

      final endIndex = stdoutText.indexOf(
        endMarker,
        beginIndex < 0 ? 0 : beginIndex + beginMarker.length,
      );

      if (beginIndex < 0 || endIndex < 0 || endIndex < beginIndex) {
        throw Exception(
          'Interactive command output '
          'could not be read.',
        );
      }

      var commandOutput = stdoutText.substring(
        beginIndex + beginMarker.length,
        endIndex,
      );

      if (commandOutput.startsWith('\r\n')) {
        commandOutput = commandOutput.substring(2);
      } else if (commandOutput.startsWith('\n')) {
        commandOutput = commandOutput.substring(1);
      }

      if (commandOutput.endsWith('\r\n')) {
        commandOutput = commandOutput.substring(0, commandOutput.length - 2);
      } else if (commandOutput.endsWith('\n')) {
        commandOutput = commandOutput.substring(0, commandOutput.length - 1);
      }

      return Uint8List.fromList(utf8.encode(commandOutput));
    } catch (_) {
      final alive = await healthCheck();

      if (!alive) {
        _markDisconnected();
      }

      rethrow;
    }
  }

  String _encodePowerShellCommand(String command) {
    final bytes = <int>[];

    for (final codeUnit in command.codeUnits) {
      bytes.add(codeUnit & 0xff);

      bytes.add((codeUnit >> 8) & 0xff);
    }

    return base64Encode(bytes);
  }

  //
  // EXPLICIT USER DISCONNECT
  //
  // This is intentionally different from an
  // unexpected network failure.
  //
  // Explicit disconnect means:
  //
  // - SSH transport closes
  // - reconnect target is cleared
  // - sudo cache is cleared
  // - persistent terminal is DESTROYED
  // - scrollback is discarded
  //
  // Therefore reconnecting later starts with
  // a completely fresh terminal.
  //
  void disconnect() {
    _closeCurrentConnection(clearLastDevice: true, destroyTerminal: true);

    if (manageBackgroundKeepAlive) {
      unawaited(backgroundKeepAlive.stop());
    }
  }

  void _closeCurrentConnection({
    required bool clearLastDevice,
    required bool destroyTerminal,
  }) {
    _desktopHost?.close();
    _standardHost?.close();
    _desktopHost = null;
    _standardHost = null;
    _stopHealthMonitor();

    final client = _client;

    final socket = _socket;

    final currentDeviceId = _deviceId;

    final wasConnected = _connected;

    if (currentDeviceId != null) {
      sudoCredentials.clearDevice(currentDeviceId);
    }

    //
    // Deal with the terminal BEFORE throwing
    // away the SSH transport references.
    //
    if (destroyTerminal) {
      //
      // Explicit disconnect.
      //
      // Remove it from this SshSession
      // immediately so reopening after a
      // reconnect cannot obtain the old buffer.
      //
      _destroyTerminal();
    } else {
      //
      // Transport replacement/loss.
      //
      // Preserve xterm history, but mark its
      // remote shell unusable.
      //
      final terminal = _persistentTerminal;

      if (terminal != null && !terminal.isClosed) {
        unawaited(terminal.transportDisconnected());
      }
    }

    _client = null;

    _socket = null;

    _deviceId = null;

    if (clearLastDevice) {
      _lastDeviceId = null;
    }

    _connected = false;

    _checking = false;

    try {
      client?.close();
    } catch (_) {}

    try {
      socket?.close();
    } catch (_) {}

    if (wasConnected) {
      notifyListeners();
    }
  }

  //
  // Unexpected SSH/network loss.
  //
  // Here we deliberately preserve:
  //
  // - lastDeviceId
  // - terminal buffer
  //
  // so automatic reconnect remains possible
  // and useful history is not thrown away.
  //
  void _markDisconnected() {
    _desktopHost?.close();
    _standardHost?.close();
    _desktopHost = null;
    _standardHost = null;
    if (!_connected && _client == null && _socket == null) {
      return;
    }

    _stopHealthMonitor();

    final client = _client;

    final socket = _socket;

    final currentDeviceId = _deviceId;

    if (currentDeviceId != null) {
      sudoCredentials.clearDevice(currentDeviceId);
    }

    final terminal = _persistentTerminal;

    if (terminal != null && !terminal.isClosed) {
      unawaited(terminal.transportDisconnected());
    }

    _client = null;

    _socket = null;

    _deviceId = null;

    //
    // Deliberately preserve
    // _lastDeviceId.
    //
    _connected = false;

    _checking = false;

    try {
      client?.close();
    } catch (_) {}

    try {
      socket?.close();
    } catch (_) {}

    notifyListeners();
  }

  //
  // Completely destroys this device's
  // persistent terminal.
  //
  // The SSH transport itself is unaffected.
  //
  void _destroyTerminal() {
    final terminal = _persistentTerminal;

    if (terminal == null) {
      return;
    }

    //
    // Detach synchronously first.
    //
    // This guarantees terminalFor() cannot
    // return the old terminal after this point.
    //
    _persistentTerminal = null;

    unawaited(terminal.dispose());
  }

  //
  // Public primitive for manually closing the
  // terminal without disconnecting SSH.
  //
  Future<void> closeTerminal() async {
    final terminal = _persistentTerminal;

    if (terminal == null) {
      return;
    }

    _persistentTerminal = null;

    await terminal.dispose();

    notifyListeners();
  }

  @override
  void dispose() {
    _stopHealthMonitor();

    final client = _client;

    final socket = _socket;

    final currentDeviceId = _deviceId;

    if (currentDeviceId != null) {
      sudoCredentials.clearDevice(currentDeviceId);
    }

    if (manageBackgroundKeepAlive) {
      sudoCredentials.clearAll();
    }

    //
    // A disposed SshSession owns no surviving
    // terminal.
    //
    _destroyTerminal();

    _client = null;

    _socket = null;

    _deviceId = null;

    _lastDeviceId = null;

    _connected = false;

    _checking = false;

    try {
      client?.close();
    } catch (_) {}

    try {
      socket?.close();
    } catch (_) {}

    if (manageBackgroundKeepAlive) {
      unawaited(backgroundKeepAlive.stop());
    }

    super.dispose();
  }
}
