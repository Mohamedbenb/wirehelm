import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_keyboard.dart';

void main() {
  test('literal text cannot become SendKeys shortcuts', () {
    expect(
      sendKeysLiteral('+^%~{}()[]\n\t'),
      '{+}{^}{%}{~}{{}{}}{(}{)}{[}{]}{ENTER}{TAB}',
    );
    final command = keyboardCommand(windows: true, text: "It's {F15}");
    expect(command, isNot(contains("It's")));
    expect(
      keyboardCommand(windows: false, text: "'; touch /tmp/bad"),
      contains("'\"'\"'"),
    );
    expect(
      () => keyboardCommand(windows: true, key: 'Invalid'),
      throwsArgumentError,
    );
  });
  test('framed PowerShell input executes before stdin reaches EOF', () async {
    if (!Platform.isWindows) return;
    const script =
        r"$s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))))";
    final encoded = base64Encode(
      script.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
    );
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]);
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    process.stderr.drain<void>();
    try {
      process.stdin.writeln(
        base64Encode(utf8.encode("Write-Output 'framed-ok'")),
      );
      await process.stdin.flush();
      expect(await output.timeout(const Duration(seconds: 10)), 'framed-ok');
    } finally {
      process.kill();
      await process.stdin.close();
    }
  });
}
