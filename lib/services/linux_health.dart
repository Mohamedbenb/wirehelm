import 'dart:convert';

import '../models/device.dart';
import '../ssh/ssh_session.dart';

const _healthMarker = '__RC_LINUX_HEALTH__';

class LinuxHealthReport {
  final Map<String, String> values;

  const LinuxHealthReport(this.values);

  String value(String key, [String fallback = 'unknown']) =>
      values[key] ?? fallback;

  bool get pcReachable =>
      value('pc_ssh') == 'reachable' || value('pc_ping') == 'reachable';
  bool get directLan => value('pc_route_kind') == 'direct_lan';

  bool get hasUndervoltage {
    final raw = values['throttled'];
    if (raw == null || !raw.startsWith('0x')) return false;
    final bits = int.tryParse(raw.substring(2), radix: 16);
    return bits != null && (bits & ((1 << 0) | (1 << 16))) != 0;
  }

  bool get hasThrottling {
    final raw = values['throttled'];
    if (raw == null || !raw.startsWith('0x')) return false;
    final bits = int.tryParse(raw.substring(2), radix: 16);
    const flags =
        (1 << 1) | (1 << 2) | (1 << 3) | (1 << 17) | (1 << 18) | (1 << 19);
    return bits != null && (bits & flags) != 0;
  }
}

String buildLinuxHealthScript({
  required String peerHost,
  required int peerPort,
}) {
  final hostBase64 = base64Encode(utf8.encode(peerHost));
  final port = peerPort.clamp(1, 65535);
  return r'''
set +e
emit() { printf '__RC_LINUX_HEALTH__\t%s\t%s\n' "$1" "$2"; }
pc_host=$(printf '%s' 'HOST_BASE64' | base64 -d 2>/dev/null)
pc_port=PC_PORT
route=$(ip -4 route show default 2>/dev/null | head -n 1)
gateway=$(printf '%s\n' "$route" | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1);exit}}')
iface=$(printf '%s\n' "$route" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
local_ip=$(printf '%s\n' "$route" | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
[ -n "$local_ip" ] || local_ip=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk 'NR==1{split($4,a,"/");print a[1]}')
emit gateway "${gateway:-none}"
emit adapter "${iface:-none}"
emit local_ip "${local_ip:-none}"
if [ -n "$gateway" ] && command -v ping >/dev/null 2>&1 && ping -c 1 -W 1 "$gateway" >/dev/null 2>&1; then router=reachable; elif [ -n "$gateway" ]; then router=no_ping_reply; else router=no_default_route; fi
emit router "$router"
if command -v getent >/dev/null 2>&1 && getent hosts example.com >/dev/null 2>&1; then dns=reachable; else dns=unavailable; fi
emit dns "$dns"
if command -v curl >/dev/null 2>&1 && curl -fsS --connect-timeout 3 --max-time 5 https://connectivitycheck.gstatic.com/generate_204 -o /dev/null >/dev/null 2>&1; then internet=reachable
elif command -v wget >/dev/null 2>&1 && wget -q -T 5 -O /dev/null https://connectivitycheck.gstatic.com/generate_204 >/dev/null 2>&1; then internet=reachable
else internet=unavailable; fi
emit internet "$internet"
if [ -n "$pc_host" ]; then
  pc_ip=$(getent ahostsv4 "$pc_host" 2>/dev/null | awk 'NR==1 {print $1}')
  [ -n "$pc_ip" ] || pc_ip="$pc_host"
  peer_route=$(ip -4 route get "$pc_ip" 2>/dev/null | head -n 1)
  if [ -n "$peer_route" ]; then peer_iface=$(printf '%s\n' "$peer_route" | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}'); peer_src=$(printf '%s\n' "$peer_route" | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}'); else peer_iface=none; peer_src=none; fi
  emit pc_host "$pc_host"
  emit pc_ip "$pc_ip"
  emit pc_route "${peer_iface:-none} · ${peer_src:-none}"
  peer_gateway=$(printf '%s\n' "$peer_route" | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1);exit}}')
  peer_kind=unknown
  if [ -n "$peer_route" ]; then
    case "$peer_iface:$pc_ip" in
      tailscale*:*|tun*:*|wg*:*) peer_kind=overlay ;;
      *) if [ -n "$peer_gateway" ]; then peer_kind=routed; else peer_kind=direct_lan; fi ;;
    esac
  fi
  emit pc_route_kind "$peer_kind"
  emit pc_gateway "${peer_gateway:-none}"
  if [ -d "/sys/class/net/$peer_iface/wireless" ]; then emit pc_link Wi-Fi; else emit pc_link "${peer_iface:-unknown}"; fi
  peer_cidr=$(ip -o -4 addr show dev "$peer_iface" 2>/dev/null | awk -v src="$peer_src" '{split($4,a,"/");if(a[1]==src){print $4;exit}}')
  emit pc_cidr "${peer_cidr:-unavailable}"
  if command -v ping >/dev/null 2>&1 && ping -c 1 -W 1 "$pc_host" >/dev/null 2>&1; then peer_ping=reachable; else peer_ping=no_ping_reply; fi
  emit pc_ping "$peer_ping"
  if command -v nc >/dev/null 2>&1 && nc -z -w 2 "$pc_host" "$pc_port" >/dev/null 2>&1; then peer_ssh=reachable
  elif command -v timeout >/dev/null 2>&1 && timeout 3 bash -c 'cat < /dev/null > /dev/tcp/$1/$2' _ "$pc_host" "$pc_port" >/dev/null 2>&1; then peer_ssh=reachable
  else peer_ssh=unreachable; fi
  emit pc_ssh "$peer_ssh"
  peer_broadcast=$(ip -o -4 addr show dev "$peer_iface" 2>/dev/null | awk -v src="$peer_src" '{split($4,a,"/");if(a[1]==src){for(i=1;i<=NF;i++) if($i=="brd"){print $(i+1);exit}}}')
  emit pc_broadcast "${peer_broadcast:-unavailable}"
else
  emit pc_host none
  emit pc_route not_selected
  emit pc_ping not_selected
  emit pc_ssh not_selected
  emit pc_broadcast unavailable
fi
if command -v wakeonlan >/dev/null 2>&1; then wol_tool=installed; else wol_tool=missing; fi
emit wol_tool "$wol_tool"
temp=$(for file in /sys/class/thermal/thermal_zone*/temp; do [ -r "$file" ] || continue; raw=$(cat "$file" 2>/dev/null); case "$raw" in ''|*[!0-9]*) continue;; esac; awk -v n="$raw" 'BEGIN {printf "%.1f\n", n/1000}'; done | sort -nr | head -n 1)
emit cpu_temp "${temp:-unavailable}"
if command -v vcgencmd >/dev/null 2>&1; then throttled=$(vcgencmd get_throttled 2>/dev/null | sed -n 's/^throttled=//p'); else throttled=unavailable; fi
emit throttled "${throttled:-unavailable}"
mem_free=$(awk '/MemAvailable:/ {printf "%.0f MiB", $2/1024}' /proc/meminfo 2>/dev/null)
emit memory_free "${mem_free:-unavailable}"
disk=$(df -P / 2>/dev/null | awk 'NR==2 {print $4 " KiB free · " $5 " used"}')
disk_used=$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
emit disk "${disk:-unavailable}"
emit disk_used "${disk_used:-unavailable}"
emit uptime "$(uptime -p 2>/dev/null || uptime 2>/dev/null)"
for tool in ffmpeg scrot grim gnome-screenshot bluetoothctl nmcli lsusb wakeonlan etherwake; do
  if command -v "$tool" >/dev/null 2>&1; then found=yes; else found=no; fi
  emit "tool_$tool" "$found"
done
video_access=missing_device
for device in /dev/video*; do [ -e "$device" ] || continue; video_access=permission_denied; if [ -r "$device" ] && [ -w "$device" ]; then video_access=available; break; fi; done
emit video_access "$video_access"
audio_access=missing_device
if [ -d /dev/snd ]; then audio_access=permission_denied; if [ -r /dev/snd ] && [ -w /dev/snd ]; then audio_access=available; fi; fi
emit audio_access "$audio_access"
'''
      .replaceFirst('HOST_BASE64', hostBase64)
      .replaceFirst('PC_PORT', '$port');
}

LinuxHealthReport parseLinuxHealth(String output) {
  final values = <String, String>{};
  for (final line in const LineSplitter().convert(output)) {
    final fields = line.trimRight().split('\t');
    if (fields.length >= 3 && fields[0] == _healthMarker) {
      values[fields[1]] = fields.sublist(2).join('\t').trim();
    }
  }
  if (values.isEmpty) {
    throw StateError(
      'The Pi did not return health information.\n${output.trim()}',
    );
  }
  return LinuxHealthReport(values);
}

Future<LinuxHealthReport> fetchLinuxHealth({
  required Device device,
  required SshSession session,
  Device? peer,
}) async {
  if (!session.isConnected || session.deviceId != device.id) {
    throw StateError('Connect to this device first.');
  }
  final host = peer == null
      ? ''
      : peer.localHost.trim().isNotEmpty
      ? peer.localHost.trim()
      : peer.host.trim();
  final script = buildLinuxHealthScript(
    peerHost: host,
    peerPort: peer?.port ?? 22,
  );
  final output = await session.run(
    script,
    timeout: const Duration(seconds: 25),
  );
  return parseLinuxHealth(utf8.decode(output, allowMalformed: true));
}
