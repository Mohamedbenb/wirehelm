import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

bool requiresFreshWindowsProcess(String script) {
  if (!RegExp(r'Add-Type\b', caseSensitive: false).hasMatch(script)) {
    return false;
  }
  if (RegExp(
    r'\bnamespace\s+|Add-Type\s+-(?:MemberDefinition|Path)|-(?:ReferencedAssemblies|OutputAssembly|OutputType|PassThru|IgnoreWarnings|Language)\b',
    caseSensitive: false,
  ).hasMatch(script)) {
    return true;
  }
  final remaining = script.replaceAll(
    RegExp(
      r"Add-Type\s+-TypeDefinition\s+('(?:[^']|'')*'|@'\r?\n[\s\S]*?\r?\n'@)",
      caseSensitive: false,
    ),
    '',
  );
  return RegExp(
    r'Add-Type\s+-TypeDefinition\b',
    caseSensitive: false,
  ).hasMatch(remaining);
}

const windowsTempArtifactCleanup = r'''
$ErrorActionPreference='SilentlyContinue'
$staleBefore=(Get-Date).AddHours(-24)
Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'NodeCockpit_*' | ForEach-Object {
 $candidate=$_
 if ($candidate.Name -notmatch '^NodeCockpit_(?:(?:Desktop|Screenshot)_)?[a-fA-F0-9]{32}$' -or $candidate.LastWriteTime -ge $staleBefore) { return }
 try {
  $oldTask=Get-ScheduledTask -TaskName $candidate.Name -ErrorAction Stop
  if ($oldTask.State -eq 'Running') { return }
  Unregister-ScheduledTask -TaskName $candidate.Name -Confirm:$false -ErrorAction SilentlyContinue
 } catch { }
 try { Remove-Item -LiteralPath $candidate.FullName -Recurse -Force -ErrorAction Stop } catch { }
}
try {
 Get-ChildItem -LiteralPath $env:TEMP -File | Where-Object {
  $_.Name -match '^RemoteControl_[0-9]{16,}\.(out|done|js|ps1)$' -and $_.LastWriteTime -lt $staleBefore
 } | Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }
try {
 Get-ScheduledTask | Where-Object {
  $_.TaskName -match '^RemoteControl_[0-9]{16,}$' -and $_.State -ne 'Running'
 } | ForEach-Object {
  try {
   $info=Get-ScheduledTaskInfo -TaskName $_.TaskName -ErrorAction Stop
   if ($info -and $info.LastRunTime -lt $staleBefore) { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue }
  } catch { }
 }
} catch { }
''';

// Older saved templates put a literal C# definition in $src before Add-Type.
// Inline only a proven single-quoted literal; genuinely dynamic code stays fresh.
String normalizeWindowsTypes(String script) {
  final assignments = RegExp(r"\$(\w+)\s*=\s*('(?:[^']|'')*')\s*;")
      .allMatches(script);
  for (final assignment in assignments) {
    final name = assignment.group(1)!;
    final literal = assignment.group(2)!;
    if (!RegExp(r'\bclass\s+(?:DTopo|ScreenPower)\b').hasMatch(literal)) {
      continue;
    }
    if (RegExp(r'\$' + RegExp.escape(name) + r'\s*=')
            .allMatches(script)
            .length !=
        1) {
      continue;
    }
    script = script.replaceAllMapped(
      RegExp(
        r'Add-Type\s+-TypeDefinition\s+\$' + RegExp.escape(name) + r'\b',
        caseSensitive: false,
      ),
      (_) => 'Add-Type -TypeDefinition $literal',
    );
  }
  return script;
}

String cacheWindowsTypes(String script) {
  // Autoloading inside an invoked ScriptBlock is scoped to that invocation.
  // Keep NetAdapter in the process scope so each probe/action reuses it.
  final adapter = RegExp(
    r'\b(?:Get|Enable|Disable)-NetAdapter\b',
    caseSensitive: false,
  ).hasMatch(script);
  return (adapter
          ? r"if (-not $global:NCNetAdapterLoaded) { Import-Module NetAdapter -Global -ErrorAction Stop; $global:NCNetAdapterLoaded=$true }; "
          : '') +
      _cacheTypes(script);
}

String _cacheTypes(String script) => script.replaceAllMapped(
  RegExp(
    r"Add-Type\s+-TypeDefinition\s+('(?:[^']|'')*'|@'\r?\n[\s\S]*?\r?\n'@)",
    caseSensitive: false,
  ),
  (match) {
    final definition = match.group(1)!;
    if (RegExp(r'\bnamespace\s+').hasMatch(definition)) return match.group(0)!;
    final classes = RegExp(r'\bclass\s+(\w+)')
        .allMatches(definition)
        .map((m) => m.group(1)!)
        .toList();
    if (classes.isEmpty) return match.group(0)!;
    final key = base64Encode(utf8.encode(definition));
    final missing = classes.map((c) => "-not ('$c' -as [type])").join(' -or ');
    final name = classes.join('_');
    return "if (-not \$global:NCTypeDefs) { \$global:NCTypeDefs=@{} }; "
        "if (\$global:NCTypeDefs.ContainsKey('$name') -and \$global:NCTypeDefs['$name'] -ne '$key') { throw 'Type definition changed; retry after helper restart.' }; "
        "if ($missing) { ${match.group(0)} }; \$global:NCTypeDefs['$name']='$key'";
  },
);

const commandHostWorker = r'''
param([string]$root)
$ErrorActionPreference='Stop'
$last=Get-Date
while ((Get-Date) -lt $last.AddSeconds(360)) {
 $request=Join-Path $root 'request.json'
 if (-not (Test-Path $request)) { Start-Sleep -Milliseconds 25; continue }
 $job=Get-Content -LiteralPath $request -Raw | ConvertFrom-Json
 Remove-Item -LiteralPath $request -Force
 $last=Get-Date
 try {
  $text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($job.script))
  $ncExecClock=[Diagnostics.Stopwatch]::StartNew()
  # Invoke in a child scope so ordinary variables/functions from one request
  # do not become ambient state for the next request. Deliberate $global: writes
  # and process-wide changes (for example Add-Type) remain process-wide.
  $value=(& ([ScriptBlock]::Create($text)) | Out-String -Width 4096)
  $reply=@{id=$job.id;value=$value;executionMs=$ncExecClock.ElapsedMilliseconds}
 } catch { $reply=@{id=$job.id;error=$_.Exception.Message;executionMs=$ncExecClock.ElapsedMilliseconds} }
 $tmp=Join-Path $root 'response.tmp'
 [IO.File]::WriteAllText($tmp,($reply | ConvertTo-Json -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
 Move-Item -LiteralPath $tmp -Destination (Join-Path $root 'response.json') -Force
}
''';

String commandHostBroker(bool desktop, {int port = 0, String? secret}) {
  if (port < 0 || port > 65535) throw ArgumentError.value(port, 'port');
  if (secret != null && !RegExp(r'^[a-f0-9]{32}$').hasMatch(secret)) {
    throw ArgumentError('Invalid helper token.');
  }
  final worker = commandHostWorker;
  final listenerSetup =
      ' \$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$port)\n';
  return r'''
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=Join-Path $env:TEMP ('NodeCockpit_'+[Guid]::NewGuid().ToString('N'))
$task=Split-Path $root -Leaf
try {
''' +
      (desktop
          ? '''
 # Protect transient scripts and output for this account, SYSTEM and admins.
 [void](New-Item -ItemType Directory -Path \$root)
 \$userSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 icacls.exe \$root /inheritance:r /grant:r "*\${userSid}:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
 if (\$LASTEXITCODE -ne 0) { throw 'Could not secure helper temp folder.' }
 \$ps=Join-Path \$root 'worker.ps1'
 [IO.File]::WriteAllText(\$ps,@'
$worker
'@,[Text.UTF8Encoding]::new(\$true))
 \$js=Join-Path \$root 'start.js'
 \$command='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+\$ps+'" -root "'+\$root+'"'
 \$commandJson=ConvertTo-Json -InputObject \$command -Compress
 \$launch='var s=new ActiveXObject("WScript.Shell"); s.Run('+\$commandJson+',0,true);'
 [IO.File]::WriteAllText(\$js,\$launch)
 \$p=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
 \$a=New-ScheduledTaskAction -Execute (Join-Path \$env:SystemRoot 'System32\\wscript.exe') -Argument ('//B //NoLogo "'+\$js+'"')
 \$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
 Register-ScheduledTask -TaskName \$task -Action \$a -Principal \$p -Settings \$settings -Force | Out-Null
 Start-ScheduledTask -TaskName \$task
'''
          : '') +
      (secret == null
          ? " \$secret=[Guid]::NewGuid().ToString('N')\n"
          : " \$secret='$secret'\n") +
      listenerSetup +
      r'''
 $listener.Start()
 [Console]::Out.WriteLine('__NC_READY__'+$listener.LocalEndpoint.Port+':'+$secret)
 $accept=$listener.BeginAcceptTcpClient($null,$null)
 if (-not $accept.AsyncWaitHandle.WaitOne(15000)) { throw 'Helper connection timed out.' }
 $connection=$listener.EndAcceptTcpClient($accept)
 $reader=[IO.StreamReader]::new($connection.GetStream(),[Text.Encoding]::UTF8)
 $writer=[IO.StreamWriter]::new($connection.GetStream(),[Text.UTF8Encoding]::new($false))
 $writer.AutoFlush=$true
 while ($null -ne ($line=$reader.ReadLine())) {
  $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line))
  $job=$json | ConvertFrom-Json
  if ($job.token -ne $secret) { throw 'Invalid helper authentication.' }
  if ($job.op -eq 'hello') {
   $writer.WriteLine('__NC_HELLO__'+$secret)
   continue
  }
''' +
      (desktop
          ? r'''
  $tmp=Join-Path $root 'request.tmp'
  [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination (Join-Path $root 'request.json') -Force
  $response=Join-Path $root 'response.json'
  $deadline=(Get-Date).AddSeconds(60)
  while (-not (Test-Path $response)) {
   if ((Get-Date) -gt $deadline) { throw 'Desktop helper timed out.' }
   Start-Sleep -Milliseconds 25
  }
  $reply=[IO.File]::ReadAllText($response)
  Remove-Item -LiteralPath $response -Force
'''
          : r'''
  try {
   $text=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($job.script))
   $ncExecClock=[Diagnostics.Stopwatch]::StartNew()
   # Match desktop worker scope behavior for ordinary session state.
   $value=(& ([ScriptBlock]::Create($text)) | Out-String -Width 4096)
   $reply=@{id=$job.id;value=$value;executionMs=$ncExecClock.ElapsedMilliseconds} | ConvertTo-Json -Compress -Depth 5
  } catch { $reply=@{id=$job.id;error=$_.Exception.Message;executionMs=$ncExecClock.ElapsedMilliseconds} | ConvertTo-Json -Compress }
''') +
      r'''
  $writer.WriteLine('__NC_REPLY__'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($reply)))
 }
} finally {
 if ($connection) { $connection.Close() }
 if ($listener) { $listener.Stop() }
 if (Test-Path $root) {
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
 }
}
''';
}

class WindowsCommandHost {
  final SSHClient client;
  final bool desktop;
  final void Function(String, Map<String, int>)? onTiming;
  WindowsCommandHost(this.client, {required this.desktop, this.onTiming});
  int? _executionMs;
  SSHSession? _channel;
  StreamSubscription<String>? _output;
  StreamSubscription<String>? _errors;
  String _startupError = '';
  Completer<void>? _ready;
  Completer<void>? _listening;
  Completer<Uint8List>? _reply;
  Future<void> _tail = Future<void>.value();
  Timer? _idle;
  int _id = 0;
  DateTime? _startedAt;
  bool _tempArtifactsCleaned = false;
  int _generation = 0;
  int? _port;
  String? _secret;
  SSHSocket? _socket;
  StreamSubscription<String>? _data;

  Future<void> _start() async {
    if (_channel != null) return;
    _tempArtifactsCleaned = false;
    final generation = _generation;
    _ready = Completer<void>();
    _ready!.future.ignore();
    _listening = Completer<void>();
    _listening!.future.ignore();
    _startupError = '';
    final random = Random.secure();
    _port = 49152 + random.nextInt(16384);
    _secret = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final startupClock = Stopwatch()..start();
    // The standard broker fits beneath Windows cmd.exe's 8191-character limit.
    // Launch it directly so a long-lived SSH process does not depend on the
    // redirected Console.In bootstrap completing. Compress the larger desktop
    // setup so it also fits without redirected startup input.
    final script = commandHostBroker(desktop, port: _port!, secret: _secret!);
    final compressed = base64Encode(gzip.encode(utf8.encode(script)));
    final source = desktop
        ? "\$z=[IO.Compression.GZipStream]::new([IO.MemoryStream]::new([Convert]::FromBase64String('$compressed')),[IO.Compression.CompressionMode]::Decompress); \$r=[IO.StreamReader]::new(\$z,[Text.Encoding]::UTF8); try { & ([ScriptBlock]::Create(\$r.ReadToEnd())) } finally { \$r.Dispose() }"
        : script;
    final encoded = base64Encode(
      source.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
    );
    final command =
        'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded';
    // Leave room for the short cmd.exe /c wrapper added by Windows OpenSSH
    // while remaining below its 8191-character command-line limit.
    if (command.length > 8150) {
      throw StateError(
        'Windows helper launch exceeds the shell command limit (${command.length} characters).',
      );
    }
    var launchExpired = false;
    final channel = await client
        .execute(command)
        .then((value) {
          if (launchExpired || generation != _generation) {
            value.channel.destroy();
            unawaited(value.stdin.close());
            throw StateError('Windows helper launch was cancelled.');
          }
          return value;
        })
        .timeout(
          Duration(
            milliseconds: max(1, 15000 - startupClock.elapsedMilliseconds),
          ),
          onTimeout: () {
            launchExpired = true;
            throw TimeoutException('Windows helper launch timed out.');
          },
        );
    _channel = channel;
    _startedAt = DateTime.now();
    _output = channel.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (identical(_channel, channel) &&
                line == '__NC_READY__$_port:$_secret' &&
                !_listening!.isCompleted) {
              _listening!.complete();
            }
          },
          onError: (Object e) {
            if (identical(_channel, channel)) _abort(e);
          },
          onDone: () {
            if (identical(_channel, channel)) {
              _abort(
                StateError(
                  _startupError.isEmpty
                      ? 'Windows helper closed (exit ${channel.exitCode ?? 'unknown'}).'
                      : 'Windows helper closed: $_startupError',
                ),
              );
            }
          },
        );
    // Keep a bounded startup diagnostic instead of silently discarding stderr.
    _errors = channel.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (text) {
            if (!identical(_channel, channel)) return;
            _startupError = '$_startupError$text'.replaceAll(
              _secret!,
              '[redacted]',
            );
            if (_startupError.length > 2048) {
              _startupError = _startupError.substring(
                _startupError.length - 2048,
              );
            }
          },
          onError: (Object e) {
            if (identical(_channel, channel)) _abort(e);
          },
        );
    // Keep the exec input pipe alive for the helper's lifetime. Closing it
    // while the process is waiting on its socket can block Windows OpenSSH
    // from servicing the other channels on the connection.
    // Prefer explicit listener readiness. The known port still permits startup
    // when an SSH server buffers console output. Do not abandon a pending
    // channel-open after two seconds: Windows can confirm it just afterward.
    await _listening!.future.timeout(
      Duration(
        milliseconds: max(
          1,
          min(2000, 15000 - startupClock.elapsedMilliseconds),
        ),
      ),
      onTimeout: () {},
    );
    if (generation != _generation) throw StateError('Windows helper stopped.');
    // Confirm readiness on the forwarded connection, independently of stdout.
    // No user command is sent until this fresh helper authenticates its hello.
    SSHSocket? connected;
    Object? connectionError;
    while (startupClock.elapsedMilliseconds < 15000) {
      if (_ready!.isCompleted) await _ready!.future;
      var expired = false;
      try {
        connected = await client
            .forwardLocal(
              '127.0.0.1',
              _port!,
              localHost: '127.0.0.1',
              localPort: 1,
            )
            .then((value) {
              if (expired || generation != _generation) {
                value.destroy();
                throw StateError('Late helper connection.');
              }
              return value;
            })
            .timeout(
              Duration(
                milliseconds: max(1, 15000 - startupClock.elapsedMilliseconds),
              ),
              onTimeout: () {
                expired = true;
                throw TimeoutException('Helper connection did not respond.');
              },
            );
        break;
      } catch (error) {
        connectionError = error;
        if (!identical(_channel, channel) || client.isClosed) rethrow;
        if (error is SSHChannelOpenError && error.code != 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final socket = connected;
    if (socket == null) {
      throw StateError(
        _startupError.isEmpty
            ? 'Windows helper port $_port could not open its SSH tunnel: $connectionError'
            : 'Windows helper startup failed: $_startupError',
      );
    }
    _socket = socket;
    _data = socket.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (!identical(_socket, socket)) return;
            try {
              if (!_ready!.isCompleted) {
                if (line != '__NC_HELLO__$_secret') {
                  throw StateError('Windows helper authentication failed.');
                }
                _ready!.complete();
                return;
              }
              if (_reply == null || _reply!.isCompleted) return;
              if (!line.startsWith('__NC_REPLY__')) {
                throw StateError('Invalid helper frame.');
              }
              final row = jsonDecode(
                utf8.decode(base64Decode(line.substring(12))),
              ) as Map;
              if (row['id'] != _id) {
                throw StateError('Unexpected helper response.');
              }
              _executionMs = (row['executionMs'] as num?)?.toInt();
              if (row['error'] != null) {
                _reply!.completeError(StateError(row['error'] as String));
              } else {
                _reply!.complete(
                  Uint8List.fromList(utf8.encode(row['value'] as String)),
                );
              }
            } catch (e) {
              _abort(e);
            }
          },
          onError: (Object e) {
            if (identical(_socket, socket)) _abort(e);
          },
          onDone: () {
            if (identical(_socket, socket)) {
              _abort(StateError('Helper connection closed.'));
            }
          },
        );
    socket.sink.add(
      Uint8List.fromList(
        utf8.encode(
          '${base64Encode(utf8.encode(jsonEncode({'op': 'hello', 'token': _secret})))}\r\n',
        ),
      ),
    );
    await _ready!.future.timeout(
      Duration(milliseconds: max(1, 15000 - startupClock.elapsedMilliseconds)),
    );
  }

  Future<Uint8List> run(
    String script,
    Duration timeout, {
    String label = 'Command',
  }) {
    final clock = Stopwatch()..start();
    final operation = _tail.then((_) async {
      final queueMs = clock.elapsedMilliseconds;
      var startupMs = 0;
      var submittedMs = -1;
      var failed = false;
      _executionMs = null;
      _idle?.cancel();
      try {
        try {
          await _start();
          startupMs = clock.elapsedMilliseconds - queueMs;
        } catch (e) {
          throw WindowsHostStartException(e);
        }
        _reply = Completer<Uint8List>();
        _reply!.future.ignore();
        _id++;
        submittedMs = clock.elapsedMilliseconds;
        final requestScript = desktop && !_tempArtifactsCleaned
            ? '$windowsTempArtifactCleanup\n$script'
            : script;
        final json = jsonEncode({
          'id': _id,
          'token': _secret,
          'script': base64Encode(utf8.encode(requestScript)),
        });
        _socket!.sink.add(
          Uint8List.fromList(
            utf8.encode('${base64Encode(utf8.encode(json))}\r\n'),
          ),
        );
        final value = await _reply!.future.timeout(timeout);
        if (desktop) _tempArtifactsCleaned = true;
        if (utf8
            .decode(value, allowMalformed: true)
            .contains('Type definition changed; retry after helper restart.')) {
          close();
        }
        return value;
      } catch (_) {
        failed = true;
        close();
        rethrow;
      } finally {
        if (submittedMs < 0) startupMs = clock.elapsedMilliseconds - queueMs;
        {
          onTiming?.call(label, {
            'queue': queueMs,
            'startup': startupMs,
            'execution': _executionMs ?? -1,
            'response':
                (submittedMs < 0
                        ? 0
                        : clock.elapsedMilliseconds -
                              submittedMs -
                              (_executionMs ?? 0))
                    .clamp(0, 1 << 30),
            'total': clock.elapsedMilliseconds,
            'failed': failed ? 1 : 0,
          });
        }
        if (_id >= 100 ||
            (_startedAt != null &&
                DateTime.now().difference(_startedAt!) >=
                    const Duration(minutes: 30))) {
          // Rotate a warm process periodically to limit accidental state
          // accumulation across a long-lived SSH connection.
          close();
        } else {
          _idle = Timer(const Duration(minutes: 5), close);
        }
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void _fail(Object error) {
    if (_listening != null && !_listening!.isCompleted) {
      _listening!.completeError(error);
    }
    if (_ready != null && !_ready!.isCompleted) _ready!.completeError(error);
    if (_reply != null && !_reply!.isCompleted) _reply!.completeError(error);
  }

  void _abort(Object error) {
    _fail(error);
    close();
  }

  void close() {
    _generation++;
    _idle?.cancel();
    _fail(StateError('Windows helper stopped.'));
    unawaited(_socket?.close() ?? Future<void>.value());
    _socket = null;
    unawaited(_data?.cancel() ?? Future<void>.value());
    _data = null;
    final channel = _channel;
    if (channel != null) {
      unawaited(
        channel.done
            .timeout(const Duration(seconds: 3))
            .then<void>(
              (_) {
                unawaited(channel.stdin.close());
              },
              onError: (Object _) {
                channel.channel.destroy();
                unawaited(channel.stdin.close());
              },
            ),
      );
    }
    _channel = null;
    unawaited(_output?.cancel() ?? Future<void>.value());
    _output = null;
    unawaited(_errors?.cancel() ?? Future<void>.value());
    _errors = null;
  }
}

class WindowsHostStartException implements Exception {
  final Object error;
  WindowsHostStartException(this.error);
  @override
  String toString() => 'Windows helper could not start: $error';
}
