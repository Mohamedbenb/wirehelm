import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/ssh/windows_command_host.dart';

void main() {
  test('saved literal source uses cached types instead of fresh PowerShell', () {
    const old =
        r"$src='public class DTopo { public static int Get(){return 4;} }'; Add-Type -TypeDefinition $src; [DTopo]::Get()";
    final normalized = normalizeWindowsTypes(old);
    expect(
      normalized,
      contains("Add-Type -TypeDefinition 'public class DTopo"),
    );
    expect(requiresFreshWindowsProcess(normalized), isFalse);
    expect(cacheWindowsTypes(normalized), contains('NCTypeDefs'));
  });
  test('reassigned or dynamic type source keeps fresh-process behavior', () {
    const reassigned =
        r"$src='public class A {}'; $src=Get-Content test.cs; Add-Type -TypeDefinition $src";
    expect(normalizeWindowsTypes(reassigned), reassigned);
    expect(requiresFreshWindowsProcess(reassigned), isTrue);
  });
}
