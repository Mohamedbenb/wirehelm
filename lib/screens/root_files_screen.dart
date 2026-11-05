import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/root_files.dart';
import '../utils/file_size.dart';
import '../utils/root_file_presentation.dart';
import '../utils/root_folder_guide.dart';

class RootFilesScreen extends StatefulWidget {
  const RootFilesScreen({super.key});
  @override
  State<RootFilesScreen> createState() => _RootFilesScreenState();
}

class _RootFilesScreenState extends State<RootFilesScreen>
    with WidgetsBindingObserver {
  String _path = '/', _filter = '';
  String? _scope, _error;
  DateTime? _expires;
  bool _busy = false, _hidden = false, _unlockable = false, _truncated = false;
  bool _advancedUnlockable = false, _advancedMode = false;
  List<Map<String, dynamic>> _entries = [];
  Timer? _timer;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _breadcrumbs = ScrollController();
  final _positions = <String, double>{};
  final _lease = ValueNotifier<DateTime?>(null);
  String _sort = 'name';
  bool _descending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load('/');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expires != null && !DateTime.now().isBefore(_expires!)) {
        _lock();
      } else if (_scope != null && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _lock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    _scroll.dispose();
    _breadcrumbs.dispose();
    _lease.dispose();
    unawaited(RootFiles.lock());
    super.dispose();
  }

  void _lock() {
    unawaited(RootFiles.lock());
    _lease.value = null;
    if (mounted) {
      setState(() {
        _scope = null;
        _expires = null;
        _advancedMode = false;
      });
    }
  }

  bool _writable(String path) =>
      _scope != null &&
      path.startsWith('$_scope/') &&
      _expires != null &&
      DateTime.now().isBefore(_expires!);
  bool get _folderWritable => _scope == _path || _writable(_path);
  String _message(Object e) =>
      e is PlatformException ? e.message ?? 'File operation failed' : '$e';

  Future<void> _load(String path) async {
    if (_busy) return;
    if (_scroll.hasClients) _positions[_path] = _scroll.offset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await RootFiles.call('list', {'path': path});
      final entries = (data['entries'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      entries.sort((a, b) {
        final folder =
            (b['directory'] == true ? 1 : 0) - (a['directory'] == true ? 1 : 0);
        return folder != 0
            ? folder
            : (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              );
      });
      if (mounted) {
        final changed = _path != data['path'];
        setState(() {
          _path = data['path'] as String;
          _entries = entries;
          _unlockable = data['unlockable'] == true;
          _advancedUnlockable = data['advancedUnlockable'] == true;
          _truncated = data['truncated'] == true;
          if (changed) {
            _filter = '';
            _search.clear();
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scroll.hasClients) {
            _scroll.jumpTo(
              (_positions[_path] ?? 0).clamp(
                0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
          if (_breadcrumbs.hasClients) {
            _breadcrumbs.jumpTo(_breadcrumbs.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> _input(String title, {String value = ''}) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          autocorrect: false,
          enableSuggestions: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    // The dialog route may still be animating with its TextField attached.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> _unlock({bool advanced = false}) async {
    String? confirmation;
    if (advanced) {
      confirmation = await showDialog<String>(
        context: context,
        builder: (_) => _AdvancedUnlockDialog(path: _path),
      );
      if (confirmation == null) return;
    } else if (!await _confirm(
      'Unlock this folder?',
      'Allow writes inside:\n$_path\n\nAccess lasts five minutes and locks when you leave the app. Every change still needs confirmation. System locations remain protected.',
      'Unlock writes',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await RootFiles.call('unlock', {
        'path': _path,
        'advanced': advanced,
        if (advanced) 'confirmation': confirmation,
      });
      if (mounted) {
        setState(() {
          _scope = result['scope'] as String;
          _advancedMode = result['advanced'] == true;
          _expires = DateTime.now().add(const Duration(minutes: 5));
          _lease.value = _expires;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(String op, Map<String, dynamic> args) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await RootFiles.call(op, args);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              op == 'trash'
                  ? 'Moved to hidden trash in this folder. Enable Hidden files to restore by renaming.'
                  : data['backup'] != null
                  ? 'Saved. Original backup: ${data['backup']}'
                  : 'Done',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _error == null) await _load(_path);
  }

  Future<void> _action(String op, Map<String, dynamic> entry) async {
    if (op == 'details') {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _FileProperties(entry: entry),
      );
      return;
    }
    String? name;
    if (op == 'rename' || op == 'copy') {
      name = await _input(
        op == 'rename' ? 'Rename to' : 'Copy in this folder as',
        value: entry['name'] as String,
      );
      if (name == null || !mounted) return;
    }
    final description = op == 'trash'
        ? 'Move ${entry['path']} to a hidden trash entry in the same folder? Nothing is permanently deleted.'
        : '${entry['path']}\n→ $name\n\nExisting destinations will not be overwritten.';
    if (!mounted ||
        !await _confirm(
          op == 'trash' ? 'Move to trash?' : 'Confirm $op',
          description,
          op == 'trash' ? 'Move to trash' : 'Confirm',
        )) {
      return;
    }
    await _mutate(op, {
      'path': entry['path'],
      'identity': entry['identity'],
      'name': ?name,
    });
  }

  Future<void> _open(Map<String, dynamic> entry) async {
    if (entry['directory'] == true || entry['link'] == true) {
      await _load(entry['path'] as String);
      return;
    }
    if (entry['regular'] != true) {
      await _action('details', entry);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Map<String, dynamic>? file;
    try {
      file = await RootFiles.call('read', {'path': entry['path']});
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || file == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _TextFileScreen(
          file: file!,
          writable: _writable(entry['path'] as String),
          lease: _lease,
        ),
      ),
    );
    if (changed == true && mounted) await _load(_path);
  }

  Future<void> _openBackups() async {
    if (_busy) return;
    try {
      final result = await RootFiles.call('backupFolder');
      if (mounted) await _load(result['path'] as String);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_filter.isNotEmpty) {
      setState(() {
        _filter = '';
        _search.clear();
      });
    } else if (_path != '/') {
      await _load(fileParentPath(_path));
    } else {
      await Navigator.maybePop(context);
    }
  }

  void _menu(String value) {
    if (value == 'guide') {
      _showFolderGuide();
    } else if (value == 'advanced') {
      _unlock(advanced: true);
    } else if (value == 'hidden') {
      setState(() => _hidden = !_hidden);
    } else if (value == 'descending') {
      setState(() => _descending = !_descending);
    } else if (['name', 'modified', 'size'].contains(value)) {
      setState(() => _sort = value);
    } else if (value == 'help') {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Write protection'),
          content: const SingleChildScrollView(
            child: Text(
              'Browsing is read-only. Unlock one folder for five minutes to make changes. Advanced unlock also supports root customizations under /data/adb after you enter the complete folder path. Other protected system paths and Android permissions remain in force.\n\nWrites lock when you leave the app. Symbolic-link writes stay blocked. Text saves keep a backup and reject changed files. There is no permanent deletion, permission editor or remount.\n\nBackups and trash stay in their original folders. These protections reduce mistakes; they do not make arbitrary edits safe.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  void _showFolderGuide() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                'Android folder guide',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Descriptions are a guide, not a guarantee that a folder is safe to edit. Layouts vary between devices.',
                ),
              ),
              for (final folder in rootFolderGuide)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.path,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(folder.description),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entries = _entries
        .where(
          (e) =>
              (_hidden || !(e['name'] as String).startsWith('.')) &&
              (e['name'] as String).toLowerCase().contains(
                _filter.toLowerCase(),
              ),
        )
        .toList();
    entries.sort((a, b) {
      final folders =
          (b['directory'] == true ? 1 : 0) - (a['directory'] == true ? 1 : 0);
      if (folders != 0) return folders;
      final primary = switch (_sort) {
        'modified' => ((a['modified'] as num?) ?? 0).compareTo(
          (b['modified'] as num?) ?? 0,
        ),
        'size' => ((a['size'] as num?) ?? 0).compareTo(
          (b['size'] as num?) ?? 0,
        ),
        _ => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      };
      final comparison = primary != 0
          ? primary
          : (a['name'] as String).compareTo(b['name'] as String);
      return _descending ? -comparison : comparison;
    });
    final seconds = (_expires?.difference(DateTime.now()).inSeconds ?? 0).clamp(
      0,
      300,
    );
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    return PopScope(
      canPop: !_busy && _path == '/' && _filter.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _busy ? null : _back),
          title: const Text('Root file explorer'),
          actions: [
            IconButton(
              tooltip: 'Go to path',
              onPressed: _busy
                  ? null
                  : () async {
                      final p = await _input(
                        'Go to absolute path',
                        value: _path,
                      );
                      if (p != null && mounted) await _load(p);
                    },
              icon: const Icon(Icons.drive_file_move_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _load(_path),
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: 'View options',
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'guide',
                  child: Text('Android folder guide'),
                ),
                if (_advancedUnlockable && _scope == null)
                  const PopupMenuItem(
                    value: 'advanced',
                    child: Text('Advanced unlock…'),
                  ),
                CheckedPopupMenuItem(
                  value: 'hidden',
                  checked: _hidden,
                  child: const Text('Show hidden files'),
                ),
                const PopupMenuDivider(),
                for (final sort in const {
                  'name': 'Sort by name',
                  'modified': 'Sort by modified date',
                  'size': 'Sort by size',
                }.entries)
                  CheckedPopupMenuItem(
                    value: sort.key,
                    checked: _sort == sort.key,
                    child: Text(sort.value),
                  ),
                CheckedPopupMenuItem(
                  value: 'descending',
                  checked: _descending,
                  child: const Text('Descending order'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'help',
                  child: Text('About write protection'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  controller: _breadcrumbs,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : () => _load('/'),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: const Text('Root'),
                      ),
                      for (var i = 0; i < parts.length; i++) ...[
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _load('/${parts.take(i + 1).join('/')}'),
                          child: Text(
                            parts[i],
                            style: i == parts.length - 1
                                ? const TextStyle(fontWeight: FontWeight.w700)
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    for (final shortcut in const [
                      (
                        '/sdcard',
                        'Shared storage',
                        Icons.phone_android_outlined,
                      ),
                      ('/data/user/0', 'App data', Icons.apps_outlined),
                      (
                        '/data/adb',
                        'Root customizations',
                        Icons.extension_outlined,
                      ),
                      ('/data/local/tmp', 'Temp', Icons.folder_outlined),
                      ('', 'Root edit backups', Icons.inventory_2_outlined),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(shortcut.$3, size: 18),
                          label: Text(shortcut.$2),
                          onPressed: _busy
                              ? null
                              : shortcut.$1.isEmpty
                              ? _openBackups
                              : () => _load(shortcut.$1),
                        ),
                      ),
                  ],
                ),
              ),
              if (rootFolderDescription(_path) case final description?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      InkWell(
                        onTap: _showFolderGuide,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text('Guide'),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: _scope == null
                      ? colors.surfaceContainerLow
                      : colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      _scope == null
                          ? Icons.shield_outlined
                          : Icons.lock_open_outlined,
                      color: _scope == null
                          ? colors.onSurfaceVariant
                          : colors.onSecondaryContainer,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _scope == null
                                ? (_unlockable
                                      ? 'Read-only browsing'
                                      : _advancedUnlockable
                                      ? 'Advanced unlock available'
                                      : 'Protected folder')
                                : _folderWritable
                                ? '${_advancedMode ? 'Advanced writes' : 'Editing enabled'} · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
                                : 'Read-only here',
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            _scope != null
                                ? 'Unlocked: $_scope'
                                : _unlockable
                                ? 'Unlock this folder to make changes'
                                : _advancedUnlockable
                                ? 'Advanced confirmation required to edit here'
                                : 'Writes stay blocked in this location',
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_scope != null)
                      TextButton(
                        onPressed: _busy ? null : _lock,
                        child: const Text('Lock'),
                      )
                    else if (_unlockable)
                      TextButton(
                        onPressed: _busy ? null : _unlock,
                        child: const Text('Unlock'),
                      ),
                    if (_scope == null && !_unlockable && _advancedUnlockable)
                      TextButton(
                        onPressed: _busy ? null : () => _unlock(advanced: true),
                        child: const Text(
                          'Advanced\nunlock',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search this folder',
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _filter.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () => setState(() {
                              _filter = '';
                              _search.clear();
                            }),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entries.length} ${entries.length == 1 ? 'item' : 'items'}${_filter.isNotEmpty ? ' found' : ''}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      'Folders first',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 2,
                child: _busy
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _error!,
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss error',
                          onPressed: () => setState(() => _error = null),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_truncated)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'First 1,000 entries shown. Search covers loaded entries only.',
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(_path),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (entries.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _error != null
                                        ? Icons.folder_off_outlined
                                        : _filter.isNotEmpty
                                        ? Icons.search_off
                                        : Icons.folder_open_outlined,
                                    size: 48,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _busy
                                        ? 'Opening folder…'
                                        : _error != null
                                        ? 'Could not load this folder'
                                        : _filter.isNotEmpty
                                        ? 'No matching files'
                                        : 'This folder is empty',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  if (!_busy &&
                                      (_filter.isNotEmpty || _error != null))
                                    TextButton(
                                      onPressed: _error != null
                                          ? () => _load(_path)
                                          : () => setState(() {
                                              _filter = '';
                                              _search.clear();
                                            }),
                                      child: Text(
                                        _error != null
                                            ? 'Try again'
                                            : 'Clear search',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                          sliver: SliverList.builder(
                            itemCount: entries.length,
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              final folder = e['directory'] == true;
                              final link = e['link'] == true;
                              final write =
                                  _writable(e['path'] as String) &&
                                  !link &&
                                  e['identity'] != null;
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.only(
                                  left: 12,
                                  right: 0,
                                ),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: folder
                                        ? colors.primaryContainer
                                        : colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    link
                                        ? Icons.link
                                        : folder
                                        ? Icons.folder_outlined
                                        : Icons.description_outlined,
                                    color: folder
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                title: Text(
                                  e['name'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  fileEntrySubtitle(e),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: _busy ? null : () => _open(e),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Actions for ${e['name']}',
                                  enabled: !_busy,
                                  onSelected: (v) => _action(v, e),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'details',
                                      child: ListTile(
                                        leading: Icon(Icons.info_outline),
                                        title: Text('Properties'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    if (write) ...[
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.drive_file_rename_outline,
                                          ),
                                          title: Text('Rename'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                      if (e['regular'] == true)
                                        const PopupMenuItem(
                                          value: 'copy',
                                          child: ListTile(
                                            leading: Icon(Icons.copy_outlined),
                                            title: Text('Copy in this folder'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      if (!((e['path'] as String) ==
                                              '/data/adb' ||
                                          (e['path'] as String).startsWith(
                                            '/data/adb/',
                                          )))
                                        const PopupMenuItem(
                                          value: 'trash',
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('Move to trash'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _folderWritable
            ? FloatingActionButton.extended(
                onPressed: _busy
                    ? null
                    : () async {
                        final name = await _input('New folder');
                        if (name == null || !mounted) return;
                        if (name.isEmpty ||
                            name.contains('/') ||
                            name == '.' ||
                            name == '..') {
                          setState(() => _error = 'Enter a single folder name');
                          return;
                        }
                        if (await _confirm(
                          'Create folder?',
                          '$_path/$name',
                          'Create',
                        )) {
                          await _mutate('mkdir', {'path': '$_path/$name'});
                        }
                      },
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New folder'),
              )
            : null,
      ),
    );
  }
}

class _AdvancedUnlockDialog extends StatefulWidget {
  final String path;
  const _AdvancedUnlockDialog({required this.path});
  @override
  State<_AdvancedUnlockDialog> createState() => _AdvancedUnlockDialogState();
}

class _AdvancedUnlockDialogState extends State<_AdvancedUnlockDialog> {
  final _confirmation = TextEditingController();
  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Advanced folder unlock'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            widget.path,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (rootFolderDescription(widget.path) case final description?)
            Text(description),
          const SizedBox(height: 12),
          const Text(
            'Editing unfamiliar files can break apps or services. Changes to root modules or boot scripts under /data/adb can remove root access or prevent booting. Access lasts five minutes, applies only inside this folder, and locks when you leave the app. Backups cannot undo every effect of a live change.\n\nThe /data/adb customization exception does not unlock other protected system paths, remount read-only filesystems or bypass Android security restrictions.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmation,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Type the complete folder path',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _confirmation.text == widget.path
            ? () => Navigator.pop(context, _confirmation.text)
            : null,
        child: const Text('Unlock folder'),
      ),
    ],
  );
}

class _FileProperties extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _FileProperties({required this.entry});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
    final directory = entry['directory'] == true;
    final modified = entry['modified'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(entry['modified'] as int)
              .toLocal();
    final localizations = MaterialLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(entry['name'] as String, style: theme.textTheme.titleLarge),
              field('Path', entry['path'] as String),
              if (directory)
                if (rootFolderDescription(entry['path'] as String)
                    case final description?)
                  field('About this folder', description),
              field(
                'Type',
                entry['link'] == true
                    ? 'Symbolic link · writes blocked'
                    : directory
                    ? 'Folder'
                    : entry['regular'] == true
                    ? 'File'
                    : 'Special filesystem entry',
              ),
              if (!directory)
                field(
                  'Size',
                  '${formatFileSize(entry['size'] as num?)} (${entry['size'] ?? '?'} bytes)',
                ),
              field(
                'Owner',
                '${fileOwnerLabel(entry['uid'])} (UID ${entry['uid'] ?? '?'})',
              ),
              field(
                'Group',
                '${fileOwnerLabel(entry['gid'], group: true)} (GID ${entry['gid'] ?? '?'})',
              ),
              field(
                'Modified',
                modified == null
                    ? 'Unknown'
                    : '${localizations.formatFullDate(modified)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(modified))}',
              ),
              const Divider(height: 28),
              Text('Permissions', style: theme.textTheme.titleMedium),
              field(
                'Owner can',
                filePermissionDescription(
                  entry['mode'],
                  6,
                  directory: directory,
                ),
              ),
              field(
                'Group can',
                filePermissionDescription(
                  entry['mode'],
                  3,
                  directory: directory,
                ),
              ),
              field(
                'Others can',
                filePermissionDescription(
                  entry['mode'],
                  0,
                  directory: directory,
                ),
              ),
              field(
                'Technical mode',
                '${filePermissionSymbols(entry['mode'])} (${entry['mode'] ?? '?'})',
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextFileScreen extends StatefulWidget {
  final Map<String, dynamic> file;
  final bool writable;
  final ValueNotifier<DateTime?> lease;
  const _TextFileScreen({
    required this.file,
    required this.writable,
    required this.lease,
  });
  @override
  State<_TextFileScreen> createState() => _TextFileScreenState();
}

class _TextFileScreenState extends State<_TextFileScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.file['text'] as String,
  );
  bool _busy = false;
  bool _allowExit = false, _leaving = false;
  String? _error;
  late String _originalText = widget.file['text'] as String;
  bool get _dirty => _text.text != _originalText;
  bool get _canWrite =>
      widget.writable &&
      widget.lease.value != null &&
      DateTime.now().isBefore(widget.lease.value!);
  @override
  void initState() {
    super.initState();
    widget.lease.addListener(_leaseChanged);
  }

  void _leaseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.lease.removeListener(_leaseChanged);
    _text.dispose();
    super.dispose();
  }

  Future<bool> _discard() async =>
      !_dirty ||
      (await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Discard changes?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Keep editing'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Discard'),
                ),
              ],
            ),
          )) ==
          true;
  Future<void> _save() async {
    if (!_canWrite || _busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save text file?'),
        content: Text(
          '${widget.file['path']}\n\n${(widget.file['path'] as String).startsWith('/data/adb/') ? 'The original is kept in the app’s private Root edit backups folder, outside module and boot-script directories.' : 'The original is kept as a hidden backup in the same folder.'} Saving is refused if the file changed or its owner, mode and SELinux label cannot be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await RootFiles.call('save', {
        'path': widget.file['path'],
        'identity': widget.file['identity'],
        'hash': widget.file['hash'],
        'text': _text.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved. Backup: ${result['backup']}')),
        );
        setState(() {
          _originalText = _text.text;
          _allowExit = true;
          _busy = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is PlatformException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy || _leaving) return;
    _leaving = true;
    try {
      if (await _discard() && mounted) {
        setState(() => _allowExit = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } finally {
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (_allowExit || !_dirty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: Text(widget.file['name'] as String),
        actions: [
          if (_canWrite)
            TextButton(
              onPressed: _busy || !_dirty ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _canWrite
                    ? 'Text editor · writes require an active folder unlock'
                    : widget.writable
                    ? 'Write access locked · unsaved text is kept here'
                    : 'Read-only · unlock the containing folder before opening to edit',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _text,
                  readOnly: !_canWrite || _busy,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
