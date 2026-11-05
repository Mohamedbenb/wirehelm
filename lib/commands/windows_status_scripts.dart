// These scripts run inside the signed-in Windows desktop.
const windowsDisplayStatus = r'''
$ProgressPreference='SilentlyContinue'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class DTopo { [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint f,out uint p,out uint m); [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint f,ref uint p,IntPtr pa,ref uint m,IntPtr ma,out uint t); public static uint Get(){ for(int i=0;i<3;i++){ uint p,m,t=0; if(GetDisplayConfigBufferSizes(4,out p,out m)!=0)return 0; IntPtr pa=Marshal.AllocHGlobal((int)Math.Max(1,p)*1024); IntPtr ma=Marshal.AllocHGlobal((int)Math.Max(1,m)*1024); try { int e=QueryDisplayConfig(4,ref p,pa,ref m,ma,out t); if(e==0)return t; if(e!=122)return 0; } finally { Marshal.FreeHGlobal(pa); Marshal.FreeHGlobal(ma); } } return 0; } }'
switch([DTopo]::Get()){1{'internal'}2{'duplicate'}4{'extend'}8{'external'}default{'unknown'}}
''';

const windowsScreenStatus = r'''
$ProgressPreference='SilentlyContinue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class ScreenPower {
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint Callback(IntPtr c,uint t,IntPtr s);
 [StructLayout(LayoutKind.Sequential)] struct Subscription { public IntPtr callback,context; }
 [DllImport("powrprof.dll")] static extern uint PowerSettingRegisterNotification(ref Guid g,uint f,ref Subscription s,out IntPtr h);
 [DllImport("powrprof.dll")] static extern uint PowerSettingUnregisterNotification(IntPtr h);
 public static string Get() {
  int state=-1;
  using(var signal=new ManualResetEvent(false)) {
   Callback cb=delegate(IntPtr c,uint t,IntPtr s) { if(t==0x8013 && s!=IntPtr.Zero){state=Marshal.ReadInt32(s,20); signal.Set();} return 0; };
   var sub=new Subscription{callback=Marshal.GetFunctionPointerForDelegate(cb),context=IntPtr.Zero};
   Guid g=new Guid("6fe69556-704a-47a0-8f24-c28d936fda47"); IntPtr handle;
   if(PowerSettingRegisterNotification(ref g,2,ref sub,out handle)!=0)return "unknown";
   try { signal.WaitOne(2000); } finally { PowerSettingUnregisterNotification(handle); GC.KeepAlive(cb); }
  }
  return state==0?"sleeping":state==1||state==2?"awake":"unknown";
 }
}
'@
[ScreenPower]::Get()
''';

const windowsScreenSleep =
    r'''Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class MonitorSleep { [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r); }'; $r=[IntPtr]::Zero; [void][MonitorSleep]::SendMessageTimeout([IntPtr]65535,0x112,[IntPtr]0xF170,[IntPtr]2,2,2000,[ref]$r)''';
const windowsScreenWake =
    r'''Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class MonitorWake { [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e); }'; [MonitorWake]::mouse_event(1,0,0,0,[UIntPtr]::Zero)''';
