import 'dart:async';
import 'dart:convert';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

class BluetoothDeviceInfo {
  final String id;
  final String name;
  final String kind;
  final bool paired;
  final bool trusted;
  final bool connected;
  final int? signal;
  final int? battery;
  final DateTime? seenAt;

  const BluetoothDeviceInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.paired,
    required this.trusted,
    required this.connected,
    this.signal,
    this.battery,
    this.seenAt,
  });

  bool get canPair => !paired && !connected;
  bool get canDisconnect => connected;
  bool get canConnect => paired && !connected;

  factory BluetoothDeviceInfo.fromMap(Map map) => BluetoothDeviceInfo(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString().trim().isNotEmpty == true
        ? map['name'].toString().trim()
        : 'Unknown device',
    kind: map['kind']?.toString() ?? 'Bluetooth device',
    paired: _asBool(map['paired']) || _asBool(map['remembered']),
    trusted: _asBool(map['trusted']),
    connected: _asBool(map['connected']),
    signal: _asInt(map['signal']),
    battery: _asInt(map['battery']),
    seenAt: DateTime.tryParse(map['seenAt']?.toString() ?? ''),
  );
}

class BluetoothSnapshot {
  final bool available;
  final String adapter;
  final bool? powered;
  final int? outputVolume;
  final String? outputName;
  final List<BluetoothDeviceInfo> devices;

  const BluetoothSnapshot({
    required this.available,
    required this.adapter,
    required this.powered,
    required this.devices,
    this.outputVolume,
    this.outputName,
  });
}

const linuxBluetoothScript = r'''
set +e
if ! command -v bluetoothctl >/dev/null 2>&1; then
 printf '__RC_BT_ERROR__\t%s\n' "$(printf '%s' 'bluetoothctl is not installed. Install it with: sudo apt install bluez' | base64 | tr -d '\n')"
 exit 0
fi
controller=$(bluetoothctl show 2>/dev/null)
powered=$(printf '%s\n' "$controller" | sed -n 's/^[[:space:]]*Powered: //p' | head -n 1)
adapter=$(printf '%s\n' "$controller" | sed -n 's/^[[:space:]]*Name: //p' | head -n 1)
[ -n "$adapter" ] || adapter=$(printf '%s\n' "$controller" | sed -n 's/^Controller [^ ]* //p' | head -n 1)
enc() { printf '%s' "$1" | base64 | tr -d '\n'; }
printf '__RC_BT_STATE__\t%s\t%s\n' "$(enc "$adapter")" "$powered"
volume=''; output=''
if command -v wpctl >/dev/null 2>&1; then
 raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
 value=$(printf '%s\n' "$raw" | awk '{print $2; exit}')
 case "$value" in ''|*[!0-9.]* ) ;; *) volume=$(awk -v v="$value" 'BEGIN {n=int(v*100+0.5); if(n<0)n=0;if(n>100)n=100;print n}') ;; esac
 output='Default audio output'
elif command -v pactl >/dev/null 2>&1; then
 raw=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null)
 volume=$(printf '%s\n' "$raw" | sed -n 's/.*\([0-9][0-9]*\)%.*$/\1/p' | head -n 1)
 output=$(pactl get-default-sink 2>/dev/null)
elif command -v amixer >/dev/null 2>&1; then
 volume=$(amixer get Master 2>/dev/null | awk -F'[][]' '/Playback/ {gsub(/%/,"",$2); print $2; exit}')
 output='ALSA Master output'
fi
if [ -n "$volume" ]; then printf '__RC_BT_VOLUME__\t%s\t%s\n' "$volume" "$(enc "$output")"; fi
bluetoothctl devices 2>/dev/null | while IFS= read -r line; do
 case "$line" in Device\ *) ;; *) continue ;; esac
 address=$(printf '%s\n' "$line" | awk '{print $2}')
 name=${line#Device "$address" }
 case "$address" in [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) ;; *) continue ;; esac
 info=$(bluetoothctl info "$address" 2>/dev/null)
 paired=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Paired: //p' | head -n 1)
 trusted=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Trusted: //p' | head -n 1)
 connected=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Connected: //p' | head -n 1)
 icon=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Icon: //p' | head -n 1)
 signal=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*RSSI: //p' | head -n 1)
 battery=$(printf '%s\n' "$info" | sed -n 's/.*Battery Percentage:.*(\([0-9][0-9]*\)).*/\1/p' | head -n 1)
 printf '__RC_BT_DEVICE__\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$address" "$(enc "$name")" "$(enc "${icon:-Bluetooth device}")" "$paired" "$trusted" "$connected" "$signal" "$battery"
done
''';

const linuxBluetoothPairCommand =
    'NO_COLOR=1 TERM=dumb bluetoothctl --agent NoInputNoOutput --timeout 25 pair __ADDRESS__';

const windowsAudioPairingScript = r'''
$ErrorActionPreference='Stop'
$type='NcModernAudioPairV42' -as [type]
if($null -eq $type) {
 Add-Type -AssemblyName System.Runtime.WindowsRuntime
 $parameters=New-Object System.CodeDom.Compiler.CompilerParameters
 $parameters.GenerateInMemory=$true
 foreach($reference in @('System.dll','System.Core.dll',"$env:WINDIR\System32\WinMetadata\Windows.Devices.winmd","$env:WINDIR\System32\WinMetadata\Windows.Foundation.winmd")) { [void]$parameters.ReferencedAssemblies.Add($reference) }
 foreach($name in @('System.Runtime','System.Threading.Tasks','System.Runtime.InteropServices.WindowsRuntime')) {
  $reference=Get-ChildItem -LiteralPath "$env:WINDIR\Microsoft.NET\assembly\GAC_MSIL\$name" -Recurse -Filter "$name.dll" | Select-Object -First 1
  if($null -eq $reference){throw 'Windows Bluetooth pairing runtime is unavailable.'}
  [void]$parameters.ReferencedAssemblies.Add($reference.FullName)
 }
 $provider=New-Object Microsoft.CSharp.CSharpCodeProvider
 try {
  $compiled=$provider.CompileAssemblyFromSource($parameters,@'
using System;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;
public static class NcModernAudioPairV42 {
 static System.Threading.Thread worker;
 static Windows.Foundation.IAsyncInfo pending;
 static volatile string state="done|0||0";
 public static string Status() {return state;}
 public static void Cancel() {var p=pending;if(p!=null)p.Cancel();}
 public static void Start(ulong address,bool repair) {
  if(worker!=null && worker.IsAlive)throw new InvalidOperationException("Another pairing is finishing. Retry shortly.");
  state="running|0||0";
  worker=new System.Threading.Thread(()=> {
   try {var result=Pair(address,repair);state=result=="Paired" || result=="AlreadyPaired"?"done|0||0":"done|"+result+"||0";}
   catch(Exception e) {state="done|"+e.GetBaseException().Message.Replace("|"," ")+"||0";}
   finally{pending=null;}
  });worker.IsBackground=true;worker.Start();
 }
 static void Wait(Windows.Foundation.IAsyncInfo operation) {
  pending=operation;var watch=System.Diagnostics.Stopwatch.StartNew();
  while(operation.Status==Windows.Foundation.AsyncStatus.Started) {
   if(watch.ElapsedMilliseconds>25000){operation.Cancel();throw new TimeoutException("Pairing timed out. Put the device in pairing mode and retry.");}
   System.Threading.Thread.Sleep(50);
  }
 }
 public static string Pair(ulong address,bool repair) {
  var operation=BluetoothDevice.FromBluetoothAddressAsync(address);
  Wait(operation);
  var device=operation.GetResults();
  try {
   if(repair) {
    var unpair=device.DeviceInformation.Pairing.UnpairAsync();Wait(unpair);
    var removal=unpair.GetResults();
    if(removal.Status!=DeviceUnpairingResultStatus.Unpaired && removal.Status!=DeviceUnpairingResultStatus.AlreadyUnpaired)throw new InvalidOperationException("Windows could not remove the old pairing: "+removal.Status);
    device.Dispose();operation=BluetoothDevice.FromBluetoothAddressAsync(address);Wait(operation);device=operation.GetResults();
   }
   var custom=device.DeviceInformation.Pairing.Custom;
   custom.PairingRequested += delegate(DeviceInformationCustomPairing sender,DevicePairingRequestedEventArgs e) {
    if(e.PairingKind==DevicePairingKinds.ConfirmOnly)e.Accept();
    else if(e.PairingKind==DevicePairingKinds.ProvidePin)e.Accept("0000");
   };
   var pair=custom.PairAsync(DevicePairingKinds.ConfirmOnly|DevicePairingKinds.ProvidePin,DevicePairingProtectionLevel.None);
   Wait(pair);
   var result=pair.GetResults();
   return result.Status.ToString();
  }finally{device.Dispose();}
 }
}
'@)
  if($compiled.Errors.HasErrors){throw ($compiled.Errors | Out-String)}
  $type=$compiled.CompiledAssembly.GetType('NcModernAudioPairV42')
 }finally{$provider.Dispose();$parameters.TempFiles.Delete()}
}
$address=[Convert]::ToUInt64('__ADDRESS__'.Replace(':','').Replace('-',''),16)
[NcModernAudioPairV42]::Start($address,('__OPERATION__' -eq 'repair'))
Write-Output '__RC_BT_ACTION__STARTED'
''';

const windowsBluetoothScript = r'''
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
if (-not ('NcBluetoothApiV46' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Threading;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct NcBtSearchV42 { public uint size; [MarshalAs(UnmanagedType.Bool)] public bool authenticated; [MarshalAs(UnmanagedType.Bool)] public bool remembered; [MarshalAs(UnmanagedType.Bool)] public bool unknown; [MarshalAs(UnmanagedType.Bool)] public bool connected; [MarshalAs(UnmanagedType.Bool)] public bool inquiry; public byte timeout; public IntPtr radio; }
[StructLayout(LayoutKind.Sequential)] public struct NcBtSystemTimeV42 { public ushort year; public ushort month; public ushort dayOfWeek; public ushort day; public ushort hour; public ushort minute; public ushort second; public ushort milliseconds; }
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct NcBtDeviceV42 { public uint size; public ulong address; public uint deviceClass; [MarshalAs(UnmanagedType.Bool)] public bool connected; [MarshalAs(UnmanagedType.Bool)] public bool remembered; [MarshalAs(UnmanagedType.Bool)] public bool authenticated; public NcBtSystemTimeV42 lastSeen; public NcBtSystemTimeV42 lastUsed; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=248)] public string name; }
public static class NcBluetoothApiV46 {
 [DllImport("bthprops.cpl", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr BluetoothFindFirstDevice(ref NcBtSearchV42 search, ref NcBtDeviceV42 device);
 [DllImport("bthprops.cpl", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool BluetoothFindNextDevice(IntPtr find, ref NcBtDeviceV42 device);
 [DllImport("bthprops.cpl", SetLastError=true)] static extern bool BluetoothFindDeviceClose(IntPtr find);
 [DllImport("bthprops.cpl", SetLastError=true)] static extern uint BluetoothRemoveDevice(ref ulong address);
 [DllImport("bthprops.cpl")] static extern uint BluetoothGetDeviceInfo(IntPtr radio, ref NcBtDeviceV42 device);
 [StructLayout(LayoutKind.Sequential)] struct AuthParams { public NcBtDeviceV42 device; public int method, io, requirements; public uint number; }
 [StructLayout(LayoutKind.Explicit, Size=48)] struct AuthResponse { [FieldOffset(0)] public ulong address; [FieldOffset(8)] public int method; [FieldOffset(12)] public uint number; [FieldOffset(12)] public byte pin0; [FieldOffset(13)] public byte pin1; [FieldOffset(14)] public byte pin2; [FieldOffset(15)] public byte pin3; [FieldOffset(16)] public byte pin4; [FieldOffset(17)] public byte pin5; [FieldOffset(18)] public byte pin6; [FieldOffset(19)] public byte pin7; [FieldOffset(20)] public byte pin8; [FieldOffset(21)] public byte pin9; [FieldOffset(22)] public byte pin10; [FieldOffset(23)] public byte pin11; [FieldOffset(24)] public byte pin12; [FieldOffset(25)] public byte pin13; [FieldOffset(26)] public byte pin14; [FieldOffset(27)] public byte pin15; [FieldOffset(28)] public byte pinLength; [FieldOffset(44)] public byte negative; }
 [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate bool AuthCallback(IntPtr context, ref AuthParams args);
 [DllImport("bthprops.cpl")] static extern uint BluetoothRegisterForAuthenticationEx(ref NcBtDeviceV42 device,out IntPtr registration,AuthCallback callback,IntPtr context);
 [DllImport("bthprops.cpl")] static extern bool BluetoothUnregisterAuthentication(IntPtr registration);
 [DllImport("bthprops.cpl")] static extern uint BluetoothAuthenticateDeviceEx(IntPtr parent,IntPtr radio,ref NcBtDeviceV42 device,IntPtr oob,int requirements);
 [DllImport("bthprops.cpl")] static extern uint BluetoothSendAuthenticationResponseEx(IntPtr radio,ref AuthResponse response);
 [StructLayout(LayoutKind.Sequential)] struct RadioSearch { public uint size; }
 [DllImport("bthprops.cpl",SetLastError=true)] static extern IntPtr BluetoothFindFirstRadio(ref RadioSearch search,out IntPtr radio);
 [DllImport("bthprops.cpl")] static extern bool BluetoothFindNextRadio(IntPtr find,out IntPtr radio);
 [DllImport("bthprops.cpl")] static extern bool BluetoothFindRadioClose(IntPtr find);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool DeviceIoControl(IntPtr handle,uint code,ref ulong address,uint size,IntPtr output,uint outputSize,out uint returned,IntPtr overlapped);
 static readonly object pairLock=new object();
 static Thread pairing; static int pairCode; static string challenge=""; static uint challengeNumber; static string answer=""; static readonly AutoResetEvent reply=new AutoResetEvent(false);
 public static string PairStatus() { lock(pairLock) { return (pairing!=null && pairing.IsAlive?"running":"done")+"|"+pairCode+"|"+challenge+"|"+challengeNumber; } }
 public static void PairReply(string value) { lock(pairLock) { answer=value; challenge=""; } reply.Set(); }
 public static void PairStart(string address) {
  lock(pairLock) {
   if(pairing!=null && pairing.IsAlive) throw new InvalidOperationException("Another pairing is still finishing. Retry shortly.");
   pairCode=0; challenge=""; answer=""; reply.Reset();
   pairing=new Thread(()=> {
    IntPtr registration=IntPtr.Zero; bool targetAudio=false;
    AuthCallback callback=delegate(IntPtr context,ref AuthParams args) {
     var response=new AuthResponse { address=args.device.address,method=args.method,number=args.number };
     // Just Works headphones have no display or keypad. Other challenges require phone confirmation.
     if(args.method==2) { response.negative=1; return BluetoothSendAuthenticationResponseEx(IntPtr.Zero,ref response)==0; }
     bool audio=targetAudio || ((args.device.deviceClass>>8)&31)==4;
     bool automaticPin=args.method==1 && audio;
     if(automaticPin) {
      // Legacy audio devices use the conventional fixed PIN without user entry.
      IntPtr buffer=Marshal.AllocHGlobal(48);
      try { Marshal.StructureToPtr(response,buffer,false); Marshal.Copy(System.Text.Encoding.ASCII.GetBytes("0000"),0,IntPtr.Add(buffer,12),4); Marshal.WriteByte(buffer,28,4); response=(AuthResponse)Marshal.PtrToStructure(buffer,typeof(AuthResponse)); }
      finally { Marshal.FreeHGlobal(buffer); }
     }
     if(!automaticPin && !(args.method==3 && args.io==3)) {
      lock(pairLock) { challenge=args.method==3?"confirm":args.method==4?"display":args.method==1?"pin":"passkey"; challengeNumber=args.number; answer=""; }
      bool answered=reply.WaitOne(20000); string value; lock(pairLock) { value=answer; challenge=""; }
      if(!answered || value=="cancel") response.negative=1;
      else if(args.method==1) {
       // Legacy PIN response supports up to sixteen bytes through the native union.
       byte[] bytes=System.Text.Encoding.ASCII.GetBytes(value); IntPtr buffer=Marshal.AllocHGlobal(48);
       try { Marshal.StructureToPtr(response,buffer,false); Marshal.Copy(bytes,0,IntPtr.Add(buffer,12),bytes.Length); Marshal.WriteByte(buffer,28,(byte)bytes.Length); response=(AuthResponse)Marshal.PtrToStructure(buffer,typeof(AuthResponse)); }
       finally { Marshal.FreeHGlobal(buffer); }
      } else if(args.method==5) { uint number; if(UInt32.TryParse(value,out number))response.number=number; else response.negative=1; }
      else if(value!="yes") response.negative=1;
     }
     if(args.method==4)return response.negative==0;
     return BluetoothSendAuthenticationResponseEx(IntPtr.Zero,ref response)==0;
    };
    try {
     var item=NewDevice(); item.address=ParseAddress(address);
     if(BluetoothGetDeviceInfo(IntPtr.Zero,ref item)!=0) {
      // Removing a stale bond also removes its cached class/name. Rediscover
      // the selected address before registering the authentication callback.
      foreach(var found in Devices(true)) if(found.address==item.address) {item=found;break;}
     }
     targetAudio=((item.deviceClass>>8)&31)==4;
     if(item.authenticated || item.remembered) return;
     uint code=BluetoothRegisterForAuthenticationEx(ref item,out registration,callback,IntPtr.Zero);
     if(code==0)code=BluetoothAuthenticateDeviceEx(IntPtr.Zero,IntPtr.Zero,ref item,IntPtr.Zero,2);
     lock(pairLock)pairCode=(int)code;
    } catch { lock(pairLock)pairCode=-1; }
    finally { if(registration!=IntPtr.Zero)BluetoothUnregisterAuthentication(registration); GC.KeepAlive(callback); lock(pairLock)challenge=""; }
   }); pairing.IsBackground=true; pairing.Start();
  }
 }
 [DllImport("bthprops.cpl")] static extern uint BluetoothEnumerateInstalledServices(IntPtr radio,ref NcBtDeviceV42 device,ref uint count,[Out] Guid[] services);
 [DllImport("bthprops.cpl")] static extern uint BluetoothSetServiceState(IntPtr radio,ref NcBtDeviceV42 device,ref Guid service,uint flags);
 public static int Connect(string address) {
  var search=new RadioSearch {size=4};IntPtr radio;var find=BluetoothFindFirstRadio(ref search,out radio);if(find==IntPtr.Zero)return Marshal.GetLastWin32Error();
  BluetoothFindRadioClose(find);
  try {return ConnectOnRadio(radio,address);}finally{CloseHandle(radio);}
 }
 static int ConnectOnRadio(IntPtr radio,string address) {
  var item=NewDevice();item.address=ParseAddress(address);
  uint state=BluetoothGetDeviceInfo(radio,ref item);if(state!=0)return (int)state;
  if(!item.authenticated && !item.remembered)return 1168;
  bool audioDevice=((item.deviceClass>>8)&31)==4;
  if(item.connected && !audioDevice)return 0;
  if(audioDevice && !item.connected) {int audio=ReconnectAudio(address);if(audio==0)return 0;}
  uint count=32;var services=new Guid[count];
  uint code=BluetoothEnumerateInstalledServices(radio,ref item,ref count,services);
  if(code==234 && count<=128) { services=new Guid[count];code=BluetoothEnumerateInstalledServices(radio,ref item,ref count,services); }
  if(code!=0)return unchecked((int)code);
  var profiles=new List<Guid>();
  // Audio pairing alone may not have installed either playback or voice profiles.
  if(((item.deviceClass>>8)&31)==4) {
   profiles.Add(new Guid("0000110b-0000-1000-8000-00805f9b34fb"));
   profiles.Add(new Guid("0000111e-0000-1000-8000-00805f9b34fb"));
  }
  for(int i=0;i<count;i++)if(!profiles.Contains(services[i]))profiles.Add(services[i]);
  if(profiles.Count==0)return 1060;
  int failure=1060;bool enabled=false;
  foreach(var profile in profiles) {
   var service=profile;
   code=BluetoothSetServiceState(radio,ref item,ref service,1);
   // Existing profiles are left installed. Reconnect uses the audio driver's
   // request, rather than uninstalling/reinstalling drivers to force a link.
   if(code==0x80070057 || code==87)continue;
   if(code==0)enabled=true;else failure=unchecked((int)code);
  }
  if(audioDevice && item.connected)return 0;
  if(audioDevice) { for(int attempt=0;attempt<(enabled?8:1);attempt++) {if(enabled)Thread.Sleep(250);int audio=ReconnectAudio(address);if(audio==0)return 0;failure=audio;} return failure;}
  return enabled?0:failure;
 }
 public static int Disconnect(string address) {
  ulong value=ParseAddress(address); var item=NewDevice();item.address=value;
  uint state=BluetoothGetDeviceInfo(IntPtr.Zero,ref item); if(state!=0)return (int)state; if(!item.connected)return 0;
  var search=new RadioSearch {size=4}; IntPtr radio; var find=BluetoothFindFirstRadio(ref search,out radio);if(find==IntPtr.Zero)return Marshal.GetLastWin32Error();
  int error=1168;
  try { do { try { uint returned; if(DeviceIoControl(radio,0x0041000C,ref value,8,IntPtr.Zero,0,out returned,IntPtr.Zero))return 0;error=Marshal.GetLastWin32Error(); } finally {CloseHandle(radio);} }while(BluetoothFindNextRadio(find,out radio)); } finally {BluetoothFindRadioClose(find);}
  return error;
 }
 [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIMMDeviceCollection {
  [PreserveSig] int GetCount(out uint count);
  [PreserveSig] int Item(uint index,out NcIMMDevice device);
 }
 [ComImport,Guid("2A07407E-6497-4A18-9787-32F79BD0D98F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIDeviceTopology {
  [PreserveSig] int GetConnectorCount(out uint count);
  [PreserveSig] int GetConnector(uint index,out NcIConnector connector);
 }
 [ComImport,Guid("9C2C4058-23F5-41DE-877A-DF3AF236A09E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIConnector {
  [PreserveSig] int GetType(out int type);
  [PreserveSig] int GetDataFlow(out int flow);
  [PreserveSig] int ConnectTo(NcIConnector connector);
  [PreserveSig] int Disconnect();
  [PreserveSig] int IsConnected([MarshalAs(UnmanagedType.Bool)] out bool connected);
  [PreserveSig] int GetConnectedTo(out NcIConnector connector);
  [PreserveSig] int GetConnectorIdConnectedTo([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetDeviceIdConnectedTo([MarshalAs(UnmanagedType.LPWStr)] out string id);
 }
 [StructLayout(LayoutKind.Sequential)] struct KsProperty { public Guid set;public uint id;public uint flags; }
 [ComImport,Guid("28F54685-06FD-11D2-B27A-00A0C9223196"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIKsControl {
  [PreserveSig] int KsProperty(ref KsProperty property,uint size,IntPtr data,uint dataSize,out uint returned);
 }
 static void Release(object value) {if(value!=null && Marshal.IsComObject(value))Marshal.ReleaseComObject(value);}
 public static string AudioFilters() {var list=new List<string>(); ReconnectAudio(null,list);return String.Join("\n",list);}
 static int ReconnectAudio(string address,List<string> diagnostics=null) {
  var enumerator=(NcIMMDeviceEnumerator)new NcMMDeviceEnumeratorComObject();NcIMMDeviceCollection collection=null;
  int failure=1168;bool requested=false;
  try {
   int hr=enumerator.EnumAudioEndpoints(0,15,out collection);if(hr!=0)return hr;
   uint count;collection.GetCount(out count);
   for(uint i=0;i<count;i++) {
    NcIMMDevice endpoint=null;object topology=null;
    try {
     if(collection.Item(i,out endpoint)!=0)continue;
     Guid topologyId=new Guid("2A07407E-6497-4A18-9787-32F79BD0D98F");
     if(endpoint.Activate(ref topologyId,23,IntPtr.Zero,out topology)!=0)continue;
     var graph=(NcIDeviceTopology)topology;uint connectors;if(graph.GetConnectorCount(out connectors)!=0)continue;
     for(uint j=0;j<connectors;j++) {
      NcIConnector connector=null;NcIMMDevice adapter=null;object control=null;
      try {
       if(graph.GetConnector(j,out connector)!=0)continue;
       string id;if(connector.GetDeviceIdConnectedTo(out id)!=0 || String.IsNullOrEmpty(id))continue;
       if(diagnostics!=null && (address==null || id.IndexOf(address.Replace(":",""),StringComparison.OrdinalIgnoreCase)>=0))diagnostics.Add(id);
       if(address==null || id.Replace(":","").Replace("-","").IndexOf(address.Replace(":","").Replace("-",""),StringComparison.OrdinalIgnoreCase)<0)continue;
       hr=enumerator.GetDevice(id,out adapter);if(hr!=0){failure=hr;continue;}
       Guid ksId=new Guid("28F54685-06FD-11D2-B27A-00A0C9223196");
       hr=adapter.Activate(ref ksId,23,IntPtr.Zero,out control);if(hr!=0){failure=hr;continue;}
       var property=new KsProperty {set=new Guid("7FA06C40-B8F6-4C7E-8556-E8C33A12E54D"),id=0,flags=1};uint returned;
       hr=((NcIKsControl)control).KsProperty(ref property,24,IntPtr.Zero,0,out returned);
       if(hr==0)requested=true;else failure=hr;
      } finally {Release(control);Release(adapter);Release(connector);}
     }
    } catch(COMException e) {failure=e.ErrorCode;} finally {Release(topology);Release(endpoint);}
   }
  } finally {Release(collection);Release(enumerator);}
  return requested?0:failure;
 }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class NcMMDeviceEnumeratorComObject { }
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIMMDeviceEnumerator {
 [PreserveSig] int EnumAudioEndpoints(int flow,int stateMask,out NcIMMDeviceCollection devices);
 [PreserveSig] int GetDefaultAudioEndpoint(int flow,int role,out NcIMMDevice device);
 [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id,out NcIMMDevice device);
 [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
 [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
}
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIMMDevice {
 [PreserveSig] int Activate(ref Guid iid,int clsCtx,IntPtr activationParams,[MarshalAs(UnmanagedType.IUnknown)] out object endpoint);
 [PreserveSig] int OpenPropertyStore(int access,out IntPtr properties);
 [PreserveSig] int GetId(out IntPtr id);
 [PreserveSig] int GetState(out int state);
}
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface NcIAudioEndpointVolume {
 [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
 [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
 [PreserveSig] int GetChannelCount(out uint count);
 [PreserveSig] int SetMasterVolumeLevel(float level,ref Guid context);
 [PreserveSig] int SetMasterVolumeLevelScalar(float level,ref Guid context);
 [PreserveSig] int GetMasterVolumeLevel(out float level);
 [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
}
[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 static NcBtDeviceV42 NewDevice() { return new NcBtDeviceV42 { size=(uint)Marshal.SizeOf(typeof(NcBtDeviceV42)), name=String.Empty }; }
 public static List<NcBtDeviceV42> Devices(bool scan) {
  var began=DateTime.UtcNow.AddSeconds(-2); var results=new List<NcBtDeviceV42>(); var query=new NcBtSearchV42 { size=(uint)Marshal.SizeOf(typeof(NcBtSearchV42)), authenticated=true, remembered=true, unknown=scan, connected=true, inquiry=scan, timeout=scan?(byte)1:(byte)0, radio=IntPtr.Zero };
  var item=NewDevice(); var find=BluetoothFindFirstDevice(ref query,ref item); if(find==IntPtr.Zero || find==new IntPtr(-1)) return results;
  try { do { BluetoothGetDeviceInfo(IntPtr.Zero,ref item); if(item.authenticated || item.remembered || item.connected || (scan && Seen(item)>=began)) results.Add(item); item=NewDevice(); } while(BluetoothFindNextDevice(find,ref item)); } finally { BluetoothFindDeviceClose(find); }
  return results;
 }
 public static DateTime Seen(NcBtDeviceV42 d) { try { var t=d.lastSeen; return new DateTime(t.year,t.month,t.day,t.hour,t.minute,t.second,t.milliseconds,DateTimeKind.Utc); } catch { return DateTime.MinValue; } }
 public static bool RadioAvailable() { var q=new RadioSearch {size=4}; IntPtr radio; var f=BluetoothFindFirstRadio(ref q,out radio); if(f==IntPtr.Zero)return false; CloseHandle(radio); BluetoothFindRadioClose(f); return true; }
 static ulong ParseAddress(string value) { return Convert.ToUInt64(value.Replace(":",String.Empty).Replace("-",String.Empty),16); }
 public static int Forget(string address) { var value=ParseAddress(address); return (int)BluetoothRemoveDevice(ref value); }
 static NcIAudioEndpointVolume Endpoint() { var enumerator=(NcIMMDeviceEnumerator)new NcMMDeviceEnumeratorComObject(); NcIMMDevice device; int hr=enumerator.GetDefaultAudioEndpoint(0,1,out device); if(hr!=0) Marshal.ThrowExceptionForHR(hr); Guid iid=new Guid("5CDF2C82-841E-4546-9722-0CF74078229A"); object endpoint; hr=device.Activate(ref iid,23,IntPtr.Zero,out endpoint); if(hr!=0) Marshal.ThrowExceptionForHR(hr); return (NcIAudioEndpointVolume)endpoint; }
 public static int GetVolume() { try { float level; int hr=Endpoint().GetMasterVolumeLevelScalar(out level); return hr==0?(int)Math.Round(level*100.0):-1; } catch { return -1; } }
 public static bool SetVolume(int percent) { try { percent=Math.Max(0,Math.Min(100,percent)); Guid context=Guid.Empty; return Endpoint().SetMasterVolumeLevelScalar(percent/100.0f,ref context)==0; } catch { return false; } }
 public static string Address(ulong value) { var text=value.ToString("X12"); return String.Join(":",new string[]{text.Substring(0,2),text.Substring(2,2),text.Substring(4,2),text.Substring(6,2),text.Substring(8,2),text.Substring(10,2)}); }
 public static string Kind(uint code) { switch((code>>8)&31) { case 1:return "Computer"; case 2:return "Phone"; case 4:return "Audio / video"; case 5:return "Peripheral"; case 6:return "Imaging"; case 7:return "Wearable"; default:return "Bluetooth device"; } }
}
'@
}
$operation='__OPERATION__'; $address='__ADDRESS__'; $passkey='__PASSKEY__'; $scan=$operation -eq 'scan'
if($operation -eq 'pair') { [NcBluetoothApiV46]::PairStart($address); Write-Output '__RC_BT_ACTION__STARTED'; return }
if($operation -eq 'pairStatus') { Write-Output ('__RC_BT_PAIR__'+[NcBluetoothApiV46]::PairStatus()); return }
if($operation -eq 'pairReply') { [NcBluetoothApiV46]::PairReply($passkey); return }
if($operation -eq 'connect') { $code=[NcBluetoothApiV46]::Connect($address); if($code -ne 0){throw "Connecting failed (Windows error $code). Keep the device switched on and disconnected from other machines, then retry."}; Write-Output '__RC_BT_ACTION__OK'; return }
if($operation -eq 'disconnect') { $code=[NcBluetoothApiV46]::Disconnect($address); if($code -ne 0){throw "Disconnect failed (Windows error $code). Pairing has been kept."}; Write-Output '__RC_BT_ACTION__OK'; return }
if($operation -eq 'forget') { $code=[NcBluetoothApiV46]::Forget($address); if($code -ne 0){throw "Removing pairing failed (Windows error $code)."}; Write-Output '__RC_BT_ACTION__OK'; return }
if($operation -eq 'trust' -or $operation -eq 'untrust') { Start-Process -FilePath 'explorer.exe' -ArgumentList 'ms-settings:bluetooth'; Write-Output '__RC_BT_ACTION__SETTINGS'; return }
if($operation -eq 'volume') { $percent=[int]$address; if(-not [NcBluetoothApiV46]::SetVolume($percent)){throw 'Windows audio volume could not be changed.'}; Write-Output '__RC_BT_ACTION__OK'; return }
$found=[NcBluetoothApiV46]::Devices($scan)
if($scan -or $operation -eq 'state') { $devices=@($found | ForEach-Object { $d=$_; $id=[NcBluetoothApiV46]::Address($d.address); @{id=$id;name=$d.name;kind=[NcBluetoothApiV46]::Kind([uint32]$d.deviceClass);paired=[bool]($d.authenticated -or $d.remembered);trusted=[bool]$d.authenticated;connected=[bool]$d.connected;signal=$null;battery=$null;seenAt=if($scan){[NcBluetoothApiV46]::Seen($d).ToString('o')}else{$null}} }); Write-Output ('__RC_BT_JSON__'+(ConvertTo-Json -InputObject @{available=[NcBluetoothApiV46]::RadioAvailable();adapter='';devices=$devices} -Depth 5 -Compress)); return }
$batteryByAddress=@{}
$batteryKey='{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2'
$addressPattern=(($found | ForEach-Object { [NcBluetoothApiV46]::Address($_.address).Replace(':','') } | Select-Object -Unique) -join '|')
$batteryNodes=if($addressPattern){@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -in @('Bluetooth','HIDClass') -and $_.InstanceId -match "(?i)$addressPattern" })}else{@()}
foreach($node in $batteryNodes) { try { $property=Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName $batteryKey -ErrorAction Stop; $raw=$property.Data; if($property.Type -ne 'Empty' -and $null -ne $raw -and "$raw" -match '^\s*\d{1,3}\s*$') { $level=[int]$raw; if($level -ge 1 -and $level -le 100) { $match=[regex]::Match($node.InstanceId,'(?i)([0-9A-F]{12})'); if($match.Success){$batteryByAddress[$match.Groups[1].Value.ToUpperInvariant()]=$level} } } } catch { } }
$devices=@($found | ForEach-Object { $d=$_; $cod=[uint32]$d.deviceClass; $id=[NcBluetoothApiV46]::Address($d.address); $battery=$batteryByAddress[$id.Replace(':','')]; @{id=$id;name=$d.name;kind=[NcBluetoothApiV46]::Kind($cod);paired=[bool]($d.authenticated -or $d.remembered);trusted=[bool]$d.authenticated;connected=[bool]$d.connected;signal=$null;battery=$battery} })
$adapters=@(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Radio|Adapter|Enumerator' -or ($_.InstanceId -match '^(USB|PCI)\\' -and $_.FriendlyName -match 'Bluetooth') -or $_.InstanceId -match 'BTH\\MS_BTHBRB' } | ForEach-Object { $_.FriendlyName })
$radio=if($adapters.Count){$adapters -join ', '}else{'Bluetooth radio unavailable'}
$volume=[NcBluetoothApiV46]::GetVolume(); if($volume -lt 0){$volume=$null}
$data=@{available=($radio -ne 'Bluetooth radio unavailable');adapter=$radio;powered=$null;outputVolume=$volume;outputName='Windows default audio output';devices=$devices}
Write-Output ('__RC_BT_JSON__'+(ConvertTo-Json -InputObject $data -Depth 5 -Compress))
''';

class BluetoothDevicesService {
  static Future<bool> _isWindows(Device device, SshSession session) async {
    if (device.shellStyle == 'windows') return true;
    if (device.shellStyle != 'auto') return false;
    final result = await session.run(
      'uname -s',
      timeout: const Duration(seconds: 5),
    );
    return !const {
      'Linux',
      'Darwin',
      'FreeBSD',
    }.contains(utf8.decode(result, allowMalformed: true).trim());
  }

  static Future<BluetoothSnapshot> load(
    Device device,
    SshSession session, {
    bool scan = false,
    bool fast = false,
  }) async {
    _checkSession(device, session);
    if (await _isWindows(device, session)) {
      final bytes = await session.runPowerShell(
        windowsBluetoothScript
            .replaceAll(
              '__OPERATION__',
              scan
                  ? 'scan'
                  : fast
                  ? 'state'
                  : 'list',
            )
            .replaceAll('__ADDRESS__', '')
            .replaceAll('__PASSKEY__', ''),
        desktop: !fast && !scan,
        label: scan ? 'Scan Bluetooth devices' : 'Read Bluetooth devices',
        timeout: Duration(seconds: scan ? 20 : 12),
      );
      return parseWindowsBluetoothSnapshot(
        utf8.decode(bytes, allowMalformed: true),
      );
    }
    final script = linuxBluetoothScript.replaceAll(
      '__SCAN__',
      scan ? 'yes' : 'no',
    );
    final bytes = await session.run(
      script,
      timeout: Duration(seconds: scan ? 20 : 12),
    );
    return parseLinuxBluetoothSnapshot(
      utf8.decode(bytes, allowMalformed: true),
    );
  }

  static Stream<BluetoothSnapshot> scan(
    Device device,
    SshSession session, {
    Duration duration = const Duration(seconds: 12),
  }) async* {
    final windows = await _isWindows(device, session);
    final deadline = DateTime.now().add(duration);
    if (windows) {
      yield await load(device, session, fast: true);
      do {
        yield await load(device, session, scan: true);
      } while (DateTime.now().isBefore(deadline));
      return;
    }
    // Keep the discovery client alive while sampling BlueZ's cache. Its discovery
    // lease ends when this owned channel closes, without stopping other clients.
    final scanner = await session.client!.execute(
      'NO_COLOR=1 TERM=dumb bluetoothctl --timeout ${duration.inSeconds + 3} scan on',
    );
    final errors = StringBuffer();
    final out = scanner.stdout.listen(
      (bytes) => errors.write(utf8.decode(bytes, allowMalformed: true)),
    );
    final err = scanner.stderr.listen(
      (bytes) => errors.write(utf8.decode(bytes, allowMalformed: true)),
    );
    try {
      do {
        yield await load(device, session);
        if (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      } while (DateTime.now().isBefore(deadline));
      if (RegExp(
        r'Failed|No default controller|NotReady|NotAuthorized',
        caseSensitive: false,
      ).hasMatch(errors.toString())) {
        throw StateError(errors.toString());
      }
    } finally {
      scanner.close();
      await out.cancel();
      await err.cancel();
    }
  }

  static Future<String> perform(
    Device device,
    SshSession session, {
    required String action,
    required String id,
    String passkey = '',
    bool audioDevice = false,
    Future<String?> Function(String kind, String code)? pairingPrompt,
  }) async {
    _checkSession(device, session);
    if (!RegExp(r'^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$').hasMatch(id)) {
      throw ArgumentError('Invalid Bluetooth device address.');
    }
    if (passkey.length > 16 || !RegExp(r'^\d*$').hasMatch(passkey)) {
      throw ArgumentError('Invalid Bluetooth passkey.');
    }
    final windows = await _isWindows(device, session);
    final address = id.replaceAll('-', ':');
    if (windows && audioDevice && (action == 'pair' || action == 'repair')) {
      try {
        await session.runPowerShell(
          windowsAudioPairingScript
              .replaceAll('__ADDRESS__', address)
              .replaceAll('__OPERATION__', action),
          desktop: true,
          label: 'Bluetooth $action',
          timeout: const Duration(seconds: 12),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (DateTime.now().isBefore(deadline)) {
          final bytes = await session.runPowerShell(
            "Write-Output ('__RC_BT_PAIR__'+[NcModernAudioPairV42]::Status())",
            desktop: true,
            label: 'Bluetooth pairing status',
            timeout: const Duration(seconds: 12),
          );
          final fields = utf8
              .decode(bytes)
              .trim()
              .split('__RC_BT_PAIR__')
              .last
              .split('|');
          if (fields.first == 'done') {
            if (fields[1] != '0') {
              throw StateError(
                '${action == 'repair' ? 'Repair' : 'Pairing'} failed: ${fields[1]}. Put the device in pairing mode and retry.',
              );
            }
            await perform(device, session, action: 'connect', id: id);
            return '__RC_BT_ACTION__OK';
          }
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        throw TimeoutException(
          'Pairing timed out. Put the device in pairing mode and retry.',
        );
      } finally {
        await session.runPowerShell(
          "if ('NcModernAudioPairV42' -as [type]) { [NcModernAudioPairV42]::Cancel() }",
          desktop: true,
          label: 'Finish Bluetooth pairing',
          timeout: const Duration(seconds: 12),
        );
      }
    }
    if (action == 'repair') {
      if (!windows) {
        throw ArgumentError('Repair is available for Windows devices.');
      }
      await perform(device, session, action: 'forget', id: id);
      try {
        await perform(
          device,
          session,
          action: 'pair',
          id: id,
          pairingPrompt: pairingPrompt,
        );
        await perform(device, session, action: 'connect', id: id);
        return '__RC_BT_ACTION__OK';
      } catch (error) {
        throw StateError(
          'Repair did not finish. The old pairing was removed. '
          'Keep the device in pairing mode and use Pair to retry. $error',
        );
      }
    }
    if (windows) {
      Future<String> request(String operation, [String reply = '']) async {
        final bytes = await session.runPowerShell(
          (operation == 'pairStatus'
                  ? "Write-Output ('__RC_BT_PAIR__'+[NcBluetoothApiV46]::PairStatus())"
                  : operation == 'pairReply'
                  ? "[NcBluetoothApiV46]::PairReply('__PASSKEY__')"
                  : windowsBluetoothScript)
              .replaceAll('__OPERATION__', operation)
              .replaceAll('__ADDRESS__', address)
              .replaceAll('__PASSKEY__', reply),
          desktop: true,
          label: 'Bluetooth $operation',
          timeout: Duration(seconds: operation == 'connect' ? 35 : 12),
        );
        return utf8.decode(bytes, allowMalformed: true).trim();
      }

      final result = await request(action);
      if (action == 'pair') {
        try {
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          bool completed = false;
          while (DateTime.now().isBefore(deadline)) {
            final status = await request('pairStatus');
            final fields = status.split('__RC_BT_PAIR__').last.split('|');
            if (fields.first == 'done') {
              if (fields[1] != '0') {
                throw StateError(
                  'Pairing failed (Windows error ${fields[1]}). Put the device in pairing mode and retry.',
                );
              }
              completed = true;
              break;
            }
            if (fields.length > 3 && fields[2].isNotEmpty) {
              final answer = await pairingPrompt?.call(fields[2], fields[3]);
              if (answer == null) throw StateError('Pairing cancelled.');
              if (!RegExp(r'^(yes|[0-9]{1,16})$').hasMatch(answer)) {
                throw ArgumentError('Invalid pairing response.');
              }
              await request('pairReply', answer);
            }
            await Future<void>.delayed(const Duration(milliseconds: 350));
          }
          if (!completed) {
            throw TimeoutException(
              'Pairing timed out. Put the device in pairing mode and retry.',
            );
          }
        } finally {
          await request('pairReply', 'cancel');
        }
      }
      return result;
    }
    final command = switch (action) {
      'pair' => linuxBluetoothPairCommand.replaceAll('__ADDRESS__', address),
      'forget' => 'bluetoothctl remove $address',
      'connect' => 'bluetoothctl connect $address',
      'disconnect' => 'bluetoothctl disconnect $address',
      'trust' => 'bluetoothctl trust $address',
      'untrust' => 'bluetoothctl untrust $address',
      _ => throw ArgumentError('Unsupported Bluetooth action: $action'),
    };
    final script =
        """
set -e
command -v bluetoothctl >/dev/null 2>&1 || { echo 'bluetoothctl is not installed. Install bluez first.' >&2; exit 1; }
$command
""";
    final bytes = await session.run(
      script,
      timeout: const Duration(seconds: 35),
    );
    final output = utf8.decode(bytes, allowMalformed: true).trim();
    final cleanOutput = output.replaceAll(
      RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'),
      '',
    );
    if (RegExp(
      r'(?:^\s*(?:Failed|Error|No default controller)\b|Failed to register agent|No agent is registered|Failed to pair)',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(cleanOutput)) {
      throw StateError(
        action == 'pair'
            ? 'Pairing failed. Put the headphones into pairing mode, then retry. Most headphones do not need a PIN.'
            : cleanOutput,
      );
    }
    return cleanOutput;
  }

  static Future<String> setVolume(
    Device device,
    SshSession session,
    int percent,
  ) async {
    _checkSession(device, session);
    if (percent < 0 || percent > 100) {
      throw RangeError.range(percent, 0, 100);
    }
    if (await _isWindows(device, session)) {
      final script = windowsBluetoothScript
          .replaceAll('__OPERATION__', 'volume')
          .replaceAll('__ADDRESS__', '$percent')
          .replaceAll('__PASSKEY__', '');
      final bytes = await session.runPowerShell(
        script,
        desktop: true,
        label: 'Set audio volume',
      );
      return utf8.decode(bytes, allowMalformed: true).trim();
    }
    final script =
        """
set -e
if command -v wpctl >/dev/null 2>&1; then wpctl set-volume @DEFAULT_AUDIO_SINK@ $percent%
elif command -v pactl >/dev/null 2>&1; then pactl set-sink-volume @DEFAULT_SINK@ $percent%
elif command -v amixer >/dev/null 2>&1; then amixer set Master $percent%
else echo 'No supported audio volume control is installed.' >&2; exit 1; fi
""";
    final bytes = await session.run(
      script,
      timeout: const Duration(seconds: 10),
    );
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}

BluetoothSnapshot parseWindowsBluetoothSnapshot(String output) {
  const marker = '__RC_BT_JSON__';
  final line = const LineSplitter()
      .convert(output)
      .lastWhere((item) => item.startsWith(marker), orElse: () => '');
  if (line.isEmpty) {
    throw StateError(
      output.trim().isEmpty
          ? 'No Bluetooth information was returned.'
          : output.trim(),
    );
  }
  final data = jsonDecode(line.substring(marker.length)) as Map;
  return BluetoothSnapshot(
    available: _asBool(data['available']),
    adapter: data['adapter']?.toString() ?? '',
    powered: _asNullableBool(data['powered']),
    outputVolume: _asInt(data['outputVolume']),
    outputName: data['outputName']?.toString(),
    devices: (data['devices'] as List? ?? [])
        .whereType<Map>()
        .map(BluetoothDeviceInfo.fromMap)
        .toList(),
  );
}

BluetoothSnapshot parseLinuxBluetoothSnapshot(String output) {
  var available = false;
  var powered = false;
  var adapter = '';
  int? volume;
  String? outputName;
  final devices = <BluetoothDeviceInfo>[];
  String decode(String value) {
    try {
      return utf8.decode(base64Decode(value));
    } on FormatException {
      return value;
    }
  }

  for (final line in const LineSplitter().convert(output)) {
    final fields = line.split('\t');
    if (fields.firstOrNull == '__RC_BT_ERROR__') {
      throw StateError(
        fields.length > 1 ? decode(fields[1]) : 'Bluetooth is unavailable.',
      );
    }
    if (fields.firstOrNull == '__RC_BT_STATE__' && fields.length >= 3) {
      adapter = decode(fields[1]);
      available = adapter.isNotEmpty;
      powered = fields[2].trim().toLowerCase() == 'yes';
    } else if (fields.firstOrNull == '__RC_BT_VOLUME__' && fields.length >= 3) {
      volume = int.tryParse(fields[1]);
      outputName = decode(fields[2]);
    } else if (fields.firstOrNull == '__RC_BT_DEVICE__' && fields.length >= 9) {
      devices.add(
        BluetoothDeviceInfo(
          id: fields[1],
          name: decode(fields[2]),
          kind: decode(fields[3]),
          paired: _asBool(fields[4]),
          trusted: _asBool(fields[5]),
          connected: _asBool(fields[6]),
          signal: _asInt(fields[7]),
          battery: _asInt(fields[8]),
        ),
      );
    }
  }
  return BluetoothSnapshot(
    available: available,
    adapter: adapter.isEmpty ? 'Bluetooth radio unavailable' : adapter,
    powered: powered,
    devices: devices,
    outputVolume: volume,
    outputName: outputName,
  );
}

void _checkSession(Device device, SshSession session) {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device to manage Bluetooth.');
  }
}

bool _asBool(Object? value) =>
    value == true ||
    value?.toString().toLowerCase() == 'true' ||
    value?.toString().toLowerCase() == 'yes';

bool? _asNullableBool(Object? value) => value == null ? null : _asBool(value);

int? _asInt(Object? value) => switch (value) {
  null => null,
  num number => number.toInt(),
  _ => int.tryParse(value.toString()),
};
