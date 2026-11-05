import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/remote_desktop.dart';

void main() {
  test('reads JPEG dimensions from its start-of-frame marker', () {
    final jpegHeader = Uint8List.fromList([
      0xff, 0xd8, // SOI
      0xff, 0xc0, // SOF0
      0x00, 0x11, // segment length
      0x08, // precision
      0x02, 0xd0, // height: 720
      0x05, 0x00, // width: 1280
      0x03, // color components
      0x01, 0x11, 0x00,
      0x02, 0x11, 0x00,
      0x03, 0x11, 0x00,
    ]);
    expect(jpegDimensions(jpegHeader), (1280, 720));
    expect(jpegDimensions(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test(
    'Windows stream captures the signed-in desktop and has bounded cleanup',
    () {
      expect(windowsDesktopWorkerScript, contains('CopyFromScreen'));
      expect(windowsDesktopWorkerScript, contains('SetCursorPos'));
      expect(windowsDesktopWorkerScript, contains('GetCursorPos'));
      expect(windowsDesktopWorkerScript, contains('GetCursorInfo'));
      expect(windowsDesktopWorkerScript, contains('DrawIconEx'));
      expect(
        windowsDesktopWorkerScript,
        contains(r'DrawCursor($graphics,$bounds)'),
      );
      expect(windowsDesktopWorkerScript, contains('point.X+x,point.Y+y'));
      expect(windowsDesktopWorkerScript, contains('control_'));
      expect(windowsDesktopWorkerScript, contains("'heartbeat'"));
      final token = 'a' * 64;
      final bootstrap = windowsDesktopBootstrapScript(controlToken: token);
      expect(bootstrap, contains('LogonType Interactive'));
      expect(bootstrap, contains('ExecutionTimeLimit'));
      expect(bootstrap, contains('TcpListener'));
      expect(bootstrap, contains('NodeCockpit_Desktop_'));
      expect(bootstrap, contains('Unregister-ScheduledTask'));
      expect(bootstrap, contains("-cne '$token'"));
    },
  );

  test('Linux stream documents its X11 tools and bounded JPEG capture', () {
    expect(linuxDesktopCaptureScript, contains('ffmpeg'));
    expect(linuxDesktopCaptureScript, contains('xrandr'));
    expect(linuxDesktopCaptureScript, contains('xdotool'));
    expect(linuxDesktopCaptureScript, contains('framerate 6'));
    expect(linuxDesktopCaptureScript, contains('image2pipe'));
    expect(linuxDesktopInputScript, contains('xdotool'));
    expect(linuxDesktopInputScript, contains('while IFS='));
    expect(linuxDesktopInputScript, contains('mousedown'));
  });

  test('Windows desktop PowerShell scripts parse cleanly', () async {
    final directory = await Directory.systemTemp.createTemp(
      'node-cockpit-desktop-script-test-',
    );
    try {
      final scripts = [
        windowsDesktopWorkerScript,
        windowsDesktopBootstrapScript(controlToken: 'b' * 64),
      ];
      for (var index = 0; index < scripts.length; index++) {
        final file = File('${directory.path}\\script-$index.ps1');
        await file.writeAsString(scripts[index]);
        final escapedPath = file.path.replaceAll("'", "''");
        final result = await Process.run('powershell.exe', [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "\$tokens=\$null;\$errors=\$null;[System.Management.Automation.Language.Parser]::ParseFile('$escapedPath',[ref]\$tokens,[ref]\$errors)|Out-Null;if(\$errors.Count){\$errors|ForEach-Object{\$_.Message};exit 1}",
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  test('signed-in Windows desktop worker captures a frame without rendering it', () async {
    if (Platform.environment['NODE_COCKPIT_DESKTOP_SMOKE_TEST'] != '1') {
      return;
    }
    final suffix = List.generate(
      32,
      (_) => Random.secure().nextInt(16).toRadixString(16),
    ).join();
    final name = 'NodeCockpit_Desktop_$suffix';
    final root = Directory('${Directory.systemTemp.path}\\$name');
    await root.create();
    await File('${root.path}\\desktop-worker.ps1')
        .writeAsString(windowsDesktopWorkerScript);
    await File('${root.path}\\heartbeat').writeAsString('active');
    final escapedRoot = root.path.replaceAll("'", "''");
    final task = name;
    const scriptTemplate = r'''
$ErrorActionPreference='Stop'
$root='__ROOT__'; $task='__TASK__'
$worker=Join-Path $root 'desktop-worker.ps1'
$launchCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$worker+'" -root "'+$root+'"'
$launchJson=ConvertTo-Json -InputObject $launchCommand -Compress
$js='var s=new ActiveXObject("WScript.Shell");s.Run('+$launchJson+',0,true);'
[IO.File]::WriteAllText((Join-Path $root 'launch.js'),$js,[Text.UTF8Encoding]::new($false))
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('//B //NoLogo "'+(Join-Path $root 'launch.js')+'"')
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $task
$deadline=(Get-Date).AddSeconds(12)
while(-not (Test-Path (Join-Path $root 'frame.seq')) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
if(-not (Test-Path (Join-Path $root 'frame.jpg'))){throw 'No frame appeared in the signed-in desktop session.'}
$sequencePath=Join-Path $root 'frame.seq'
if(-not (Test-Path $sequencePath)){
 $workerError=Join-Path $root 'error.txt'
 if(Test-Path $workerError){throw ('Desktop worker failed after capture: '+[IO.File]::ReadAllText($workerError))}
 throw 'The worker captured a frame but did not write a frame sequence.'
}
$sequence=[IO.File]::ReadAllText($sequencePath)
if($sequence -notmatch '^\d+$'){throw "The worker wrote an invalid frame sequence: $sequence"}
''';
    try {
      final script = scriptTemplate
          .replaceAll('__ROOT__', escapedRoot)
          .replaceAll('__TASK__', task);
      final result = await Process.run('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 25));
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final jpeg = await File('${root.path}\\frame.jpg').readAsBytes();
      expect(jpegDimensions(jpeg), isNotNull);
      // Only the JPEG header is examined; captured desktop pixels stay local.
    } finally {
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Stop-ScheduledTask -TaskName '$task' -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName '$task' -Confirm:\$false -ErrorAction SilentlyContinue",
      ]);
      if (await root.exists()) await root.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
