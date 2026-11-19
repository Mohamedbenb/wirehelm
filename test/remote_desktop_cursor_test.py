"""Execute the embedded Windows cursor C# against fail-closed native stubs.

No desktop is captured and no real input is sent. Every DllImport is replaced
before compilation; unknown imports fail the test. Tests run under both installed
Windows PowerShell architectures to check actual CLR structure alignment.
"""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

NATIVE = r'''
public static class CursorNative {
 public static Rectangle Desktop;
 public static Point Position;
 public static int Flags, Queries, SeenSize, PositionQueries, DpiCalls;
 public static bool QueryOk, PositionOk;
 public static IntPtr Dpi;
 public static readonly List<NcInput[]> Batches=new List<NcInput[]>();
 public static readonly Queue<uint> Results=new Queue<uint>();
 public static void Reset() {
  Desktop=new Rectangle(-1920,-200,4480,1640);Position=new Point(-100,200);
  Flags=2;Queries=0;SeenSize=0;PositionQueries=0;DpiCalls=0;
  QueryOk=true;PositionOk=true;Dpi=new IntPtr(17);Batches.Clear();Results.Clear();
 }
 public static IntPtr SetDpi(IntPtr value){var previous=Dpi;Dpi=value;DpiCalls++;return previous;}
 public static bool Query(ref NcCursorInfo info){Queries++;SeenSize=info.cbSize;if(!QueryOk)return false;info.flags=Flags;info.hCursor=new IntPtr(123);info.ptScreenPos=Position;return true;}
 public static uint Send(uint count,NcInput[] inputs,int size){
  if(size!=Marshal.SizeOf(typeof(NcInput))||count!=inputs.Length)throw new Exception("Invalid SendInput ABI");
  Batches.Add((NcInput[])inputs.Clone());return Results.Count>0?Results.Dequeue():count;
 }
 public static int Metric(int index){switch(index){case 76:return Desktop.Left;case 77:return Desktop.Top;case 78:return Desktop.Width;case 79:return Desktop.Height;default:throw new Exception("Unexpected metric");}}
}
'''

STUBS = {
 'SetThreadDpiAwarenessContext': 'public static IntPtr SetThreadDpiAwarenessContext(IntPtr value){return CursorNative.SetDpi(value);}',
 'SendInput': 'public static uint SendInput(uint count,NcInput[] inputs,int size){return CursorNative.Send(count,inputs,size);}',
 'GetCursorPos': 'public static bool GetCursorPos(out Point point){CursorNative.PositionQueries++;point=CursorNative.Position;return CursorNative.PositionOk;}',
 'GetCursorInfo': 'public static bool GetCursorInfo(ref NcCursorInfo info){return CursorNative.Query(ref info);}',
 'GetIconInfo': 'public static bool GetIconInfo(IntPtr icon,out NcIconInfo info){throw new Exception("Unexpected native icon access");}',
 'DrawIconEx': 'public static bool DrawIconEx(IntPtr hdc,int x,int y,IntPtr icon,int width,int height,uint step,IntPtr brush,uint flags){throw new Exception("Unexpected native drawing");}',
 'DeleteObject': 'public static bool DeleteObject(IntPtr handle){throw new Exception("Unexpected native resource access");}',
 'GetSystemMetrics': 'public static int GetSystemMetrics(int index){return CursorNative.Metric(index);}',
 'mouse_event': 'public static void mouse_event(uint flags,int dx,int dy,int data,UIntPtr extra){throw new Exception("Real button input must not run");}',
}

HARNESS = r'''
public static class CursorCases {
 static readonly Dictionary<string,string> Results=new Dictionary<string,string>();
 static void Check(bool value,string message){if(!value)throw new Exception(message);}
 static void DpiRestored(){Check(CursorNative.Dpi==new IntPtr(17),"DPI context leaked");}
 static void Run(string name,Action action){CursorNative.Reset();try{action();DpiRestored();Results[name]="pass";}catch(Exception e){Results[name]=e.GetType().Name+": "+e.Message;}}
 static int Expected(int p,int origin,int extent){var pixel=Math.Max(0L,Math.Min((long)extent-1,(long)p-origin));return (int)Math.Floor((pixel+0.5)*65536.0/extent);}
 static void Event(NcInput e,int x,int y){
  Check(e.type==0,"Not mouse input");Check(e.mi.dwFlags==0xc001,"MOVE/ABSOLUTE/VIRTUALDESK flags incorrect");
  Check(e.mi.mouseData==0&&e.mi.time==0&&e.mi.dwExtraInfo==UIntPtr.Zero,"Unexpected data/time/extra info");
  Check(e.mi.dx==Expected(x,CursorNative.Desktop.Left,CursorNative.Desktop.Width),"Wrong normalized x");
  Check(e.mi.dy==Expected(y,CursorNative.Desktop.Top,CursorNative.Desktop.Height),"Wrong normalized y");
  var actualX=CursorNative.Desktop.Left+(long)e.mi.dx*CursorNative.Desktop.Width/65536;
  var actualY=CursorNative.Desktop.Top+(long)e.mi.dy*CursorNative.Desktop.Height/65536;
  Check(actualX==Math.Max(CursorNative.Desktop.Left,Math.Min(CursorNative.Desktop.Right-1,x)),"Physical x does not round-trip");
  Check(actualY==Math.Max(CursorNative.Desktop.Top,Math.Min(CursorNative.Desktop.Bottom-1,y)),"Physical y does not round-trip");
 }
 static void ExpectFailure(Action action){var failed=false;try{action();}catch(System.ComponentModel.Win32Exception){failed=true;}Check(failed,"Native failure was swallowed");}
 public static Dictionary<string,string> All(){
  Run("abi",delegate{
   var x64=IntPtr.Size==8;
   Check(Marshal.SizeOf(typeof(NcMouseInput))==(x64?32:24),"MOUSEINPUT size");
   Check(Marshal.OffsetOf(typeof(NcMouseInput),"dwExtraInfo").ToInt32()==(x64?24:20),"ExtraInfo offset");
   Check(Marshal.SizeOf(typeof(NcInput))==(x64?40:28),"INPUT size");
   Check(Marshal.OffsetOf(typeof(NcInput),"mi").ToInt32()==(x64?8:4),"Mouse union offset");
  });
  Run("move_normalizes_clamps_negative_origin",delegate{
   var points=new[]{new Point(-1920,-200),new Point(-100,200),new Point(2559,1439),new Point(-9999,-9999),new Point(99999,99999)};
   foreach(var p in points){NcDesktopInput.Move(p.X,p.Y);var batch=CursorNative.Batches[CursorNative.Batches.Count-1];Check(batch.Length==1,"Move not singular");Event(batch[0],p.X,p.Y);DpiRestored();}
   Check(CursorNative.Queries==0,"Movement should not query visibility itself");
  });
  Run("relative_uses_physical_target",delegate{NcDesktopInput.MoveRelative(-200,350);Check(CursorNative.PositionQueries==1,"Position not read");Event(CursorNative.Batches[0][0],-300,550);});
  Run("suppressed_pair_restores_position",delegate{
   NcDesktopInput.EnsureCursorVisible();Check(CursorNative.Queries==1,"Wrong query count");
   Check(CursorNative.SeenSize==Marshal.SizeOf(typeof(NcCursorInfo)),"cbSize not initialized");
   Check(CursorNative.Batches.Count==1&&CursorNative.Batches[0].Length==2,"Recovery not one bounded pair");
   Event(CursorNative.Batches[0][0],-99,200);Event(CursorNative.Batches[0][1],-100,200);
  });
  Run("right_edge_nudges_inward",delegate{CursorNative.Position=new Point(2559,1439);NcDesktopInput.EnsureCursorVisible();Event(CursorNative.Batches[0][0],2558,1439);Event(CursorNative.Batches[0][1],2559,1439);});
  Run("out_of_bounds_position_is_clamped",delegate{CursorNative.Position=new Point(-3000,9000);NcDesktopInput.EnsureCursorVisible();Event(CursorNative.Batches[0][0],-1919,1439);Event(CursorNative.Batches[0][1],-1920,1439);});
  Run("one_pixel_wide_uses_vertical_nudge",delegate{CursorNative.Desktop=new Rectangle(-1,50,1,3);CursorNative.Position=new Point(-1,52);NcDesktopInput.EnsureCursorVisible();Event(CursorNative.Batches[0][0],-1,51);Event(CursorNative.Batches[0][1],-1,52);});
  Run("one_pixel_desktop_has_no_recovery_move",delegate{CursorNative.Desktop=new Rectangle(-1,50,1,1);NcDesktopInput.EnsureCursorVisible();Check(CursorNative.Batches.Count==0,"Tiny desktop generated input");});
  Run("showing_does_not_inject",delegate{CursorNative.Flags=1;NcDesktopInput.EnsureCursorVisible();Check(CursorNative.Batches.Count==0,"Visible cursor generated input");});
  Run("application_hidden_does_not_inject",delegate{CursorNative.Flags=0;NcDesktopInput.EnsureCursorVisible();Check(CursorNative.Batches.Count==0,"App-hidden cursor generated input");});
  Run("query_failure_is_reported_without_input",delegate{CursorNative.QueryOk=false;ExpectFailure(NcDesktopInput.EnsureCursorVisible);Check(CursorNative.Batches.Count==0,"Query failure generated input");});
  Run("partial_pair_attempts_single_restore_then_fails",delegate{
   CursorNative.Results.Enqueue(1);CursorNative.Results.Enqueue(1);ExpectFailure(NcDesktopInput.EnsureCursorVisible);
   Check(CursorNative.Batches.Count==2&&CursorNative.Batches[1].Length==1,"Unbounded or missing restore attempt");Event(CursorNative.Batches[1][0],-100,200);
  });
  Run("failed_restore_is_bounded",delegate{CursorNative.Results.Enqueue(0);CursorNative.Results.Enqueue(0);ExpectFailure(NcDesktopInput.EnsureCursorVisible);Check(CursorNative.Batches.Count==2,"Restore retries unbounded");});
  Run("move_failure_restores_dpi",delegate{CursorNative.Results.Enqueue(0);ExpectFailure(delegate{NcDesktopInput.Move(100,200);});Check(CursorNative.Batches.Count==1,"Single move retried unexpectedly");});
  Run("relative_query_failure_restores_dpi",delegate{CursorNative.PositionOk=false;ExpectFailure(delegate{NcDesktopInput.MoveRelative(1,1);});Check(CursorNative.Batches.Count==0,"Position query failure sent input");});
  return Results;
 }
}
'''


def production_worker():
    text = (ROOT / 'lib/services/remote_desktop.dart').read_text(encoding='utf-8')
    return text.split("const windowsDesktopWorkerScript = r'''", 1)[1].split("''';", 1)[0]


def stubbed_csharp(worker):
    code = worker.split("-TypeDefinition @'", 1)[1].split("\n'@", 1)[0].strip()
    imports = re.compile(r'\[DllImport\([^\]]+\)\]\s*(?:public\s+)?static\s+extern\s+\w+\s+(\w+)\([^;]*\);')
    seen = []
    def replace(match):
        name = match.group(1)
        if name not in STUBS:
            raise AssertionError('Unstubbed native method: ' + name)
        seen.append(name)
        return STUBS[name]
    code = imports.sub(replace, code)
    if '[DllImport' in code or set(seen) != set(STUBS):
        raise AssertionError('Native import extraction changed; refusing execution')
    code = code.replace('graphics.CopyFromScreen(bounds.Left,bounds.Top,0,0,bounds.Size);', 'throw new Exception("Screen capture is forbidden in this test");')
    if 'CopyFromScreen' in code:
        raise AssertionError('Screen capture extraction changed; refusing execution')
    return code + NATIVE + HARNESS


@unittest.skipUnless(os.name == 'nt', 'Windows CLR test')
class CursorInteropTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        worker = production_worker()
        code = stubbed_csharp(worker)
        encoded = base64.b64encode(code.encode('utf-8')).decode('ascii')
        script = "$ErrorActionPreference='Stop'\nAdd-Type -AssemblyName System.Drawing\n"
        script += "$code=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded + "'))\n"
        script += 'Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $code\n'
        script += '@{pointerSize=[IntPtr]::Size;cases=[CursorCases]::All()}|ConvertTo-Json -Depth 6 -Compress\n'
        windows = Path(os.environ.get('SystemRoot', 'C:/Windows'))
        cls.arch_results = {}
        with tempfile.TemporaryDirectory(prefix='wirehelm-cursor-stub-') as temp:
            path = Path(temp) / 'probe.ps1'
            path.write_text(script, encoding='utf-8-sig')
            for arch, folder in [('x64', 'System32'), ('x86', 'SysWOW64')]:
                exe = windows / folder / 'WindowsPowerShell/v1.0/powershell.exe'
                if not exe.is_file():
                    continue
                result = subprocess.run([str(exe), '-NoLogo', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', str(path)], capture_output=True, text=True, timeout=45)
                if result.returncode:
                    raise AssertionError(arch + ': ' + result.stdout + result.stderr)
                data = json.loads(result.stdout.strip())
                if data['pointerSize'] != (8 if arch == 'x64' else 4):
                    raise AssertionError('Unexpected PowerShell architecture: ' + arch)
                cls.arch_results[arch] = data['cases']
        if not cls.arch_results:
            raise unittest.SkipTest('Windows PowerShell unavailable')

    def check_case(self, name):
        for arch, results in self.arch_results.items():
            with self.subTest(architecture=arch):
                self.assertEqual(results[name], 'pass', name + ': ' + results[name])


for _case in re.findall(r'Run\("([a-z_]+)"', HARNESS):
    def _test(self, name=_case):
        self.check_case(name)
    setattr(CursorInteropTests, 'test_' + _case, _test)


class CursorIntegrationBoundaries(unittest.TestCase):
    def test_recovery_is_only_start_and_control_not_capture(self):
        worker = production_worker()
        calls = list(re.finditer(r'\[NcDesktopInput\]::EnsureCursorVisible\(\)', worker))
        self.assertEqual(len(calls), 2)
        loop = worker.index(' while ($true)')
        control = worker.index("$control=Get-Content -LiteralPath $controlPath")
        capture = worker.index('[NcDesktopInput]::Copy($graphics,$bounds)')
        self.assertLess(calls[0].start(), loop)
        self.assertGreater(calls[1].start(), control)
        self.assertLess(calls[1].start(), capture)
        self.assertNotIn('EnsureCursorVisible', worker[capture:])
        self.assertNotIn('ShowCursor(', worker)
        self.assertNotIn('SetCursorPos(', worker)
        self.assertRegex(worker, r"if\(\$control\.action -notin @\('up','upAtCursor'\)\)\s*\{\s*\[NcDesktopInput\]::EnsureCursorVisible\(\)\s*\}")
        self.assertRegex(worker, r"'up'\s*\{\s*try\s*\{\s*\[NcDesktopInput\]::Move\(\$x,\$y\)\s*\}\s*finally\s*\{\s*\[NcDesktopInput\]::Up\(\[uint32\]\(\$button\*2\)\)\s*\}\s*\}")


if __name__ == '__main__':
    unittest.main(verbosity=2)
