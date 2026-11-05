import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/ssh/persistent_terminal.dart';
import 'package:remote_control/screens/terminal_screen.dart';

class Shell implements SSHSession {
  final out = StreamController<Uint8List>();
  final err = StreamController<Uint8List>();
  final ended = Completer<void>();
  final writes = <List<int>>[];
  bool closed = false;
  @override
  Stream<Uint8List> get stdout => out.stream;
  @override
  Stream<Uint8List> get stderr => err.stream;
  @override
  Future<void> get done => ended.future;
  @override
  void write(Uint8List bytes) => writes.add(bytes);
  @override
  void close() {
    closed = true;
    if (!ended.isCompleted) ended.complete();
  }

  @override
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Unicode survives split SSH packets', () async {
    final bytes = utf8.encode('café 中文 😀');
    expect(
      await terminalOutput(
        Stream.fromIterable(bytes.map((b) => [b])),
        windows: true,
      ).join(),
      'café 中文 😀',
    );
  });
  test('Windows startup waits for marker split across packets', () async {
    final shell = Shell();
    final terminal = PersistentTerminal(
      isWindows: true,
      openShell: () async => shell,
    );
    final start = terminal.start();
    await Future<void>.delayed(Duration.zero);
    terminal.write('must not send');
    expect(shell.writes, isEmpty);
    shell.out.add(
      Uint8List.fromList(utf8.encode('\x1b[2J\x1b[H\x1b[5;3HPowerShell rea')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(terminal.isStarted, false);
    shell.out.add(Uint8List.fromList(utf8.encode('dy\r\nPS> ')));
    await start;
    expect(terminal.isStarted, true);
    expect(
      terminal.terminal.buffer.lines[4].getText(),
      contains('PowerShell ready'),
    );
    expect(terminal.terminal.reflowEnabled, false);
    terminal.write('whoami\r');
    expect(utf8.decode(shell.writes.single), 'whoami\r');
    await terminal.dispose();
  });
  test(
    'VT replies reach Windows before startup and without a visible screen',
    () async {
      final shell = Shell();
      final terminal = PersistentTerminal(
        isWindows: true,
        openShell: () async => shell,
      );
      var typed = 0;
      terminal.terminal.onOutput = (_) => typed++;
      final start = terminal.start();
      await Future<void>.delayed(Duration.zero);
      shell.out.add(Uint8List.fromList(utf8.encode('\x1b[4;7H\x1b[6n')));
      await Future<void>.delayed(Duration.zero);
      expect(utf8.decode(shell.writes.single), '\x1b[4;7R');
      expect(typed, 0);
      shell.out.add(Uint8List.fromList(utf8.encode('PowerShell ready')));
      await start;
      await terminal.dispose();
    },
  );
  test(
    'shell exit does not disconnect replacement and scrollback persists',
    () async {
      final old = Shell(), next = Shell();
      var current = old;
      final terminal = PersistentTerminal(
        isWindows: false,
        openShell: () async => current,
      );
      await terminal.start();
      old.out.add(Uint8List.fromList(utf8.encode('previous output\r\n')));
      await Future<void>.delayed(Duration.zero);
      await terminal.close();
      current = next;
      await terminal.start();
      await Future<void>.delayed(Duration.zero);
      expect(terminal.isStarted, true);
      expect(terminal.terminal.buffer.getText(), contains('previous output'));
      next.close();
      await Future<void>.delayed(Duration.zero);
      expect(terminal.state.value, TerminalConnectionState.closed);
      await terminal.dispose();
    },
  );
  test('closing during channel creation closes the late shell', () async {
    final opened = Completer<SSHSession>();
    final shell = Shell();
    final terminal = PersistentTerminal(
      isWindows: false,
      openShell: () => opened.future,
    );
    final start = terminal.start();
    final expectation = expectLater(start, throwsStateError);
    await terminal.close();
    opened.complete(shell);
    await expectation;
    expect(shell.closed, true);
    expect(terminal.isStarted, false);
    await terminal.dispose();
  });
  test('Ctrl and Alt encode input once and scripts are literal', () {
    expect(terminalModifiedInput('c', ctrl: true, alt: false), [3]);
    expect(terminalModifiedInput('x', ctrl: false, alt: true), [27, 120]);
    expect(
      terminalModifiedInput('😀', ctrl: false, alt: false),
      utf8.encode('😀'),
    );
    final script = "Write-Output 'hello'\nWrite-Output 'world'";
    final command = terminalComposerCommand(script, windows: true);
    expect(command, contains(base64Encode(utf8.encode(script))));
    expect(command, isNot(contains("'hello'")));
    expect(terminalComposerCommand('ls', windows: false), 'ls\r');
  });
  test('Windows bootstrap syntax parses without launching a shell', () async {
    if (!Platform.isWindows) return;
    final encoded = base64Encode(utf8.encode(windowsTerminalBootstrap));
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); \$t=\$null; \$e=\$null; [void][Management.Automation.Language.Parser]::ParseInput(\$s,[ref]\$t,[ref]\$e); if(\$e.Count){ \$e | Out-String; exit 1 }",
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
