import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_screenshot.dart';

void main() {
  test('Linux capture supplies a nonexistent filename and cleans up', () async {
    final bash = Platform.isWindows ? r'C:\Program Files\Git\bin\bash.exe' : '/bin/bash';
    if (!File(bash).existsSync()) return;
    final process = await Process.start(bash, ['--noprofile', '--norc']);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(r'''
scrot() {
  test ! -e "$1" || { echo 'Capture filename already exists' >&2; return 1; }
  printf '\211PNG\r\n\032\n' > "$1"
}
unset WAYLAND_DISPLAY
''');
    process.stdin.write(linuxScreenshotScript);
    await process.stdin.close();
    expect(await process.exitCode, 0, reason: await errors);
    expect(decodeScreenshot(await output), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
  test('Windows screenshot script parses without executing capture', () async {
    if (!Platform.isWindows) return;
    final encoded = base64Encode(utf8.encode(windowsScreenshotScript));
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); \$t=\$null; \$e=\$null; [void][Management.Automation.Language.Parser]::ParseInput(\$s,[ref]\$t,[ref]\$e); if(\$e.Count){ \$e | Out-String; exit 1 }",
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
  test('extracts framed PNG despite desktop wrapper noise', () {
    final png = [137, 80, 78, 71, 13, 10, 26, 10, 0];
    expect(
      decodeScreenshot('noise\n__COCKPIT_PNG__${base64Encode(png)}\nend'),
      png,
    );
  });
  test('rejects remote errors and non PNG content', () {
    expect(() => decodeScreenshot('Desktop is unavailable'), throwsStateError);
    expect(
      () => decodeScreenshot('__COCKPIT_PNG__${base64Encode([1, 2, 3])}'),
      throwsFormatException,
    );
  });
}
