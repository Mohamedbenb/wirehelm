import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'app_theme';
  static const _accentKey = 'app_accent';
  static const _showEndpointKey = 'show_connection_endpoint';

  ThemeMode _themeMode = ThemeMode.system;
  String _accent = 'blue';
  bool _showConnectionEndpoint = true;

  ThemeMode get themeMode => _themeMode;
  String get accent => _accent;
  bool get showConnectionEndpoint => _showConnectionEndpoint;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final theme = prefs.getString(_themeKey);

    switch (theme) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;

      case 'dark':
        _themeMode = ThemeMode.dark;
        break;

      default:
        _themeMode = ThemeMode.system;
    }

    _accent = prefs.getString(_accentKey) ?? 'blue';

    _showConnectionEndpoint =
        prefs.getBool(_showEndpointKey) ?? true;
  }

  Future<void> setThemeMode(
    ThemeMode mode,
  ) async {
    _themeMode = mode;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _themeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );

    notifyListeners();
  }

  Future<void> setAccent(
    String accent,
  ) async {
    _accent = accent;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _accentKey,
      accent,
    );

    notifyListeners();
  }

  Future<void> setShowConnectionEndpoint(
    bool value,
  ) async {
    _showConnectionEndpoint = value;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _showEndpointKey,
      value,
    );

    notifyListeners();
  }

  Color get accentColor {
    switch (_accent) {
      case 'teal':
        return const Color(0xFF00796B);

      case 'green':
        return const Color(0xFF2E7D32);

      case 'orange':
        return const Color(0xFFEF6C00);

      case 'red':
        return const Color(0xFFC62828);

      default:
        return const Color(0xFF1565C0);
    }
  }
}

final appSettings = AppSettings();