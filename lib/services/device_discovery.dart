import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';
import '../transport/tsnet_client.dart';
import '../transport/tsnet_socket.dart';

class DiscoveredDevice {
  final String name, host, source, os, lastSeen;
  final int port;
  final bool? online;
  bool? reachable, ssh;
  DiscoveredDevice({
    required this.name,
    required this.host,
    required this.source,
    this.port = 22,
    this.os = '',
    this.lastSeen = '',
    this.online,
  });
}

class DiscoverySnapshot {
  bool searched = false;
  String? error;
  final List<DiscoveredDevice> devices = [];
}

bool isOwnPhonePeer(Map<String, dynamic> peer, Map<String, dynamic> info) {
  if (peer['os'] != 'android') return false;
  final name = (peer['name'] as String? ?? '').toLowerCase();
  final deviceName = (info['deviceName'] as String? ?? '').toLowerCase();
  if (deviceName.isNotEmpty && name == deviceName) return true;
  // This app's earlier A-series Termux test used this exact naming convention.
  final model = RegExp(
    r'^sm-a(\d{2})',
    caseSensitive: false,
  ).firstMatch(info['model'] as String? ?? '');
  return model != null && name == 'remote-control-a${model.group(1)}-test';
}

Set<String> localDeviceAddresses(Map<String, dynamic> snapshot) => {
  for (final item in snapshot['interfaces'] as List? ?? [])
    for (final address in item['addresses'] as List? ?? [])
      (address as String).split('/').first,
};

List<String> localScanHosts(Map<String, dynamic> snapshot) {
  if (snapshot['wifi'] != true) return [];
  final interface = (snapshot['interfaces'] as List? ?? []).where(
    (i) => i['name'] == snapshot['defaultInterface'],
  );
  for (final item in interface) {
    for (final value in item['addresses'] as List) {
      final parts = (value as String).split('/');
      final bytes = parts.first.split('.').map(int.tryParse).toList();
      if (bytes.length != 4 ||
          bytes.any((b) => b == null || b < 0 || b > 255)) {
        continue;
      }
      final prefix = int.tryParse(parts.last);
      if (prefix == null || prefix < 1 || prefix > 30) continue;
      final effective = prefix < 24 ? 24 : prefix;
      final address = bytes.fold<int>(0, (a, b) => (a << 8) | b!);
      final mask = (0xffffffff << (32 - effective)) & 0xffffffff;
      final network = address & mask;
      final end = network | (~mask & 0xffffffff);
      return [
        for (var ip = network + 1; ip < end; ip++)
          if (ip != address)
            [ip >> 24 & 255, ip >> 16 & 255, ip >> 8 & 255, ip & 255].join('.'),
      ];
    }
  }
  return [];
}

class DeviceDiscovery {
  bool cancelled = false;
  final List<DiscoveredDevice> devices = [];
  final Set<String> ownAddresses = {};
  final void Function() changed;
  DeviceDiscovery(this.changed);

  void add(DiscoveredDevice device) {
    if (cancelled || ownAddresses.contains(device.host)) return;
    final old = devices.where(
      (d) =>
          d.source == device.source &&
          d.host == device.host &&
          d.port == device.port,
    );
    if (old.isEmpty) devices.add(device);
    devices.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    changed();
  }

  Future<void> tailnet() async {
    final status = await TsnetClient.instance.status();
    ownAddresses.addAll(status.ips);
    final info = jsonDecode(
      (await TsnetClient.channel.invokeMethod<String>('lanInfo'))!,
    ) as Map<String, dynamic>;
    final peers = await TsnetClient.instance.peers();
    for (final peer in peers) {
      final ips = (peer['ips'] as List).cast<String>();
      if (ips.isEmpty ||
          ips.any(ownAddresses.contains) ||
          isOwnPhonePeer(peer, info)) {
        continue;
      }
      add(
        DiscoveredDevice(
          name: peer['name'] as String,
          host: ips.first,
          source: 'Tailscale',
          os: peer['os'] as String? ?? '',
          online: peer['online'] as bool?,
          lastSeen: peer['lastSeen'] as String? ?? '',
        ),
      );
    }
  }

  Future<void> lan(List<Device> saved) async {
    final info = await TsnetClient.channel.invokeMethod<String>('lanInfo');
    ownAddresses.addAll(
      localDeviceAddresses(jsonDecode(info!) as Map<String, dynamic>),
    );
    final text = await TsnetClient.channel.invokeMethod<String>('discoverLan');
    for (final item in jsonDecode(text!) as List) {
      final sshService = (item['service'] as String).contains('_ssh.');
      add(
        DiscoveredDevice(
          name: item['name'] as String,
          host: item['host'] as String,
          source: 'LAN',
          port: sshService ? item['port'] as int : 22,
        ),
      );
    }
    for (final device in saved.where((d) => d.localHost.isNotEmpty)) {
      add(
        DiscoveredDevice(
          name: device.name,
          host: device.localHost,
          port: device.port,
          source: 'LAN',
          os: device.shellStyle,
        ),
      );
    }
  }

  Future<void> scanLan() async {
    final text = await TsnetClient.channel.invokeMethod<String>('lanInfo');
    final snapshot = jsonDecode(text!) as Map<String, dynamic>;
    if (snapshot['wifi'] != true) {
      throw StateError('Connect to Wi-Fi to scan the LAN.');
    }
    final hosts = localScanHosts(snapshot);
    if (hosts.isEmpty) throw StateError('No IPv4 Wi-Fi subnet is available.');
    var next = 0;
    await Future.wait(
      List.generate(16, (_) async {
        while (!cancelled && next < hosts.length) {
          final host = hosts[next++];
          final candidate = DiscoveredDevice(
            name: host,
            host: host,
            source: 'LAN',
          );
          await probe(candidate);
          if (candidate.reachable == true) add(candidate);
        }
      }),
    );
  }

  Future<void> probe(DiscoveredDevice device) async {
    if (cancelled) return;
    var connected = false;
    try {
      if (device.source == 'Tailscale') {
        final socket = await TsnetSocket.connect(device.host, device.port);
        connected = true;
        device.reachable = true;
        try {
          final bytes = await socket.stream.first.timeout(
            const Duration(seconds: 2),
          );
          device.ssh = utf8
              .decode(bytes, allowMalformed: true)
              .startsWith('SSH-');
        } finally {
          socket.destroy();
        }
      } else {
        final socket = await Socket.connect(
          device.host,
          device.port,
          timeout: const Duration(milliseconds: 700),
        );
        connected = true;
        device.reachable = true;
        try {
          final bytes = await socket.first.timeout(
            const Duration(milliseconds: 700),
          );
          device.ssh = utf8
              .decode(bytes, allowMalformed: true)
              .startsWith('SSH-');
        } finally {
          socket.destroy();
        }
      }
    } catch (_) {
      device.reachable = connected;
      device.ssh = false;
    }
    if (!cancelled) changed();
  }

  Future<void> checkAll() async {
    var next = 0;
    final snapshot = List<DiscoveredDevice>.of(devices);
    await Future.wait(
      List.generate(4, (_) async {
        while (!cancelled && next < snapshot.length) {
          await probe(snapshot[next++]);
        }
      }),
    );
  }
}
