import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'transport/tsnet_client.dart';

import 'screens/local_customization_screen.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Termux terminal components v0.118.3',
    ], await rootBundle.loadString('assets/licenses/termux.txt'));
  });
  await appSettings.load();

  runApp(const RemoteControlApp());
  if (TsnetClient.supported) {
    unawaited(
      () async {
        if (await TsnetClient.instance.useTsnet()) {
          await TsnetClient.instance.start();
        }
      }().catchError((Object _) {}),
    );
  }
}

class RemoteControlApp extends StatelessWidget {
  const RemoteControlApp({super.key});

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color accent,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );

    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,

      scaffoldBackgroundColor: dark
          ? const Color(0xFF121212)
          : const Color(0xFFF7F7FA),

      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF121212)
            : const Color(0xFFF7F7FA),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF1D1D20) : Colors.white,
        elevation: dark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? scheme.primaryContainer : accent,
          foregroundColor: dark ? scheme.onPrimaryContainer : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark ? scheme.primaryContainer : accent,
        foregroundColor: dark ? scheme.onPrimaryContainer : Colors.white,
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF19191C) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF68686F) : const Color(0xFFB8B8C0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent;
          }

          return null;
        }),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF1D1D20) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettings,
      builder: (context, _) {
        final accent = appSettings.accentColor;

        return MaterialApp(
          debugShowCheckedModeBanner: false,

          title: 'Wirehelm',

          themeMode: appSettings.themeMode,

          theme: _buildTheme(brightness: Brightness.light, accent: accent),

          darkTheme: _buildTheme(brightness: Brightness.dark, accent: accent),

          home: const LocalCustomizationScreen(),
        );
      },
    );
  }
}
