import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_clipboard.dart';

void main() {
  const id = '0123456789abcdef0123456789abcdef';
  test('transfer roots are absolute, unique and bounded before cleanup', () {
    expect(
      validClipboardRoot(
        'C:/Users/User/AppData/Local/Temp/Wirehelm_Clipboard_$id',
        id,
        true,
      ),
      true,
    );
    expect(
      validClipboardRoot('/tmp/Wirehelm_Clipboard_$id.abc123', id, false),
      true,
    );
    for (final path in [
      'C:/../Wirehelm_Clipboard_$id',
      'relative/Wirehelm_Clipboard_$id',
      'C:/Temp/Wirehelm_Clipboard_$id\nBAD',
    ]) {
      expect(validClipboardRoot(path, id, true), false);
    }
    expect(validClipboardRoot('/tmp/unrelated', id, false), false);
    expect(() => clipboardRootScript("bad';code"), throwsArgumentError);
  });
  test(
    'Windows uses file payload, STA desktop clipboard and bounded cleanup',
    () {
      final dir = Directory('build/clipboard-script-checks')
        ..createSync(recursive: true);
      File('${dir.path}/prepare.ps1')
          .writeAsStringSync(clipboardRootScript(id));
      File('${dir.path}/copy.ps1').writeAsStringSync(
        windowsClipboardScript(
          'C:/Temp/Wirehelm_Clipboard_$id',
          id,
          image: true,
        ),
      );
      File('${dir.path}/cleanup.ps1').writeAsStringSync(
        clipboardCleanupScript('C:/Temp/Wirehelm_Clipboard_$id', id),
      );
      final script = windowsClipboardScript(
        'C:/Temp/Wirehelm_Clipboard_$id',
        id,
        image: true,
      );
      expect(script, contains('[Windows.Forms.Clipboard]::SetImage'));
      expect(script, contains("GetApartmentState() -ne 'STA'"));
      expect(script, contains('GetFileName(\$root)'));
      expect(script, contains('[IO.Directory]::Delete(\$root,\$false)'));
      expect(script, contains('if (\$true)'));
      expect(
        windowsClipboardScript(
          'C:/Temp/Wirehelm_Clipboard_$id',
          id,
          image: false,
        ),
        contains('[IO.File]::ReadAllText'),
      );
    },
  );
}
