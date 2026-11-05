import '../models/device.dart';

// Reachability fallback ends before SSH host-key verification/authentication.
// A reachable local endpoint must pass those checks; failures never silently
// select a different machine.
Future<T> connectDeviceHosts<T>({
  required Device device,
  required Future<T> Function(String host, Duration timeout) local,
  required Future<T> Function(String host) internet,
}) async {
  if (device.localHost.trim().isNotEmpty) {
    try {
      return await local(device.localHost.trim(), const Duration(seconds: 3));
    } catch (_) {
      // A local address may be unavailable when the phone is away from home.
    }
  }
  return internet(device.host.trim());
}
