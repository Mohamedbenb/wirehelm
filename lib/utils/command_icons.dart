import 'package:flutter/material.dart';

const commandIcons = <String, IconData>{
  'terminal': Icons.terminal,
  'display': Icons.desktop_windows,
  'monitor': Icons.monitor,
  'power': Icons.power_settings_new,
  'lock': Icons.lock,
  'restart': Icons.restart_alt,
  'sleep': Icons.bedtime,
  'settings': Icons.settings,
  'play': Icons.play_arrow,
  'folder': Icons.folder,
  'wifi': Icons.wifi,
};

IconData commandIcon(String name) {
  return commandIcons[name] ?? Icons.terminal;
}