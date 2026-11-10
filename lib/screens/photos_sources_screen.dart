import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customization/local_customization.dart';

class PhotosSourcesScreen extends StatefulWidget {
  const PhotosSourcesScreen({super.key});

  @override
  State<PhotosSourcesScreen> createState() => _PhotosSourcesScreenState();
}

class _PhotosSourcesScreenState extends State<PhotosSourcesScreen>
    with WidgetsBindingObserver {
  static const _rules = {
    'messengerNames': 'Messenger creation files',
    'facebookNames': 'Facebook image filenames',
    'whatsappNames': 'WhatsApp filenames',
  };
  static const _folders = {
    'cameraFolder': ('Camera', 'DCIM/Camera'),
    'whatsappFolder': ('WhatsApp', 'Pictures/WhatsApp'),
    'videosFolder': ('Videos', 'Movies/Videos'),
  };
  final _paths = {
    for (final key in _folders.keys) key: TextEditingController(),
  };
  final Map<String, dynamic> _draft = {};
  Map<String, dynamic>? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _paths.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _loadDraft(Map<String, dynamic> data) {
    for (final key in ['enabled', 'development', ..._rules.keys]) {
      _draft[key] = data[key];
    }
    for (final entry in _paths.entries) {
      entry.value.text = data[entry.key] as String? ?? '';
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      if (mounted) _error = error.message ?? 'Photos Sources is unavailable.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _perform(() async {
    final data = await LocalCustomization.call('photosSourcesStatus');
    if (!mounted) return;
    if (_status == null) _loadDraft(data);
    _status = data;
  });

  Future<void> _save() => _perform(() async {
    FocusScope.of(context).unfocus();
    final data = await LocalCustomization.call('savePhotosSources', {
      'config': jsonEncode({
        ..._draft,
        for (final entry in _paths.entries) entry.key: entry.value.text,
      }),
    });
    if (!mounted) return;
    _loadDraft(data);
    _status = data;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved. Reopen Collections to apply.')),
    );
  });

  Widget _compatibility(Map<String, dynamic> data) {
    final version = data['photosVersion'] as String? ?? '';
    final supported = data['supported'] == true;
    final reportedAt = data['reportedAt'] as int? ?? 0;
    final download = switch (data['downloadState']) {
      'waiting' => 'Waiting for Android',
      'running' => 'Downloading',
      'paused' => 'Paused',
      'complete' => 'Complete',
      _ => null,
    };
    final compatibility = switch ((version, supported, data['scope'])) {
      ('', _, _) => 'Google Photos is unavailable.',
      (_, false, _) => 'This Google Photos version is unsupported.',
      (_, _, 'missing') => 'Enable Google Photos in Wirehelm’s Vector scope.',
      _ when reportedAt == 0 =>
        'Open Google Photos to check the Sources integration.',
      _ => 'The Sources integration has reported in.',
    };
    final reportTime = DateTime.fromMillisecondsSinceEpoch(reportedAt);
    final format = MaterialLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(compatibility),
            if (version.isNotEmpty) Text('Google Photos $version'),
            if (reportedAt > 0) ...[
              Text(
                'Last report ${format.formatShortDate(reportTime)} '
                '${format.formatTimeOfDay(TimeOfDay.fromDateTime(reportTime))}',
              ),
              Text(
                data['backgroundReady'] == true
                    ? 'Background downloads available'
                    : 'Background downloads unavailable',
              ),
            ],
            if (download != null)
              Text(
                'Last reported download · $download\n'
                '${data['done']} of ${data['total']} downloaded'
                ' · ${data['skipped']} skipped',
              ),
            Wrap(
              spacing: 12,
              children: [
                if (version.isNotEmpty)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() async {
                            await LocalCustomization.call('openGooglePhotos');
                          }),
                    child: const Text('Open Google Photos'),
                  ),
                if (data['scope'] == 'missing')
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _perform(() async {
                            await LocalCustomization.call('frameworkModule');
                          }),
                    child: const Text('Open Vector'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final heading = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos Sources'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (status != null) ...[
            _compatibility(status),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show Sources in Collections'),
              subtitle: const Text(
                'Google Photos handles browsing and downloads. Turning this '
                'off hides the entry. Current downloads continue.',
              ),
              value: _draft['enabled'] == true,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _draft['enabled'] = value;
                    }),
            ),
            const SizedBox(height: 12),
            Text('Filename rules', style: heading),
            const Text('Use known filenames to help identify the source.'),
            for (final entry in _rules.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                value: _draft[entry.key] == true,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _draft[entry.key] = value;
                      }),
              ),
            DropdownButtonFormField<String>(
              initialValue: _draft['development'] as String?,
              decoration: const InputDecoration(
                labelText: 'Development group',
                helperText:
                    'Controls the group for development-related images.',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'existing',
                  child: Text('Keep existing preference'),
                ),
                DropdownMenuItem(value: 'on', child: Text('Show group')),
                DropdownMenuItem(value: 'off', child: Text('Hide group')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _draft['development'] = value;
                    }),
            ),
            const SizedBox(height: 24),
            Text('Preferred device folders', style: heading),
            const Text(
              'Use paths relative to internal storage. Leave a field blank for '
              'automatic suggestions. You choose the destination in Photos.',
            ),
            for (final entry in _folders.entries)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _paths[entry.key],
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: entry.value.$1,
                    hintText: entry.value.$2,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save settings'),
            ),
          ],
        ],
      ),
    );
  }
}
