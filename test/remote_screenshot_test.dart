import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_screenshot.dart';

void main() {
  test(
    'Linux capture returns a preview and retains the original for download',
    () async {
      final fixture = await Directory.systemTemp.createTemp(
        'wirehelm_screenshot_test_',
      );
      addTearDown(() => fixture.delete(recursive: true));
      // The worker normally uses /tmp on the SSH host. Confine both capture and
      // expiry cleanup to this fixture, with only the named utilities on PATH.
      final script = linuxScreenshotScript.replaceAll(
        '/tmp/NodeCockpit_Screenshot_',
        r'"$fixture"/NodeCockpit_Screenshot_',
      );
      final result = await Process.run(
        '/bin/bash',
        [
          '--noprofile',
          '--norc',
          '-c',
          r'''
set -eu
mkdir "$fixture/bin"
for tool in id sed head date stat mktemp chmod rm rmdir base64 tr; do
  ln -s "$(command -v "$tool")" "$fixture/bin/$tool"
done
export PATH="$fixture/bin"
export WAYLAND_DISPLAY=missing-test-display
scrot() {
  test ! -e "$1" || return 1
  printf 'test original' > "$1"
}
ffmpeg() {
  printf 'test preview' > "${!#}"
}
''' +
              script,
        ],
        environment: {'fixture': fixture.path, 'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final lines = const LineSplitter().convert(result.stdout as String);
      expect(lines, hasLength(2));
      const pathPrefix = '__COCKPIT_PATH__';
      expect(lines.first, startsWith(pathPrefix));
      final path = utf8.decode(
        base64Decode(lines.first.substring(pathPrefix.length)),
      );
      final original = File(path);
      expect(original.parent.parent.path, fixture.path);
      expect(await original.readAsString(), 'test original');
      expect(
        lines.last,
        '__COCKPIT_PREVIEW__${base64Encode(utf8.encode('test preview'))}',
      );
    },
    skip: !Platform.isLinux,
  );
  test('Windows screenshot script parses without executing capture', () async {
    final encoded = base64Encode(utf8.encode(windowsScreenshotScript));
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); \$t=\$null; \$e=\$null; [void][Management.Automation.Language.Parser]::ParseInput(\$s,[ref]\$t,[ref]\$e); if(\$e.Count){ \$e | Out-String; exit 1 }",
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: !Platform.isWindows);
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
