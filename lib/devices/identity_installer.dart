import 'dart:convert';
import 'dart:typed_data';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

class IdentityInstallResult {
  final bool alreadyInstalled;
  final String target;

  const IdentityInstallResult({
    required this.alreadyInstalled,
    required this.target,
  });
}

class IdentityInstaller {
  static const _installedMarker = '__REMOTE_CONTROL_IDENTITY_INSTALLED__';

  static const _existsMarker = '__REMOTE_CONTROL_IDENTITY_EXISTS__';

  static const _targetMarker = '__REMOTE_CONTROL_IDENTITY_TARGET__';

  Future<IdentityInstallResult> install({
    required Device device,
    required String publicKey,
    SshSession? session,
  }) async {
    final targetSession = session ?? sshSession;

    final connected =
        targetSession.isConnected && targetSession.deviceId == device.id;

    if (!connected) {
      throw Exception(
        'Connect to this device before '
        'installing an identity.',
      );
    }

    final key = publicKey.trim();

    if (key.isEmpty) {
      throw Exception(
        'The selected identity has no '
        'public key.',
      );
    }

    switch (device.shellStyle) {
      case 'linux':
        return _installLinux(targetSession, key);

      case 'windows':
        return _installWindows(targetSession, key);

      default:
        throw Exception(
          'Identity installation requires '
          'a Linux or Windows device type.',
        );
    }
  }

  Future<IdentityInstallResult> _installLinux(
    SshSession session,
    String publicKey,
  ) async {
    final quotedKey = _shellQuote(publicKey);

    final command =
        '''
set -e

ssh_dir="\$HOME/.ssh"
authorized="\$ssh_dir/authorized_keys"

mkdir -p "\$ssh_dir"
chmod 700 "\$ssh_dir"

touch "\$authorized"
chmod 600 "\$authorized"

key=$quotedKey

if grep -qxF -- "\$key" "\$authorized"; then
    printf '%s\\n' '$_existsMarker'
else
    printf '%s\\n' "\$key" >> "\$authorized"
    printf '%s\\n' '$_installedMarker'
fi

printf '%s%s\\n' '$_targetMarker' "\$authorized"
''';

    final result = await session.run(command);

    final output = utf8.decode(result, allowMalformed: true);

    return _parseResult(output);
  }

  Future<IdentityInstallResult> _installWindows(
    SshSession session,
    String publicKey,
  ) async {
    final script = _buildWindowsScript(publicKey);

    final encoded = _encodePowerShellCommand(
      r"$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; try { $s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s.Trim())))) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }",
    );

    final result = await session.run(
      'powershell.exe '
      '-NoProfile '
      '-NonInteractive '
      '-ExecutionPolicy Bypass '
      '-EncodedCommand '
      '$encoded',
      input: Uint8List.fromList(
        utf8.encode([base64Encode(utf8.encode(script)), '\n'].join()),
      ),
    );

    final output = utf8.decode(result, allowMalformed: true);

    return _parseResult(output);
  }

  String _buildWindowsScript(String publicKey) {
    final escapedKey = publicKey.replaceAll("'", "''");

    return '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
\$key = '$escapedKey'
\$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
\$isAdministrator = @(\$identity.Groups | Where-Object { \$_.Value -eq 'S-1-5-32-544' }).Count -gt 0
if (\$isAdministrator) {
    \$authorized = Join-Path \$env:ProgramData 'ssh\\administrators_authorized_keys'
} else {
    \$authorized = Join-Path \$env:USERPROFILE '.ssh\\authorized_keys'
}
\$sshDirectory = Split-Path -Parent \$authorized
New-Item -ItemType Directory -Path \$sshDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath \$authorized)) {
    New-Item -ItemType File -Path \$authorized -Force | Out-Null
}
\$alreadyExists = @((Get-Content -LiteralPath \$authorized) | Where-Object { \$_.Trim() -eq \$key }).Count -gt 0
if (-not \$alreadyExists) { Add-Content -LiteralPath \$authorized -Value \$key -Encoding Ascii }
if (\$isAdministrator) {
    try {
        \$acl = Get-Acl -LiteralPath \$authorized
        \$acl.SetAccessRuleProtection(\$true, \$false)
        foreach (\$rule in @(\$acl.Access)) { [void]\$acl.RemoveAccessRuleAll(\$rule) }
        \$administrators = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        \$system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        \$acl.SetOwner(\$administrators)
        \$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(\$administrators, 'FullControl', 'Allow'))
        \$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(\$system, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath \$authorized -AclObject \$acl
    } catch {
        throw ('The key was written, but Windows could not configure permissions. Connect with an elevated administrator account. ' + \$_.Exception.Message)
    }
}
Write-Output ('$_targetMarker' + \$authorized)
if (\$alreadyExists) { Write-Output '$_existsMarker' } else { Write-Output '$_installedMarker' }
''';
  }

  IdentityInstallResult _parseResult(String output) {
    final installed = output.contains(_installedMarker);

    final alreadyInstalled = output.contains(_existsMarker);

    if (!installed && !alreadyInstalled) {
      throw Exception(
        output.trim().isEmpty
            ? 'The identity installation '
                  'did not return a valid result.'
            : 'Identity installation failed:\n'
                  '${output.trim()}',
      );
    }

    String? target;

    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith(_targetMarker)) {
        target = line.substring(_targetMarker.length).trim();

        break;
      }
    }

    if (target == null || target.isEmpty) {
      target = 'authorized_keys';
    }

    return IdentityInstallResult(
      alreadyInstalled: alreadyInstalled,
      target: target,
    );
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _encodePowerShellCommand(String command) {
    final bytes = <int>[];

    for (final codeUnit in command.codeUnits) {
      bytes.add(codeUnit & 0xff);

      bytes.add((codeUnit >> 8) & 0xff);
    }

    return base64Encode(bytes);
  }
}
