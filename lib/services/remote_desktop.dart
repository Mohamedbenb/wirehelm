import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import 'remote_media.dart';

const windowsDesktopWorkerScript = r'''
param([string]$root)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct NcCursorInfo { public int cbSize; public int flags; public IntPtr hCursor; public Point ptScreenPos; }
[StructLayout(LayoutKind.Sequential)] public struct NcIconInfo { [MarshalAs(UnmanagedType.Bool)] public bool fIcon; public uint xHotspot; public uint yHotspot; public IntPtr hbmMask; public IntPtr hbmColor; }
public static class NcDesktopInput {
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
 [DllImport("user32.dll")] static extern bool GetCursorInfo(out NcCursorInfo info);
 [DllImport("user32.dll")] static extern bool GetIconInfo(IntPtr icon,out NcIconInfo info);
 [DllImport("user32.dll")] static extern bool DrawIconEx(IntPtr hdc,int x,int y,IntPtr icon,int width,int height,uint step,IntPtr brush,uint flags);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr handle);
 [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,int dx,int dy,int data,UIntPtr extra);
 static readonly HashSet<uint> heldButtons = new HashSet<uint>();
 static readonly object buttonLock = new object();
 public static Rectangle Bounds() {
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try { return new Rectangle(GetSystemMetrics(76),GetSystemMetrics(77),GetSystemMetrics(78),GetSystemMetrics(79)); }
  finally { SetThreadDpiAwarenessContext(previous); }
 }
 public static void Copy(Graphics graphics, Rectangle bounds) {
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try { graphics.CopyFromScreen(bounds.Left,bounds.Top,0,0,bounds.Size); }
  finally { SetThreadDpiAwarenessContext(previous); }
 }
 public static void Move(int x,int y) {
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try { if(!SetCursorPos(x,y)) throw new System.ComponentModel.Win32Exception(); }
  finally { SetThreadDpiAwarenessContext(previous); }
 }
 public static void DrawCursor(Graphics graphics, Rectangle bounds) {
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try {
   var cursor=new NcCursorInfo(); cursor.cbSize=Marshal.SizeOf(typeof(NcCursorInfo));
   if(!GetCursorInfo(out cursor) || (cursor.flags & 1)==0 || cursor.hCursor==IntPtr.Zero) return;
   NcIconInfo iconInfo;
   if(!GetIconInfo(cursor.hCursor,out iconInfo)) throw new System.ComponentModel.Win32Exception();
   try {
    var hdc=graphics.GetHdc();
    try {
     if(!DrawIconEx(hdc,cursor.ptScreenPos.X-bounds.Left-(int)iconInfo.xHotspot,cursor.ptScreenPos.Y-bounds.Top-(int)iconInfo.yHotspot,cursor.hCursor,0,0,0,IntPtr.Zero,3)) throw new System.ComponentModel.Win32Exception();
    } finally { graphics.ReleaseHdc(hdc); }
   } finally { if(iconInfo.hbmColor!=IntPtr.Zero) DeleteObject(iconInfo.hbmColor); if(iconInfo.hbmMask!=IntPtr.Zero) DeleteObject(iconInfo.hbmMask); }
  }
  finally { SetThreadDpiAwarenessContext(previous); }
 }
 public static void MoveRelative(int x,int y) {
  var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
  try { Point point; if(!GetCursorPos(out point)) throw new System.ComponentModel.Win32Exception(); if(!SetCursorPos(point.X+x,point.Y+y)) throw new System.ComponentModel.Win32Exception(); }
  finally { SetThreadDpiAwarenessContext(previous); }
 }
 public static void Down(uint button) {
  lock(buttonLock) { mouse_event(button,0,0,0,UIntPtr.Zero); heldButtons.Add(button); }
 }
 public static void Up(uint button) {
  lock(buttonLock) { if(heldButtons.Remove(button/2)) mouse_event(button,0,0,0,UIntPtr.Zero); }
 }
 public static void Click(uint button) {
  mouse_event(button,0,0,0,UIntPtr.Zero); mouse_event(button*2,0,0,0,UIntPtr.Zero);
 }
 public static void Release() {
  lock(buttonLock) {
   foreach(uint down in heldButtons) mouse_event(down*2,0,0,0,UIntPtr.Zero);
   heldButtons.Clear();
  }
 }
}
'@
$bounds=[NcDesktopInput]::Bounds()
$width=[Math]::Max(1,[int][Math]::Min(1280,$bounds.Width))
$height=[Math]::Max(1,[int][Math]::Round($bounds.Height*$width/$bounds.Width))
$jpeg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg' | Select-Object -First 1
$quality=[System.Drawing.Imaging.EncoderParameters]::new(1); $quality.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::Quality,[long]58)
$frame=Join-Path $root 'frame.jpg'; $frameTmp=Join-Path $root 'frame.tmp'; $sequence=Join-Path $root 'frame.seq'; $sequenceTmp=Join-Path $root 'frame.seq.tmp'; $errorPath=Join-Path $root 'error.txt'; $heartbeat=Join-Path $root 'heartbeat'
$seq=0; $nextControl=1
try {
 while ($true) {
  if (-not (Test-Path $root) -or -not (Test-Path $heartbeat) -or (Get-Item $heartbeat).LastWriteTime -lt (Get-Date).AddSeconds(-6)) { break }
  # Apply queued controls before doing the next expensive screen capture so
  # clicks and pointer moves do not wait behind a full frame encode.
  while (Test-Path (Join-Path $root ('control_'+$nextControl+'.json'))) {
   $controlPath=Join-Path $root ('control_'+$nextControl+'.json')
   try {
    $control=Get-Content -LiteralPath $controlPath -Raw | ConvertFrom-Json
    $x=$bounds.Left+[int][Math]::Round([Math]::Max([double]0,[Math]::Min([double]1,[double]$control.x))*($bounds.Width-1))
    $y=$bounds.Top+[int][Math]::Round([Math]::Max([double]0,[Math]::Min([double]1,[double]$control.y))*($bounds.Height-1))
    $button= switch ($control.button) { 'right' { 8 } 'middle' { 32 } default { 2 } }
    switch ($control.action) {
     'relative' { $dx=[int][Math]::Round([double]$control.deltaX*$bounds.Width); $dy=[int][Math]::Round([double]$control.deltaY*$bounds.Height); [NcDesktopInput]::MoveRelative($dx,$dy) }
     'clickAtCursor' { [NcDesktopInput]::Click([uint32]$button) }
     'downAtCursor' { [NcDesktopInput]::Down([uint32]$button) }
     'upAtCursor' { [NcDesktopInput]::Up([uint32]($button*2)) }
     default {
      [NcDesktopInput]::Move($x,$y)
      switch ($control.action) {
       'down' { [NcDesktopInput]::Down([uint32]$button) }
       'up' { [NcDesktopInput]::Up([uint32]($button*2)) }
       'click' { [NcDesktopInput]::Click([uint32]$button) }
       'move' { }
       'wheel' { $wheel=if($control.delta -gt 0){-120}else{120}; [NcDesktopInput]::mouse_event(2048,0,0,$wheel,[UIntPtr]::Zero) }
      }
     }
    }
   } catch { [IO.File]::WriteAllText($errorPath,$_.Exception.Message) }
   Remove-Item -LiteralPath $controlPath -Force -ErrorAction SilentlyContinue
   $nextControl++
  }
  try {
   $source=[System.Drawing.Bitmap]::new($bounds.Width,$bounds.Height)
   $graphics=[System.Drawing.Graphics]::FromImage($source)
   try {
    [NcDesktopInput]::Copy($graphics,$bounds)
    [NcDesktopInput]::DrawCursor($graphics,$bounds)
    $scaled=[System.Drawing.Bitmap]::new($width,$height)
    $scaledGraphics=[System.Drawing.Graphics]::FromImage($scaled)
    try { $scaledGraphics.DrawImage($source,0,0,$width,$height); $scaled.Save($frameTmp,$jpeg,$quality) }
    finally { $scaledGraphics.Dispose(); $scaled.Dispose() }
   } finally { $graphics.Dispose(); $source.Dispose() }
   Move-Item -LiteralPath $frameTmp -Destination $frame -Force
   $seq++; [IO.File]::WriteAllText($sequenceTmp,[string]$seq); Move-Item -LiteralPath $sequenceTmp -Destination $sequence -Force
  } catch { [IO.File]::WriteAllText($errorPath,$_.Exception.Message); Start-Sleep -Milliseconds 300 }
  Start-Sleep -Milliseconds 150
 }
} finally { [NcDesktopInput]::Release(); $quality.Dispose() }
''';

enum DesktopStreamMode { balanced, responsive, dataSaver }

({int width, int fps, int quality}) _streamSettings(DesktopStreamMode mode) =>
    switch (mode) {
      DesktopStreamMode.balanced => (width: 1280, fps: 8, quality: 55),
      DesktopStreamMode.responsive => (width: 960, fps: 30, quality: 44),
      DesktopStreamMode.dataSaver => (width: 640, fps: 4, quality: 42),
    };

String _windowsWorker(DesktopStreamMode mode) {
  final settings = _streamSettings(mode);
  return windowsDesktopWorkerScript
      .replaceAll('[Math]::Min(1280,', '[Math]::Min(${settings.width},')
      .replaceAll('[long]58', '[long]${settings.quality}')
      .replaceAll(
        'Start-Sleep -Milliseconds 150',
        'Start-Sleep -Milliseconds ${1000 ~/ settings.fps}',
      );
}

String windowsDesktopBootstrapScript({
  required String controlToken,
  DesktopStreamMode mode = DesktopStreamMode.balanced,
}) =>
    r'''
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$name='NodeCockpit_Desktop_'+[Guid]::NewGuid().ToString('N'); $root=Join-Path $env:TEMP $name; $task=$name
$listener=$null; $client=$null; $reader=$null
try {
 # Inherit the logged-in user's private %TEMP% DACL. The task principal below
 # is this same Windows account, so both the SSH launcher and worker share the
 # account ACL without creating a protected DACL that can omit the task token.
 [void][IO.Directory]::CreateDirectory($root)
 $workerPath=Join-Path $root 'desktop-worker.ps1'
 [IO.File]::WriteAllText($workerPath,[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__WORKER__')),[Text.UTF8Encoding]::new($true))
 $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0); $listener.Start(); $port=$listener.LocalEndpoint.Port
 $launcherPath=Join-Path $root 'launch.js'; $launchCommand='powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$workerPath+'" -root "'+$root+'"'; $launchJson=ConvertTo-Json -InputObject $launchCommand -Compress; $js='var s=new ActiveXObject("WScript.Shell");s.Run('+$launchJson+',0,true);'
 [IO.File]::WriteAllText($launcherPath,$js,[Text.UTF8Encoding]::new($false))
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
 $action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('//B //NoLogo "'+$launcherPath+'"')
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
 [IO.File]::WriteAllText((Join-Path $root 'heartbeat'),'active')
 Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
 Start-ScheduledTask -TaskName $task
 $lastHeartbeat=Get-Date
 [Console]::Out.WriteLine('__NC_DESKTOP_READY__'+$port); [Console]::Out.Flush()
 $client=$listener.AcceptTcpClient(); $reader=[IO.StreamReader]::new($client.GetStream(),[Text.Encoding]::UTF8)
 if($reader.ReadLine() -cne '__CONTROL_TOKEN__'){throw 'Desktop control authentication failed.'}
 $controlSeq=0; $frameSeq=0; $inputTask=$reader.ReadLineAsync()
 while($true){
  if($inputTask -and $inputTask.IsCompleted){$line=$inputTask.Result;if($null -eq $line){break};$control=$line|ConvertFrom-Json;$controlSeq++;$file=Join-Path $root ('control_'+$controlSeq+'.json');$pending=$file+'.tmp';[IO.File]::WriteAllText($pending,($control|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $pending -Destination $file;$inputTask=$reader.ReadLineAsync()}
  $sequenceFile=Join-Path $root 'frame.seq'
  $image=$null
  # The worker atomically replaces frame.seq after each capture. Windows can
  # briefly deny a concurrent read during that rename; treat it as a missed
  # poll and try again instead of stopping the entire stream.
  try { if(Test-Path $sequenceFile){$current=[int][IO.File]::ReadAllText($sequenceFile);if($current -gt $frameSeq){$image=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'frame.jpg')))}} } catch [System.IO.IOException] { Start-Sleep -Milliseconds 20 } catch [System.UnauthorizedAccessException] { Start-Sleep -Milliseconds 20 } catch [System.Management.Automation.ItemNotFoundException] { }
  if($image){[Console]::Out.WriteLine('__NC_FRAME__'+$current+':'+$image);[Console]::Out.Flush();$frameSeq=$current}
  $errorFile=Join-Path $root 'error.txt'
  try { if(Test-Path $errorFile){$message=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($errorFile)));[Console]::Out.WriteLine('__NC_ERROR__'+$message);[Console]::Out.Flush();Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue} } catch [System.IO.IOException] { }
  if(((Get-Date)-$lastHeartbeat).TotalSeconds -ge 1){[IO.File]::WriteAllText((Join-Path $root 'heartbeat'),'active');$lastHeartbeat=Get-Date}
  Start-Sleep -Milliseconds 10
 }
} catch { $message=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Exception.Message));[Console]::Out.WriteLine('__NC_FATAL__'+$message);[Console]::Out.Flush() }
finally {if($client){$client.Close()};if($listener){$listener.Stop()};Remove-Item -LiteralPath (Join-Path $root 'heartbeat') -Force -ErrorAction SilentlyContinue;Start-Sleep -Milliseconds 350;Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
'''
        .replaceAll(
          '__WORKER__',
          base64Encode(utf8.encode(_windowsWorker(mode))),
        )
        .replaceAll('__CONTROL_TOKEN__', controlToken);

Uint8List _powershellUtf16(String script) {
  final units = script.codeUnits;
  final bytes = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes[i * 2] = units[i] & 0xff;
    bytes[i * 2 + 1] = units[i] >> 8;
  }
  return bytes;
}

String _shellQuote(String text) => "'${text.replaceAll("'", "'\"'\"'")}'";

const linuxDesktopCaptureScript = r'''
set -eu
command -v ffmpeg >/dev/null || { echo 'FFmpeg is not installed on the remote device.' >&2; exit 1; }
command -v xrandr >/dev/null || { echo 'Live view currently needs an X11 desktop with xrandr.' >&2; exit 1; }
command -v xdotool >/dev/null || { echo 'Install xdotool on the remote Linux device to control the desktop.' >&2; exit 1; }
export DISPLAY=${DISPLAY:-:0}
geometry=$(xrandr --current | sed -nE 's/^[^ ]+ connected (primary )?([0-9]+x[0-9]+).*/\2/p' | head -n 1)
[ -n "$geometry" ] || { echo 'Could not detect an active X11 display.' >&2; exit 1; }
exec ffmpeg -hide_banner -loglevel error -f x11grab -framerate 6 -video_size "$geometry" -i "$DISPLAY" -vf "scale='min(1280,iw)':-2,fps=6" -q:v 8 -f image2pipe -vcodec mjpeg pipe:1
''';

const linuxDesktopInputScript = r'''
set -eu
command -v xdotool >/dev/null || { echo 'Install xdotool on the remote Linux device to control the desktop.' >&2; exit 1; }
command -v xrandr >/dev/null || { echo 'Live desktop control needs an X11 desktop with xrandr.' >&2; exit 1; }
export DISPLAY=${DISPLAY:-:0}
geometry=$(xrandr --current | sed -nE 's/^[^ ]+ connected (primary )?([0-9]+x[0-9]+).*/\2/p' | head -n 1)
[ -n "$geometry" ] || { echo 'Could not detect an active X11 display.' >&2; exit 1; }
width=${geometry%x*}; height=${geometry#*x}
printf '__NC_INPUT_READY__\n'
while IFS=' ' read -r xp yp action button delta dx dy; do
 [ -n "$action" ] || continue
 x=$((xp*(width-1)/10000)); y=$((yp*(height-1)/10000))
 case "$action" in
  down) xdotool mousemove "$x" "$y" mousedown "$button" ;;
  up) xdotool mouseup "$button" ;;
  click) xdotool mousemove "$x" "$y" click "$button" ;;
  downAtCursor) xdotool mousedown "$button" ;;
  upAtCursor) xdotool mouseup "$button" ;;
  clickAtCursor) xdotool click "$button" ;;
  relative) rx=$((dx*width/10000)); ry=$((dy*height/10000)); xdotool mousemove_relative -- "$rx" "$ry" ;;
  move) xdotool mousemove "$x" "$y" ;;
  wheel) if [ "$delta" -gt 0 ]; then xdotool mousemove "$x" "$y" click 5; else xdotool mousemove "$x" "$y" click 4; fi ;;
 esac
done
''';

class RemoteDesktopStream {
  final Device device;
  final SshSession session;
  final _frames = StreamController<Uint8List>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _jpeg = JpegFrames();
  final _ready = Completer<void>();
  SSHSession? _exec;
  SSHSession? _inputChannel;
  SSHForwardChannel? _control;
  String? _controlToken;
  StreamSubscription<Uint8List>? _stdout;
  StreamSubscription<Uint8List>? _stderr;
  StreamSubscription<Uint8List>? _inputStdout;
  StreamSubscription<Uint8List>? _inputStderr;
  StreamSubscription<String>? _windowsOutput;
  Timer? _limit;
  bool _windows = false, _stopped = false;
  final DesktopStreamMode mode;
  int _frameCount = 0, _lastFrameSequence = 0;
  String? _error;

  RemoteDesktopStream({
    required this.device,
    required this.session,
    this.mode = DesktopStreamMode.balanced,
  });
  Stream<Uint8List> get frames => _frames.stream;
  Stream<String> get errors => _errors.stream;
  bool get windows => _windows;

  Future<void> start() async {
    if (!session.isConnected || session.deviceId != device.id) {
      throw StateError('Connect to this device first.');
    }
    final client = session.client;
    if (client == null) throw StateError('Device disconnected.');
    _windows = device.shellStyle == 'windows';
    if (device.shellStyle == 'auto') {
      final output = utf8.decode(
        await session.run('uname -s', timeout: const Duration(seconds: 8)),
        allowMalformed: true,
      );
      _windows = !output.toLowerCase().contains('linux');
    }
    if (_stopped) return;
    _limit = Timer(const Duration(minutes: 10), () {
      _fail(StateError('Live desktop sessions stop after 10 minutes.'));
    });
    if (_windows) {
      final token = List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _controlToken = token;
      final script = windowsDesktopBootstrapScript(
        controlToken: token,
        mode: mode,
      );
      const bootstrap =
          r"$ProgressPreference='SilentlyContinue'; $ErrorActionPreference='Stop'; $s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))))";
      final encodedBootstrap = base64Encode(_powershellUtf16(bootstrap));
      final channel = await client.execute(
        'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedBootstrap',
      );
      if (_stopped) {
        channel.close();
        return;
      }
      _exec = channel;
      channel.stdin.add(utf8.encode('${base64Encode(utf8.encode(script))}\n'));
      await channel.stdin.close();
      _windowsOutput = channel.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onWindowsLine, onError: _fail, onDone: _onDone);
      _stderr = channel.stderr.listen((bytes) {
        final text = utf8.decode(bytes, allowMalformed: true).trim();
        if (text.isNotEmpty) _error = text;
      });
      await _ready.future.timeout(const Duration(seconds: 20));
    } else {
      await _startLinux(client);
    }
  }

  Future<void> _startLinux(SSHClient client) async {
    final inputReady = Completer<void>();
    final input = await client.execute(
      'sh -lc ${_shellQuote(linuxDesktopInputScript)}',
    );
    if (_stopped) {
      input.close();
      return;
    }
    _inputChannel = input;
    _inputStdout = input.stdout.listen(
      (bytes) {
        if (utf8
                .decode(bytes, allowMalformed: true)
                .contains('__NC_INPUT_READY__') &&
            !inputReady.isCompleted) {
          inputReady.complete();
        }
      },
      onError: (Object error) {
        if (!inputReady.isCompleted) inputReady.completeError(error);
      },
      onDone: () {
        if (!inputReady.isCompleted) {
          inputReady.completeError(
            StateError(
              _error ?? 'Could not start the Linux desktop input worker.',
            ),
          );
        }
      },
    );
    _inputStderr = input.stderr.listen((bytes) {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) _error = text;
    });
    await inputReady.future.timeout(const Duration(seconds: 10));
    if (_stopped) return;
    final settings = _streamSettings(mode);
    final captureScript = linuxDesktopCaptureScript
        .replaceAll('framerate 6', 'framerate ${settings.fps}')
        .replaceAll('fps=6', 'fps=${settings.fps}')
        .replaceAll('min(1280,iw)', 'min(${settings.width},iw)')
        .replaceAll(
          '-q:v 8',
          '-q:v ${((100 - settings.quality) / 5).round().clamp(2, 15)}',
        );
    final quoted = _shellQuote(captureScript);
    final channel = await client.execute('sh -lc $quoted');
    if (_stopped) {
      channel.close();
      return;
    }
    _exec = channel;
    _stdout = channel.stdout.listen(
      (bytes) {
        try {
          for (final image in _jpeg.add(bytes)) {
            _frameCount++;
            _frames.add(image);
            if (!_ready.isCompleted) _ready.complete();
          }
        } catch (error) {
          _fail(error);
        }
      },
      onError: _fail,
      onDone: _onDone,
    );
    _stderr = channel.stderr.listen((bytes) {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) _error = text;
    });
    await _ready.future.timeout(const Duration(seconds: 20));
  }

  void _onWindowsLine(String line) {
    if (_stopped) return;
    if (line.startsWith('__NC_FATAL__')) {
      try {
        _fail(
          StateError(
            utf8.decode(base64Decode(line.substring('__NC_FATAL__'.length))),
          ),
        );
      } catch (_) {
        _fail(
          StateError('The desktop stream could not continue. Please retry.'),
        );
      }
      return;
    }
    if (line.startsWith('__NC_DESKTOP_READY__')) {
      final port = int.tryParse(line.substring('__NC_DESKTOP_READY__'.length));
      if (port == null || port < 1 || port > 65535) {
        _fail(StateError('Invalid desktop control endpoint.'));
        return;
      }
      final client = session.client;
      if (client == null) {
        _fail(StateError('Device disconnected.'));
        return;
      }
      unawaited(
        client
            .forwardLocal('127.0.0.1', port)
            .then((control) {
              if (_stopped) {
                control.destroy();
              } else {
                _control = control;
                control.sink.add(utf8.encode('$_controlToken\n'));
              }
            })
            .catchError((Object error) => _fail(error)),
      );
      return;
    }
    if (line.startsWith('__NC_FRAME__')) {
      final split = line.indexOf(':', '__NC_FRAME__'.length);
      if (split < 0) return;
      final sequence = int.tryParse(
        line.substring('__NC_FRAME__'.length, split),
      );
      if (sequence == null || sequence <= _lastFrameSequence) return;
      _lastFrameSequence = sequence;
      try {
        _frames.add(base64Decode(line.substring(split + 1)));
        _frameCount++;
        if (!_ready.isCompleted) _ready.complete();
      } catch (error) {
        _fail(error);
      }
      return;
    }
    if (line.startsWith('__NC_ERROR__')) {
      try {
        _error = utf8.decode(
          base64Decode(line.substring('__NC_ERROR__'.length)),
        );
      } catch (_) {
        _error = 'Remote desktop capture failed.';
      }
    }
  }

  Future<void> sendPointer({
    required double x,
    required double y,
    required String action,
    String button = 'left',
    int delta = 0,
    double deltaX = 0,
    double deltaY = 0,
  }) async {
    if (_stopped) return;
    final event = {
      'x': x.clamp(0.0, 1.0),
      'y': y.clamp(0.0, 1.0),
      'action': action,
      'button': button,
      'delta': delta,
      'deltaX': deltaX,
      'deltaY': deltaY,
    };
    if (_windows) {
      final control = _control;
      if (control == null) return;
      control.sink.add(utf8.encode('${jsonEncode(event)}\n'));
      return;
    }
    final input = _inputChannel;
    if (input == null) return;
    final xPercent = (x.clamp(0.0, 1.0) * 10000).round();
    final yPercent = (y.clamp(0.0, 1.0) * 10000).round();
    final deltaXPercent = (deltaX * 10000).round();
    final deltaYPercent = (deltaY * 10000).round();
    input.stdin.add(
      utf8.encode(
        '$xPercent $yPercent $action ${_linuxButton(button)} $delta $deltaXPercent $deltaYPercent\n',
      ),
    );
  }

  int _linuxButton(String button) => switch (button) {
    'right' => 3,
    'middle' => 2,
    _ => 1,
  };

  void _onDone() {
    if (_stopped) return;
    final message = _error;
    _fail(
      StateError(
        message == null || message.isEmpty
            ? _frameCount == 0
                  ? 'No desktop frames received. Check that the user is signed into an interactive desktop session.'
                  : 'Desktop stream ended.'
            : message,
      ),
    );
  }

  void _fail(Object error) {
    if (_stopped) return;
    _error = '$error';
    _errors.add(_error!);
    if (!_ready.isCompleted) _ready.completeError(error);
    unawaited(stop());
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    if (!_ready.isCompleted) _ready.complete();
    _limit?.cancel();
    try {
      _control?.sink.close();
      _control?.destroy();
    } catch (_) {}
    try {
      _inputChannel?.stdin.close();
      _inputChannel?.kill(SSHSignal.TERM);
      _inputChannel?.close();
      final exec = _exec;
      if (exec != null) {
        if (_windows) {
          // Let the bootstrap observe the closed control socket and clean up
          // its scheduled task before falling back to a forced close.
          try {
            await exec.done.timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
        exec.kill(SSHSignal.TERM);
        exec.close();
      }
    } catch (_) {}
    await _windowsOutput?.cancel();
    await _stdout?.cancel();
    await _stderr?.cancel();
    await _inputStdout?.cancel();
    await _inputStderr?.cancel();
    await _frames.close();
    await _errors.close();
  }
}

/// Return the encoded JPEG width and height without decoding its pixels.
(int, int)? jpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  const startOfFrame = <int>{
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  };
  var offset = 2;
  while (offset + 3 < bytes.length) {
    if (bytes[offset] != 0xff) {
      offset++;
      continue;
    }
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0xd8 || marker == 0xd9 || marker == 0x01) continue;
    if (marker >= 0xd0 && marker <= 0xd7) continue;
    if (offset + 1 >= bytes.length) return null;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if (startOfFrame.contains(marker) && length >= 7) {
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width > 0 && height > 0) return (width, height);
      return null;
    }
    offset += length;
  }
  return null;
}
