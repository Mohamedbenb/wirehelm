import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../transport/tsnet_client.dart';
import 'app_updates_settings_screen.dart';
import 'identities_screen.dart';
import 'tailscale_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettings,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.system_update),
                    title: const Text('App updates'),
                    subtitle: const Text(
                      'Install updates or test download speed',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AppUpdatesSettingsScreen(),
                      ),
                    ),
                  ),
                ),
                _SettingsHeading('Connections'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: const Text('SSH identities'),
                        subtitle: const Text('Manage keys for your devices'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const IdentitiesScreen(),
                          ),
                        ),
                      ),
                      if (TsnetClient.supported) ...[
                        const Divider(height: 1, indent: 56, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.cloud_outlined),
                          title: const Text('Tailscale'),
                          subtitle: const Text('Remote connection and sign-in'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TailscaleScreen(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _SettingsHeading('Appearance'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<ThemeMode>(
                          initialValue: appSettings.themeMode,
                          decoration: const InputDecoration(labelText: 'Theme'),
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) appSettings.setThemeMode(value);
                          },
                        ),
                        const SizedBox(height: 20),
                        Text('Accent color', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 12),
                        const Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _AccentChoice(
                              name: 'blue',
                              color: Color(0xFF1565C0),
                            ),
                            _AccentChoice(
                              name: 'teal',
                              color: Color(0xFF00796B),
                            ),
                            _AccentChoice(
                              name: 'green',
                              color: Color(0xFF2E7D32),
                            ),
                            _AccentChoice(
                              name: 'orange',
                              color: Color(0xFFEF6C00),
                            ),
                            _AccentChoice(
                              name: 'red',
                              color: Color(0xFFC62828),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingsHeading('Device list'),
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    title: const Text('Show connection details'),
                    subtitle: const Text(
                      'Username, host and port on device cards',
                    ),
                    value: appSettings.showConnectionEndpoint,
                    onChanged: appSettings.setShowConnectionEndpoint,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  final String label;

  const _SettingsHeading(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _AccentChoice extends StatelessWidget {
  final String name;
  final Color color;

  const _AccentChoice({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    final selected = appSettings.accent == name;
    return Semantics(
      label: '$name accent',
      selected: selected,
      button: true,
      child: Tooltip(
        message: '${name[0].toUpperCase()}${name.substring(1)}',
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => appSettings.setAccent(name),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
