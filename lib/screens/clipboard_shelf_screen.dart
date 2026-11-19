import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customization/local_customization.dart';
import '../models/device.dart';
import '../services/device_storage.dart';
import '../services/remote_clipboard.dart';
import '../ssh/ssh_session_manager.dart';
import 'devices_screen.dart';

final _clipboardShelfEvents = const EventChannel(
  'remote_control/clipboard_shelf_events',
).receiveBroadcastStream();

class ClipboardShelfScreen extends StatefulWidget {
  const ClipboardShelfScreen({super.key});
  @override
  State<ClipboardShelfScreen> createState() => _ClipboardShelfScreenState();
}

class _ClipboardShelfScreenState extends State<ClipboardShelfScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic> data = {};
  String query = '';
  String? error;
  bool busy = false, pinned = false, sending = false;
  bool get blocked => busy || sending;
  int generation = 0;
  Timer? debounce;
  Timer? eventRefresh;
  StreamSubscription<dynamic>? shelfEvents;
  Map<String, dynamic> get policy =>
      Map<String, dynamic>.from(data['policy'] as Map? ?? {});
  List<Map<String, dynamic>> get entries => (data['entries'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    shelfEvents = _clipboardShelfEvents.listen((_) {
      eventRefresh?.cancel();
      eventRefresh = Timer(const Duration(milliseconds: 150), () {
        if (mounted &&
            !blocked &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            (ModalRoute.of(context)?.isCurrent ?? false)) {
          unawaited(load());
        }
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    debounce?.cancel();
    eventRefresh?.cancel();
    unawaited(shelfEvents?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(load());
  }

  Future<bool> load({
    String op = 'list',
    Map<String, dynamic> args = const {},
  }) async {
    if (sending) return false;
    final ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await LocalCustomization.call('clipboardShelf', {
        'op': op,
        'query': query,
        'pinned': pinned,
        ...args,
      });
      if (!mounted || ticket != generation) return false;
      setState(() => data = result);
      return true;
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = '$e');
      return false;
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<bool> configure(Map<String, dynamic> changes) => load(
    op: 'configure',
    args: {
      'config': jsonEncode({...policy, ...changes}),
    },
  );
  String when(dynamic stamp) {
    final d = DateTime.fromMillisecondsSinceEpoch((stamp as num? ?? 0).toInt());
    final l = MaterialLocalizations.of(context);
    return '${l.formatShortDate(d)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

  Future<void> copy(Map<String, dynamic> e) async {
    if (await load(op: 'copy', args: {'id': e['id']}) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. Paste in the app you choose.')),
      );
    }
  }

  Future<void> sendToPc(Map<String, dynamic> entry) async {
    if (blocked) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final devices = await DeviceStorage().loadDevices();
      if (!mounted) return;
      var manage = false;
      final target = await showModalBottomSheet<Device>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                const ListTile(
                  title: Text('Send to PC clipboard'),
                  subtitle: Text(
                    'Select a connected computer. Only this item is sent.',
                  ),
                ),
                Expanded(
                  child: devices.isEmpty
                      ? const Center(
                          child: Text(
                            'No saved computers. Add one in Devices.',
                          ),
                        )
                      : ListView(
                          children: devices.map((d) {
                            final online =
                                sshSessions
                                    .existingSession(d.id)
                                    ?.isConnected ==
                                true;
                            return ListTile(
                              leading: const Icon(Icons.computer),
                              title: Text(d.name),
                              subtitle: Text(
                                online
                                    ? 'Connected'
                                    : 'Connect in Devices first',
                              ),
                              enabled: online,
                              onTap: () => Navigator.pop(c, d),
                            );
                          }).toList(),
                        ),
                ),
                TextButton(
                  onPressed: () {
                    manage = true;
                    Navigator.pop(c);
                  },
                  child: const Text('Open Devices'),
                ),
              ],
            ),
          ),
        ),
      );
      if (target == null) {
        if (manage && mounted) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DevicesScreen()),
          );
        }
        return;
      }
      final session = sshSessions.existingSession(target.id);
      if (session == null || !session.isConnected) {
        throw StateError('The PC disconnected. Reconnect in Devices.');
      }
      final full = await LocalCustomization.call('clipboardShelf', {
        'op': 'detail',
        'id': entry['id'],
      });
      final image = full['kind'] == 'image';
      final bytes = image
          ? await File(full['image'] as String).readAsBytes()
          : Uint8List.fromList(utf8.encode(full['text'] as String));
      await sendClipboardToPc(
        target,
        session,
        bytes,
        image: image,
        mime: full['mime'] as String? ?? 'text/plain',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied to ${target.name}’s clipboard.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> addToEdge() async {
    if (blocked) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await LocalCustomization.call('addClipboardEdgeShortcut');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['edgeEnabled'] == false
                  ? 'Added to Favorites. Enable Edge panel in UI features to use it.'
                  : result['added'] == false
                  ? 'Clipboard shelf is already in Edge panel Favorites.'
                  : 'Added to Edge panel Favorites.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> detail(Map<String, dynamic> e) async {
    try {
      final full = await LocalCustomization.call('clipboardShelf', {
        'op': 'detail',
        'id': e['id'],
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(e['app'] as String? ?? 'Saved clip'),
          content: SingleChildScrollView(
            child: full['kind'] == 'image'
                ? Image.file(
                    File(full['thumb'] as String),
                    errorBuilder: (_, _, _) => const Text('Image unavailable'),
                  )
                : SelectableText(full['text'] as String? ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                unawaited(copy(e));
              },
              child: const Text('Copy'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> clear() async {
    bool includePins = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Clear clipboard history?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Deletes saved shelf entries. The current Android clipboard is left as it is.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include pinned clips'),
                value: includePins,
                onChanged: (v) => update(() => includePins = v == true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear history'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await load(op: 'clear', args: {'includePins': includePins});
    }
  }

  Future<void> exclusions() async {
    try {
      final result = await LocalCustomization.call('clipboardApps');
      if (!mounted) return;
      final apps = <String, String>{
        for (final a in result['apps'] as List? ?? [])
          a['package'] as String: a['label'] as String,
      };
      final excluded = Set<String>.from(policy['excluded'] as List? ?? []);
      for (final p in excluded) {
        apps.putIfAbsent(p, () => p);
      }
      String filter = '', custom = '';
      String? validation;
      final saved = await showDialog<Set<String>>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) {
            final visible =
                apps.keys
                    .where(
                      (p) => '$p ${apps[p]}'.toLowerCase().contains(
                        filter.toLowerCase(),
                      ),
                    )
                    .toList()
                  ..sort(
                    (a, b) => apps[a]!.toLowerCase().compareTo(
                      apps[b]!.toLowerCase(),
                    ),
                  );
            return AlertDialog(
              title: const Text('Excluded apps'),
              content: SizedBox(
                width: 440,
                height: 480,
                child: Column(
                  children: [
                    const Text(
                      'Checked apps are never saved. Adding an exclusion does not delete older entries.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Find an app',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => update(() => filter = v),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (c, i) {
                          final p = visible[i];
                          return CheckboxListTile(
                            title: Text(apps[p]!),
                            subtitle: Text(p),
                            value: excluded.contains(p),
                            onChanged: (v) => update(() {
                              if (v == true) {
                                excluded.add(p);
                              } else {
                                excluded.remove(p);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Or enter a package name',
                        errorText: validation,
                      ),
                      onChanged: (v) => custom = v.trim(),
                      onSubmitted: (_) {
                        update(() {
                          if (RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$')
                              .hasMatch(custom)) {
                            apps[custom] = custom;
                            excluded.add(custom);
                            validation = null;
                            filter = custom;
                          } else {
                            validation = 'Example: com.example.app';
                          }
                        });
                      },
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Press Enter to add a package.'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, excluded),
                  child: const Text('Save exclusions'),
                ),
              ],
            );
          },
        ),
      );
      if (saved != null && mounted) {
        await configure({'excluded': saved.toList()..sort()});
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clips = entries, p = policy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard shelf'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: blocked ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear history',
            onPressed: blocked ? null : clear,
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<String>(
            tooltip: 'Shelf options',
            enabled: !blocked,
            onSelected: (_) => addToEdge(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edge', child: Text('Add to Edge panel')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (blocked) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('Save copied items'),
            subtitle: const Text(
              'Capture new copies while unlocked. Stored only on this phone.',
            ),
            value: p['enabled'] == true,
            onChanged: blocked ? null : (v) => configure({'enabled': v}),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              (data['observerAt'] as num? ?? 0) > 0
                  ? 'SystemUI observer connected · hook ${data['observerVersion']}. Tap a clip to copy; hold it to view.'
                  : 'Capture needs Wirehelm’s updated SystemUI hook. After activation, copy something to connect the observer.',
            ),
          ),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('History and privacy'),
            children: [
              SwitchListTile(
                title: const Text('Save images'),
                subtitle: const Text(
                  'Supported images up to 8 MB. Animated images keep their original file.',
                ),
                value: p['images'] != false,
                onChanged: blocked ? null : (v) => configure({'images': v}),
              ),
              SwitchListTile(
                title: const Text('Automatically copy screenshots'),
                subtitle: const Text(
                  'New screenshots go to the shelf and Android clipboard. Uses System UI as the source; app exclusions do not identify what is visible in a screenshot.',
                ),
                value: p['screenshots'] != false,
                onChanged: blocked || p['images'] == false
                    ? null
                    : (v) => configure({'screenshots': v}),
              ),
              ListTile(
                title: const Text('Recent clips'),
                trailing: DropdownButton<int>(
                  value: (p['limit'] as num? ?? 100).toInt(),
                  items: [50, 100, 200]
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                      .toList(),
                  onChanged: blocked
                      ? null
                      : (v) {
                          if (v != null) unawaited(configure({'limit': v}));
                        },
                ),
              ),
              ListTile(
                title: const Text('Keep recent clips for'),
                trailing: DropdownButton<int>(
                  value: (p['days'] as num? ?? 7).toInt(),
                  items: [1, 7, 30]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text('$v ${v == 1 ? 'day' : 'days'}'),
                        ),
                      )
                      .toList(),
                  onChanged: blocked
                      ? null
                      : (v) {
                          if (v != null) unawaited(configure({'days': v}));
                        },
                ),
              ),
              ListTile(
                title: const Text('Excluded apps'),
                subtitle: Text(
                  '${(p['excluded'] as List? ?? []).length} packages excluded',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: blocked ? null : exclusions,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Clips marked sensitive are always skipped. Some apps may not mark private content: exclude those apps yourself. Pinned clips do not expire (up to 25). Images share a 64 MB budget. Expired entries are cleaned on the next copy or shelf access. Pausing capture keeps existing history.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search text or source package',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              query = v;
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) unawaited(load());
              });
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Pinned only'),
              selected: pinned,
              onSelected: blocked
                  ? null
                  : (v) {
                      setState(() => pinned = v);
                      unawaited(load());
                    },
            ),
          ),
          if (clips.isEmpty && !blocked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
              child: Text(
                query.isNotEmpty || pinned
                    ? 'No matching saved clips.'
                    : p['enabled'] == true
                    ? 'Copy text or a supported image in another app to start your shelf.'
                    : 'Enable capture to save new clips. Existing clipboard content is not imported.',
              ),
            ),
          ...clips.map(
            (e) => Card(
              key: ValueKey(e['id']),
              child: InkWell(
                onTap: blocked ? null : () => copy(e),
                onLongPress: blocked ? null : () => detail(e),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${e['app']} · ${when(e['at'])}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: e['pinned'] == true ? 'Unpin' : 'Pin',
                            onPressed: blocked
                                ? null
                                : () => load(
                                    op: 'pin',
                                    args: {
                                      'id': e['id'],
                                      'value': e['pinned'] != true,
                                    },
                                  ),
                            icon: Icon(
                              e['pinned'] == true
                                  ? Icons.bookmark_outline_rounded
                                  : Icons.bookmark_border_rounded,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete clip',
                            onPressed: blocked
                                ? null
                                : () =>
                                      load(op: 'delete', args: {'id': e['id']}),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      if (e['kind'] == 'image')
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(e['thumb'] as String),
                            height: 140,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Text('Saved image unavailable'),
                          ),
                        )
                      else
                        Text(
                          e['text'] as String? ?? '',
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      TextButton.icon(
                        onPressed: blocked ? null : () => sendToPc(e),
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: const Text('Send to PC'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
