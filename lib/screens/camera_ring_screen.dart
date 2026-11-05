import 'dart:convert';

import 'package:flutter/material.dart';

import '../customization/local_customization.dart';

class CameraRingScreen extends StatefulWidget {
  const CameraRingScreen({super.key});
  @override
  State<CameraRingScreen> createState() => _CameraRingScreenState();
}

class _CameraRingScreenState extends State<CameraRingScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> _config = {};
  Map<String, dynamic> _state = {};
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true, _saving = false, _dirty = false;
  String? _error;
  List<Map<String, dynamic>> get _rules => ((_config['apps'] as List?) ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final value = await LocalCustomization.call('cameraRingState');
      if (mounted) setState(() => _state = value);
    } catch (_) {
      // Preserve the editable draft if the status transport is temporarily unavailable.
    }
  }

  Future<void> _load() async {
    try {
      final data = await LocalCustomization.call('cameraRingState');
      final apps = await LocalCustomization.call('notificationApps');
      if (!mounted) return;
      setState(() {
        _state = data;
        _config = Map<String, dynamic>.from(data['config'] as Map);
        _apps = ((apps['apps'] as List?) ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _edit(String key, dynamic value) => setState(() {
    _config[key] = value;
    _dirty = true;
  });
  Future<void> _save({bool test = false, bool ambient = false}) async {
    if (_saving) return;
    if (_config['enabled'] == true && _rules.isEmpty) {
      setState(
        () => _error = 'Choose at least one app before enabling the ring.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await LocalCustomization.call('applyCameraRing', {
        'config': jsonEncode(_config),
      });
      if (!mounted) return;
      setState(() {
        _state = data;
        _dirty = false;
      });
      if (test) {
        await LocalCustomization.call('testCameraRing', {'ambient': ambient});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ambient
                    ? 'Lock normally now. Ambient entry is tested for up to 30 seconds; stock AOD content may appear.'
                    : 'Lock the phone normally to see the ring. Test ends after 30 seconds.',
              ),
              duration: Duration(seconds: 8),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopTest() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await LocalCustomization.call('stopCameraRingTest');
      await _refreshStatus();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _label(String pkg) =>
      _apps
          .where((a) => a['package'] == pkg)
          .map((a) => '${a['label']}')
          .firstOrNull ??
      pkg;
  Widget _icon(String pkg) {
    final icon = _apps
        .where((a) => a['package'] == pkg)
        .map((a) => a['icon'] as String?)
        .firstOrNull;
    return icon == null
        ? const Icon(Icons.apps)
        : Image.memory(base64Decode(icon), width: 36, height: 36);
  }

  Color _color(String value) =>
      Color(int.parse('FF${value.substring(1)}', radix: 16));
  Future<void> _chooseApps() async {
    final selected = _rules.map((a) => a['package'] as String).toSet();
    String query = '';
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final filtered = _apps
              .where(
                (a) => '${a['label']} ${a['package']}'.toLowerCase().contains(
                  query.toLowerCase(),
                ),
              )
              .toList();
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Notification apps',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search apps',
                    ),
                    onChanged: (v) => update(() => query = v),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final app = filtered[i],
                            pkg = filtered[i]['package'] as String;
                        return CheckboxListTile(
                          value: selected.contains(pkg),
                          secondary: _icon(pkg),
                          title: Text('${app['label']}'),
                          subtitle: Text(pkg),
                          onChanged: (value) => update(() {
                            if (value == true && selected.length < 64) {
                              selected.add(pkg);
                            } else {
                              selected.remove(pkg);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: Text('Use ${selected.length} apps'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    final old = {for (final app in _rules) app['package']: app};
    _edit('apps', [
      for (final pkg in picked)
        old[pkg] ?? {'package': pkg, 'priority': 3, 'color': '#FFFFFF'},
    ]);
  }

  Future<void> _chooseColor(int index) async {
    final rules = _rules;
    String custom = rules[index]['color'] as String;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_label(rules[index]['package'] as String)} color'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final hex in [
                  '#FFFFFF',
                  '#FF5252',
                  '#FFAB40',
                  '#FFFF00',
                  '#69F0AE',
                  '#40C4FF',
                  '#B388FF',
                  '#FF80AB',
                ])
                  InkWell(
                    onTap: () => Navigator.pop(context, hex),
                    child: CircleAvatar(
                      backgroundColor: _color(hex),
                      radius: 18,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: custom,
              onChanged: (v) => custom = v,
              maxLength: 7,
              decoration: const InputDecoration(
                labelText: 'Hex color',
                hintText: '#FFFFFF',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = custom.trim().toUpperCase();
              if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(v)) {
                Navigator.pop(context, v);
              }
            },
            child: const Text('Use color'),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      rules[index]['color'] = value;
      _edit('apps', rules);
    }
  }

  Widget _slider(
    String title,
    String key,
    double fallback,
    double min,
    double max,
    int divisions,
    String suffix,
  ) {
    final value = ((_config[key] as num?)?.toDouble() ?? fallback)
        .clamp(min, max)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: ${value.toStringAsFixed(key == 'thickness' ? 1 : 0)}$suffix',
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: _saving
              ? null
              : (v) => _edit(key, key == 'thickness' ? v : v.round()),
        ),
      ],
    );
  }

  String _statusLabel() {
    final raw = '${_state['status'] ?? ''}';
    final state = RegExp(r'(?:^|,)state=([^,]+)').firstMatch(raw)?.group(1);
    if (state == 'showing') {
      final pkg = RegExp(r',winner=([^,]+)').firstMatch(raw)?.group(1);
      final priority = RegExp(r',priority=(\d+)').firstMatch(raw)?.group(1);
      return pkg == 'test'
          ? 'AOD test active'
          : 'Showing ${_label(pkg ?? '')} · priority $priority';
    }
    return switch (state) {
      'disabled' => 'Ring is off',
      'screen awake' => 'Ready for Always-on Display',
      'no matching notifications' =>
        'Waiting for notifications from selected apps',
      'waiting for AOD' => 'Waiting for Always-on Display',
      'portrait only' => 'Available in portrait orientation',
      'unavailable' =>
        'Ring unavailable. Check Customization health for details.',
      _ => 'Waiting for the SystemUI connection',
    };
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final preview = rules.isEmpty
        ? '#FFFFFF'
        : rules.reduce(
                (a, b) =>
                    (a['priority'] as int) >= (b['priority'] as int) ? a : b,
              )['color']
              as String;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification ring'),
        actions: [
          TextButton(
            onPressed: _loading || _saving || !_dirty ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable notification ring'),
                  subtitle: const Text(
                    'Around the camera, only while the phone is dozing.',
                  ),
                  value: _config['enabled'] == true,
                  onChanged: _saving ? null : (v) => _edit('enabled', v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use ring with Always-on Display off'),
                  subtitle: const Text(
                    'Request native ambient display while selected notifications are waiting. It stops when they are cleared and leaves the Android AOD setting unchanged. Ambient display can increase battery use.',
                  ),
                  value: _config['ambientOnDemand'] == true,
                  onChanged: _saving
                      ? null
                      : (v) => _edit('ambientOnDemand', v),
                ),
                if (_state['aodEnabled'] != true &&
                    _config['ambientOnDemand'] != true)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Always-on Display is off. Enable the option above or Android Always-on Display to show the ring while asleep.',
                          ),
                          TextButton(
                            onPressed: () =>
                                LocalCustomization.call('openDisplaySettings'),
                            child: const Text('Open display settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_state['supported'] != true)
                  const Text('This SystemUI build has not been validated.'),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(
                        color: _color(preview).withValues(
                          alpha:
                              ((_config['intensity'] as num?)?.toDouble() ??
                                  100) /
                              100,
                        ),
                        width: (_config['thickness'] as num?)?.toDouble() ?? 3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Appearance preview. Actual brightness also depends on the phone's AOD brightness.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _slider('Thickness', 'thickness', 3, 1, 8, 14, ' dp'),
                _slider('Intensity', 'intensity', 100, 10, 100, 18, '%'),
                _slider(
                  'Fade duration (up and down)',
                  'intervalMs',
                  2500,
                  1000,
                  10000,
                  18,
                  ' ms',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include ongoing notifications'),
                  subtitle: const Text(
                    'Includes foreground services and persistent notifications.',
                  ),
                  value: _config['includeOngoing'] == true,
                  onChanged: _saving ? null : (v) => _edit('includeOngoing', v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Apps and priority',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : _chooseApps,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const Text(
                  '5 is highest. The highest-priority pending app wins; equal priorities use the newest notification. Clearing it reveals the next app.',
                ),
                if (rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: OutlinedButton.icon(
                      onPressed: _chooseApps,
                      icon: const Icon(Icons.apps),
                      label: const Text('Choose apps'),
                    ),
                  ),
                for (int i = 0; i < rules.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _icon(rules[i]['package'] as String),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _label(rules[i]['package'] as String),
                                ),
                              ),
                              IconButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        final list = _rules..removeAt(i);
                                        _edit('apps', list);
                                      },
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Text('Priority'),
                              const SizedBox(width: 12),
                              DropdownButton<int>(
                                value: rules[i]['priority'] as int,
                                items: [
                                  for (int n = 1; n <= 5; n++)
                                    DropdownMenuItem(
                                      value: n,
                                      child: Text('$n'),
                                    ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          final list = _rules;
                                          list[i]['priority'] = v;
                                          _edit('apps', list);
                                        }
                                      },
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => _chooseColor(i),
                                icon: Icon(
                                  Icons.circle,
                                  color: _color(rules[i]['color'] as String),
                                ),
                                label: const Text('Color'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(test: true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Save and test on AOD for 30 seconds'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stops showing when the phone wakes or matching notifications are removed. It does not wake the screen or hold a wake lock; blinking may pause during deep sleep. Portrait, current-user apps only.',
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ambient-entry experiment',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          'With Always-on display OFF, save and start this test, then lock normally. It requests native ambient display once and schedules one expiry alarm for 30 seconds after starting. Stock clock and other AOD content may appear. This is not the automatic ring-only mode; your AOD setting is unchanged.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(test: true, ambient: true),
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Save and test ambient entry'),
                        ),
                        TextButton(
                          onPressed: _saving ? null : _stopTest,
                          child: const Text('Stop test'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _statusLabel(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
