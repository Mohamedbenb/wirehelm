import 'dart:convert';
import 'dart:typed_data';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

class DeviceInformation {
  final Map<String, String> system;
  final List<Map<String, String>> adapters;
  final List<String> bluetoothDevices;
  final List<String> peripherals;
  DeviceInformation(
    this.system,
    this.adapters, {
    this.bluetoothDevices = const [],
    this.peripherals = const [],
  });
}

const linuxInformationScript = r'''
printf '__RC_INFO__\thostname\t%s\n' "$(hostname)"
printf '__RC_INFO__\tuser\t%s\n' "$(id -un)"
printf '__RC_INFO__\tos\t%s\n' "$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"')"
printf '__RC_INFO__\tkernel\t%s\n' "$(uname -sr)"
printf '__RC_INFO__\tarchitecture\t%s\n' "$(uname -m)"
printf '__RC_INFO__\tuptime\t%s\n' "$(uptime -p 2>/dev/null || uptime)"
printf '__RC_INFO__\tcpu\t%s\n' "$(awk -F: '/model name|Hardware/ {sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
printf '__RC_INFO__\tmemory\t%s\n' "$(awk '/MemTotal:/ {printf "%.1f GiB",$2/1048576}' /proc/meminfo 2>/dev/null)"
printf '__RC_INFO__\tdisk\t%s\n' "$(df -Ph / | awk 'NR==2 {print $4 " free of " $2 " (" $5 " used)"}')"
for dir in /sys/class/net/*; do
  [ -d "$dir" ] || continue
  name=${dir##*/}
  mac=$(cat "$dir/address" 2>/dev/null)
  state=$(cat "$dir/operstate" 2>/dev/null)
  ips=$(ip -o addr show dev "$name" 2>/dev/null | awk '/inet/ {printf "%s ",$4}')
  route=$(ip -4 route show default 2>/dev/null | awk -v dev="$name" '$0 ~ " dev "dev {print; exit}')
  internet=no; [ -n "$route" ] && internet=yes
  printf '__RC_NIC__\t%s\t%s\t%s\t%s\t%s\n' "$name" "$mac" "$state" "$ips" "$internet"
done
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetoothctl devices Connected 2>/dev/null | sed 's/^/__RC_BT__\t/'
fi
if command -v lsusb >/dev/null 2>&1; then
  lsusb 2>/dev/null | sed 's/^/__RC_PERIPHERAL__\t/'
fi
''';

const windowsInformationScript = r'''
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$os=Get-CimInstance Win32_OperatingSystem
$pc=Get-CimInstance Win32_ComputerSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$defaultRoute=Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric,InterfaceMetric | Select-Object -First 1
$nics=@(Get-NetAdapter | ForEach-Object {
 $a=$_; $ips=@(Get-NetIPAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
 @{name=$a.Name; mac=$a.MacAddress; status=[string]$a.Status; ips=($ips -join ', '); internet=($null -ne $defaultRoute -and $a.ifIndex -eq $defaultRoute.InterfaceIndex)}
})
$bluetooth=@(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { $_.FriendlyName } | Where-Object { $_ } | Select-Object -Unique)
$peripherals=@(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.Class -in @('USB','HIDClass') -and $_.Status -eq 'OK' } | ForEach-Object { $_.FriendlyName } | Where-Object { $_ } | Select-Object -Unique -First 30)
$disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$data=@{system=@{hostname=$env:COMPUTERNAME; user=[Security.Principal.WindowsIdentity]::GetCurrent().Name; os=$os.Caption; kernel=$os.Version; architecture=$os.OSArchitecture; cpu=$cpu.Name; model=($pc.Manufacturer+' '+$pc.Model); memory=('{0:N1} GiB' -f ($pc.TotalPhysicalMemory/1GB)); uptime=((Get-Date)-$os.LastBootUpTime).ToString(); disk=('{0:N1} GiB free of {1:N1} GiB' -f ($disk.FreeSpace/1GB),($disk.Size/1GB))}; adapters=$nics; bluetoothDevices=$bluetooth; peripherals=$peripherals}
Write-Output ('__RC_INFORMATION_JSON__'+(ConvertTo-Json -InputObject $data -Depth 5 -Compress))
''';

DeviceInformation parseDeviceInformation(String output) {
  const marker = '__RC_INFORMATION_JSON__';
  final lines = const LineSplitter().convert(output);
  final jsonLines = lines.where((line) => line.startsWith(marker));
  if (jsonLines.isNotEmpty) {
    final data = jsonDecode(
      jsonLines.last.substring(marker.length),
    ) as Map<String, dynamic>;
    Map<String, String> strings(Map map) =>
        map.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    return DeviceInformation(
      strings(data['system'] as Map),
      (data['adapters'] as List? ?? []).map((a) => strings(a as Map)).toList(),
      bluetoothDevices: (data['bluetoothDevices'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
      peripherals: (data['peripherals'] as List? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
  final system = <String, String>{};
  final adapters = <Map<String, String>>[];
  final bluetoothDevices = <String>[];
  final peripherals = <String>[];
  for (final line in lines) {
    final fields = line.split('\t');
    if (fields.length >= 3 && fields.first == '__RC_INFO__') {
      system[fields[1]] = fields.sublist(2).join('\t');
    }
    if (fields.length >= 5 && fields.first == '__RC_NIC__') {
      adapters.add({
        'name': fields[1],
        'mac': fields[2],
        'status': fields[3],
        'ips': fields[4],
        'internet': fields.length > 5 && fields[5].trim() == 'yes'
            ? 'true'
            : 'false',
      });
    }
    if (fields.length >= 2 && fields.first == '__RC_BT__') {
      bluetoothDevices.add(fields.sublist(1).join('\t'));
    }
    if (fields.length >= 2 && fields.first == '__RC_PERIPHERAL__') {
      peripherals.add(fields.sublist(1).join('\t'));
    }
  }
  if (system.isEmpty) {
    throw StateError(
      'The device did not return information.\n${output.trim()}',
    );
  }
  return DeviceInformation(
    system,
    adapters,
    bluetoothDevices: bluetoothDevices,
    peripherals: peripherals,
  );
}

Future<DeviceInformation> fetchDeviceInformation(
  Device device,
  SshSession session,
) async {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device to load live information.');
  }
  var windows = device.shellStyle == 'windows';
  if (device.shellStyle == 'auto') {
    final probe = utf8
        .decode(
          await session.run('uname -s', timeout: const Duration(seconds: 5)),
          allowMalformed: true,
        )
        .trim();
    windows = !['Linux', 'Darwin', 'FreeBSD'].contains(probe);
  }
  Uint8List bytes;
  if (windows) {
    const bootstrap =
        r"$ErrorActionPreference='Stop'; try { $s=[Console]::In.ReadLine(); & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)))) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }";
    final encoded = base64Encode(
      bootstrap.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
    );
    bytes = await session.run(
      timeout: const Duration(seconds: 20),
      'powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded',
      input: Uint8List.fromList(
        utf8.encode(
          [base64Encode(utf8.encode(windowsInformationScript)), '\n'].join(),
        ),
      ),
    );
  } else {
    bytes = await session.run(
      linuxInformationScript,
      timeout: const Duration(seconds: 15),
    );
  }
  return parseDeviceInformation(utf8.decode(bytes, allowMalformed: true));
}
