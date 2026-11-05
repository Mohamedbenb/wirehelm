import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'native_terminal.dart';

enum TerminalConnectionState { idle, starting, ready, closed, failed }

// VT replies are protocol traffic, not keystrokes. They must reach ConPTY
// even during startup or while the UI has a Ctrl/Alt modifier selected.
class CockpitTerminal extends Terminal {
  void Function(String)? onProtocolOutput;
  final NativeTerminal? native = nativeTerminalSupported
      ? NativeTerminal()
      : null;
  CockpitTerminal() : super(maxLines: 10000) {
    native?.onOutput = (text, protocol) {
      if (protocol) {
        onProtocolOutput?.call(text);
      } else {
        onOutput?.call(text);
      }
    };
    native?.onResize = (w, h, pw, ph) => onResize?.call(w, h, pw, ph);
  }
  @override
  void write(String data) {
    if (native == null) {
      super.write(data);
    } else {
      native!.send('append', {'text': data});
    }
  }

  @override
  void paste(String text) {
    if (native == null) {
      super.paste(text);
    } else {
      native!.send('paste', {'text': text});
    }
  }

  @override
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) {
    if (native == null) {
      return super.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
    }
    native!.send('key', {'key': key.name, 'ctrl': ctrl, 'alt': alt});
    return true;
  }

  void _reply(void Function() emit) {
    final input = onOutput;
    onOutput = onProtocolOutput;
    try {
      emit();
    } finally {
      onOutput = input;
    }
  }

  @override
  void sendPrimaryDeviceAttributes() =>
      _reply(super.sendPrimaryDeviceAttributes);
  @override
  void sendSecondaryDeviceAttributes() =>
      _reply(super.sendSecondaryDeviceAttributes);
  @override
  void sendTertiaryDeviceAttributes() =>
      _reply(super.sendTertiaryDeviceAttributes);
  @override
  void sendOperatingStatus() => _reply(super.sendOperatingStatus);
  @override
  void sendCursorPosition() => onProtocolOutput?.call(
    '\x1b[${buffer.cursorY + 1};${buffer.cursorX + 1}R',
  );
  @override
  void sendSize() => _reply(super.sendSize);
}

const windowsTerminalBootstrap = r'''
$ProgressPreference='SilentlyContinue'
$utf8=New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding=$utf8
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
try {
 Import-Module PSReadLine -ErrorAction Stop
 Set-PSReadLineOption -EditMode Emacs -BellStyle None
 if ((Get-Command Set-PSReadLineOption).Parameters.ContainsKey('PredictionSource')) { Set-PSReadLineOption -PredictionSource None }
 Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
} catch {}
function global:prompt {
 $e=[char]27
 $p=$executionContext.SessionState.Path.CurrentLocation.Path
 $leaf=Split-Path -Leaf $p
 if ([string]::IsNullOrEmpty($leaf)) { $leaf=$p }
 return "$e[32mPS $leaf>$e[0m "
}
try { [Console]::Clear() } catch {}
Write-Host 'PowerShell ready' -ForegroundColor Cyan
''';

String get windowsTerminalCommand {
  final encoded = base64Encode(
    windowsTerminalBootstrap.codeUnits
        .expand((c) => [c & 255, (c >> 8) & 255])
        .toList(),
  );
  return 'powershell.exe -NoLogo -NoProfile -NoExit -EncodedCommand $encoded';
}

// Decode the stream, rather than individual SSH packets, so Unicode split
// across packets (including emoji and non-Latin paths) remains intact.
Stream<String> terminalOutput(
  Stream<List<int>> bytes, {
  required bool windows,
}) => bytes
    .cast<List<int>>()
    .transform(const Utf8Decoder(allowMalformed: true))
    .map((text) => windows ? text.replaceAll('\r\r\n', '\r\n') : text);

class PersistentTerminal {
  final bool isWindows;
  final Future<SSHSession> Function() openShell;
  final CockpitTerminal terminal = CockpitTerminal();
  final state = ValueNotifier(TerminalConnectionState.idle);
  SSHSession? _shell;
  StreamSubscription<String>? _stdout, _stderr;
  Future<void>? _startFuture;
  Completer<void>? _ready;
  String _bootstrap = '';
  String? error;
  final recentCommands = <String>[];
  bool _disposed = false;
  int _generation = 0;
  List<int>? _size;
  Timer? _resizeTimer;

  PersistentTerminal({required this.isWindows, required this.openShell}) {
    terminal.reflowEnabled = !isWindows;
    terminal.native?.send('compatibility', {'windows': isWindows});
    terminal.onProtocolOutput = (data) {
      if (!_disposed) _shell?.write(Uint8List.fromList(utf8.encode(data)));
    };
  }
  bool get isStarted => state.value == TerminalConnectionState.ready;
  bool get isClosed =>
      _shell == null ||
      state.value == TerminalConnectionState.closed ||
      state.value == TerminalConnectionState.failed;
  SSHSession? get shell => _shell;

  Future<void> start() {
    if (_disposed) {
      return Future.error(StateError('Terminal has been disposed.'));
    }
    if (isStarted) return Future.value();
    if (_startFuture != null) return _startFuture!;
    final future = _start();
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) _startFuture = null;
    });
  }

  Future<void> _start() async {
    final generation = ++_generation;
    state.value = TerminalConnectionState.starting;
    error = null;
    _bootstrap = '';
    var expired = false;
    SSHSession? opened;
    // Attach the timeout/error handler before bytes can complete the marker.
    final ready = isWindows ? Completer<void>() : null;
    _ready = ready;
    final readyFuture = ready?.future.timeout(const Duration(seconds: 15));
    // Opening can fail before we await readiness; consume that error too.
    if (readyFuture != null) unawaited(readyFuture.catchError((Object _) {}));
    try {
      opened = await openShell()
          .then((shell) {
            if (expired || _disposed || generation != _generation) {
              shell.close();
              throw StateError('Shell startup cancelled.');
            }
            return shell;
          })
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              expired = true;
              throw TimeoutException('SSH shell did not open.');
            },
          );
      if (_disposed || generation != _generation) {
        opened.close();
        return;
      }
      final previousOut = _stdout, previousErr = _stderr;
      _stdout = null;
      _stderr = null;
      await previousOut?.cancel();
      await previousErr?.cancel();
      if (_disposed || generation != _generation) {
        opened.close();
        return;
      }
      _shell = opened;
      _stdout = terminalOutput(opened.stdout, windows: isWindows).listen(
        (text) {
          if (generation != _generation || _disposed) return;
          // ConPTY's initial cursor/erase sequences are part of its screen
          // state. Dropping them makes subsequent resize repaints duplicate.
          terminal.write(text);
          if (isWindows && !ready!.isCompleted) {
            _bootstrap += text;
            final index = _bootstrap.indexOf('PowerShell ready');
            if (index >= 0) {
              _bootstrap = '';
              ready.complete();
            } else if (_bootstrap.length > 65536) {
              ready.completeError(
                StateError('PowerShell startup produced excessive output.'),
              );
            }
          }
        },
        onError: (Object e) {
          _shellEnded(generation, '$e');
        },
      );
      _stderr = terminalOutput(opened.stderr, windows: isWindows).listen(
        (text) {
          if (generation == _generation && !_disposed) terminal.write(text);
        },
        onError: (Object e) {
          _shellEnded(generation, '$e');
        },
      );
      unawaited(
        opened.done.then(
          (_) => _shellEnded(generation),
          onError: (Object e) => _shellEnded(generation, '$e'),
        ),
      );
      final size = _size;
      if (size != null) {
        opened.resizeTerminal(size[0], size[1], size[2], size[3]);
      }
      if (readyFuture != null) await readyFuture;
      if (!_disposed && generation == _generation && _shell != null) {
        state.value = TerminalConnectionState.ready;
      }
    } catch (e) {
      if (ready != null && !ready.isCompleted) ready.completeError(e);
      opened?.close();
      if (!_disposed && generation == _generation) {
        _shell = null;
        error = '$e';
        state.value = TerminalConnectionState.failed;
        terminal.write('\r\n[Could not start shell: $e]\r\n');
      }
      rethrow;
    }
  }

  void _shellEnded(int generation, [String? failure]) {
    if (_disposed ||
        generation != _generation ||
        _shell == null ||
        state.value == TerminalConnectionState.closed) {
      return;
    }
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(
        StateError(failure ?? 'PowerShell exited before becoming ready.'),
      );
    }
    final shell = _shell;
    _shell = null;
    shell?.close();
    error = failure;
    state.value = failure == null
        ? TerminalConnectionState.closed
        : TerminalConnectionState.failed;
    terminal.write('\r\n[${failure ?? 'Shell closed'}]\r\n');
  }

  void write(String data) => writeBytes(utf8.encode(data));
  void writeBytes(List<int> data) {
    if (!isStarted || _disposed || data.isEmpty) return;
    _shell?.write(Uint8List.fromList(data));
  }

  void resize({
    required int width,
    required int height,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    if (width < 2 || height < 2) return;
    final next = [width, height, pixelWidth, pixelHeight];
    if (listEquals(next, _size)) return;
    _size = next;
    _resizeTimer?.cancel();
    if (isWindows) {
      // Keyboard animations produce many transient sizes. Let ConPTY repaint
      // once at the settled dimensions, with Windows owning line reflow.
      _resizeTimer = Timer(const Duration(milliseconds: 120), () {
        _shell?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      });
    } else {
      _shell?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    }
  }

  Future<void> close() async {
    _resizeTimer?.cancel();
    ++_generation;
    _startFuture = null;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('Shell closed.'));
    }
    final shell = _shell;
    _shell = null;
    if (!_disposed) state.value = TerminalConnectionState.closed;
    shell?.close();
    final stdout = _stdout, stderr = _stderr;
    _stdout = null;
    _stderr = null;
    await stdout?.cancel();
    await stderr?.cancel();
  }

  Future<void> transportDisconnected() async {
    await close();
    if (!_disposed) {
      terminal.write(
        '\r\n[Connection closed — reconnect to resume with a new shell]\r\n',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await close();
    terminal.native?.dispose();
    state.dispose();
  }
}
