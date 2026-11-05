import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/file_transfer_queue.dart';
import '../utils/file_size.dart';
import '../ssh/ssh_session_manager.dart';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import '../services/download_store.dart';
import '../services/upload_store.dart';

class SftpScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  final List<Device> peerDevices;
  const SftpScreen({
    super.key,
    required this.device,
    required this.session,
    this.peerDevices = const [],
  });
  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  final _queue = FileTransferQueue();
  List<String> _favorites = [];
  bool _showTransfers = false, _leaving = false;
  String get _favoriteKey => 'file_favorites_${widget.device.id}';
  SftpClient? _sftp;
  List<SftpName> _entries = [];
  String _path = '.', _home = '.', _message = '';
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _busy = false;
  List<SftpName> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((entry) => entry.filename.toLowerCase().contains(query))
        .toList(growable: false);
  }

  void _toggleSearch() {
    setState(() {
      if (_searching) {
        _search.clear();
        _searching = false;
      } else {
        _searching = true;
      }
    });
  }

  Future<void> _upload() async {
    Map<String, dynamic>? selected;
    try {
      selected = await UploadStore.pick();
    } catch (e) {
      if (mounted) setState(() => _message = 'Cannot select file: $e');
      return;
    }
    if (selected == null || !mounted) return;
    final name = (selected['name'] as String)
        .replaceAll('\\', '/')
        .split('/')
        .last;
    if (name.isEmpty || name == '.' || name == '..') {
      setState(() => _message = 'Invalid filename');
      return;
    }
    final chosen = selected;
    final target = '$_path/$name';
    final sftp = _sftp!;
    _queue.add(
      FileTransfer('Upload $name', (t) async {
        SftpFile? file;
        SftpFileWriter? writer;
        Timer? timer;
        var created = false, completed = false;
        try {
          await UploadStore.open(chosen['uri'] as String);
          t.total = chosen['size'] as int?;
          file = await sftp
              .open(
                target,
                mode:
                    SftpFileOpenMode.write |
                    SftpFileOpenMode.create |
                    SftpFileOpenMode.exclusive,
              )
              .timeout(const Duration(seconds: 20));
          created = true;
          var lastProgress = DateTime.now();
          writer = file.write(
            UploadStore.read(() => t.cancelled),
            chunkSize: 64 * 1024,
            maxPendingRequests: 16,
            onProgress: (n) {
              lastProgress = DateTime.now();
              t.progress(n);
            },
          );
          timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
            if (t.cancelled ||
                DateTime.now().difference(lastProgress) >
                    const Duration(seconds: 30)) {
              {
                unawaited(writer!.abort());
              }
            }
          });
          await writer.done;
          if (t.cancelled) throw StateError('Upload cancelled');
          if (t.total != null && t.bytes != t.total) {
            throw StateError('Incomplete upload');
          }
          completed = true;
        } finally {
          timer?.cancel();
          if (!completed) {
            try {
              await writer?.abort();
            } catch (_) {}
          }
          try {
            await file?.close();
          } catch (_) {}
          if (created && !completed) {
            try {
              await sftp.remove(target);
            } catch (_) {}
          }
          await UploadStore.close();
        }
      }),
    );
    setState(() => _showTransfers = true);
  }

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      setState(() => _message = 'Enter a single folder name.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _sftp!.mkdir('$_path/$name').timeout(const Duration(seconds: 20));
      await _load(_path);
    } catch (e) {
      if (mounted) setState(() => _message = 'Cannot create folder: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T> _openResource<T>(
    Future<T> opening,
    Future<void> Function(T) close,
  ) async {
    var expired = false;
    final guarded = opening.then((resource) async {
      if (expired || !mounted) {
        try {
          await close(resource);
        } catch (_) {}
        throw StateError('File operation cancelled.');
      }
      return resource;
    });
    return guarded.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        expired = true;
        throw TimeoutException('The remote file service did not respond.');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _queue.addListener(_queueChanged);
    _readFavorites();
    _load('.');
  }

  Future<void> _load(String path) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (!widget.session.isConnected ||
          widget.session.deviceId != widget.device.id) {
        throw StateError('Connect to this device first.');
      }
      if (_sftp == null) {
        final opened = await _openResource(
          widget.session.client!.sftp(),
          (sftp) => sftp.close(),
        );
        if (!mounted) {
          await opened.close();
          return;
        }
        _sftp = opened;
        _home = await opened.absolute('.').timeout(const Duration(seconds: 20));
      }
      final resolved = await _sftp!
          .absolute(path)
          .timeout(const Duration(seconds: 20));
      final entries = await _sftp!
          .listdir(resolved)
          .timeout(const Duration(seconds: 20));
      entries.removeWhere((e) => e.filename == '.' || e.filename == '..');
      entries.sort(
        (a, b) => a.attr.isDirectory != b.attr.isDirectory
            ? (a.attr.isDirectory ? -1 : 1)
            : a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _path = resolved;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Cannot browse files: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _queueChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _readFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _favorites = prefs.getStringList(_favoriteKey) ?? []);
    }
  }

  Future<void> _favorite() async {
    setState(() {
      if (_favorites.contains(_path)) {
        _favorites.remove(_path);
      } else {
        _favorites.add(_path);
      }
    });
    await (await SharedPreferences.getInstance()).setStringList(
      _favoriteKey,
      _favorites,
    );
  }

  Widget _transferPanel() => SizedBox(
    height: _queue.items.isEmpty ? 64 : 200,
    child: _queue.items.isEmpty
        ? const Center(child: Text('No queued transfers'))
        : ListView(
            children: _queue.items.reversed
                .map(
                  (t) => ListTile(
                    title: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.state.name} · ${formatFileSize(t.bytes)}${t.total == null ? '' : ' / ${formatFileSize(t.total)}'} · ${formatFileSize(t.bytesPerSecond)}/s',
                        ),
                        if (t.state == TransferState.running)
                          LinearProgressIndicator(
                            value: (t.total ?? 0) > 0
                                ? (t.bytes / t.total!).clamp(0, 1)
                                : null,
                          ),
                        if (t.error != null) Text(t.error!, maxLines: 2),
                      ],
                    ),
                    trailing:
                        t.state == TransferState.queued ||
                            t.state == TransferState.running
                        ? IconButton(
                            tooltip: 'Cancel transfer',
                            icon: const Icon(Icons.close),
                            onPressed: t.cancel,
                          )
                        : t.state == TransferState.failed ||
                              t.state == TransferState.cancelled
                        ? IconButton(
                            tooltip: 'Retry transfer',
                            icon: const Icon(Icons.refresh),
                            onPressed: () => _queue.retry(t),
                          )
                        : const Icon(Icons.check_circle_outline),
                  ),
                )
                .toList(),
          ),
  );
  Future<String?> _ask(String title, String label, String initial) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    c.dispose();
    return value;
  }

  Future<void> _fileAction(SftpName entry, String action) async {
    final source = '$_path/${entry.filename}';
    if (action == 'download') {
      final sftp = _sftp!;
      final task = FileTransfer('Download ${entry.filename}', (t) async {
        final f = await sftp.open(source).timeout(const Duration(seconds: 20));
        try {
          t.total = (await f.stat()).size;
          await DownloadStore.save(
            entry.filename,
            f
                .read(chunkSize: 64 * 1024, maxPendingRequests: 16)
                .timeout(const Duration(seconds: 30))
                .map((chunk) {
                  if (t.cancelled) throw StateError('Transfer cancelled');
                  return chunk;
                }),
            onProgress: t.progress,
          );
          if (t.total != null && t.bytes != t.total) {
            throw StateError('Incomplete download');
          }
        } finally {
          await f.close();
        }
      });
      _queue.add(task);
      setState(() => _showTransfers = true);
      return;
    }
    if (action == 'copy') {
      await _copyToDevice(entry, source);
      return;
    }
    if (action == 'preview') {
      await _preview(entry, source);
      return;
    }
    final target = await _ask(
      action == 'rename' ? 'Rename' : 'Move to folder',
      action == 'rename' ? 'New name' : 'Destination folder',
      action == 'rename' ? entry.filename : _path,
    );
    if (!mounted || target == null || target.isEmpty) return;
    if (action == 'rename' &&
        (target == '.' ||
            target == '..' ||
            target.contains('/') ||
            target.contains('\\') ||
            target.contains('\x00'))) {
      setState(() => _message = 'Enter a single filename.');
      return;
    }
    setState(() => _busy = true);
    try {
      final destination = action == 'rename'
          ? '$_path/$target'
          : '$target/${entry.filename}';
      if (destination == source) return;
      var exists = false;
      try {
        await _sftp!.stat(destination);
        exists = true;
      } on SftpStatusError catch (e) {
        if (e.code != SftpStatusCode.noSuchFile) rethrow;
      }
      if (exists) {
        throw StateError(
          'Destination already exists. Choose a different name.',
        );
      }
      await _sftp!
          .rename(source, destination)
          .timeout(const Duration(seconds: 20));
      await _load(_path);
    } catch (e) {
      if (mounted) setState(() => _message = 'File action failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(SftpName entry, String source) async {
    final ext = entry.filename.toLowerCase().split('.').last;
    final image = isPreviewImage(entry.filename);
    final text = const [
      'txt',
      'md',
      'json',
      'yaml',
      'yml',
      'csv',
      'log',
      'dart',
      'py',
      'sh',
      'ps1',
      'xml',
      'ini',
      'conf',
      'html',
      'css',
      'js',
    ].contains(ext);
    if (!image && !text) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry.filename),
          content: Text(
            '${formatFileSize(entry.attr.size)}\nPreview is unavailable for this file type.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _fileAction(entry, 'download');
              },
              child: const Text('Download'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    if (image && (entry.attr.size ?? 0) > 8 * 1048576) {
      setState(
        () => _message =
            'Image preview limit is 8 MB. Download the original instead.',
      );
      return;
    }
    setState(() => _busy = true);
    SftpFile? f;
    try {
      f = await _sftp!.open(source).timeout(const Duration(seconds: 20));
      final Uint8List bytes = await f
          .readBytes(length: image ? 8 * 1048576 : 256 * 1024)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (image) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (ctx) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                title: Text(entry.filename),
                actions: [
                  IconButton(
                    tooltip: 'Download original',
                    icon: const Icon(Icons.download),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _fileAction(entry, 'download');
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 8,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This image format cannot be previewed. Use Download original.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry.filename),
          content: SizedBox(
            width: double.maxFinite,
            child: image
                ? InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      errorBuilder: (_, e, stack) =>
                          const Text('Cannot decode image'),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      utf8.decode(bytes, allowMalformed: true),
                    ),
                  ),
          ),
          actions: [
            if (text && (entry.attr.size ?? 0) > bytes.length)
              const Text('First 256 KB'),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _fileAction(entry, 'download');
              },
              child: const Text('Download original'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _message = 'Preview failed: $e');
    } finally {
      await f?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToDevice(SftpName entry, String source) async {
    final peers = widget.peerDevices
        .where(
          (d) =>
              d.id != widget.device.id &&
              (sshSessions.existingSession(d.id)?.isConnected ?? false),
        )
        .toList();
    if (peers.isEmpty) {
      setState(
        () => _message =
            'Connect the other device from Devices first, then return here.',
      );
      return;
    }
    final peer = await showDialog<Device>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Copy to device'),
        children: peers
            .map(
              (d) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, d),
                child: Text(d.name),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || peer == null) return;
    final folder = await _ask(
      'Copy to ${peer.name}',
      'Destination folder · streamed through phone',
      '.',
    );
    if (!mounted || folder == null || folder.isEmpty) return;
    final sourceClient = _sftp!;
    final session = sshSessions.existingSession(peer.id)!;
    _queue.add(
      FileTransfer('Copy ${entry.filename} → ${peer.name}', (t) async {
        if (!session.isConnected) throw StateError('Destination disconnected');
        final destination = await session.client!.sftp().timeout(
          const Duration(seconds: 20),
        );
        SftpFile? input, output;
        SftpFileWriter? writer;
        String? target;
        bool created = false, completed = false;
        Timer? cancelTimer;
        try {
          final resolved = await destination
              .absolute(folder)
              .timeout(const Duration(seconds: 20));
          target = '$resolved/${entry.filename}';
          input = await sourceClient
              .open(source)
              .timeout(const Duration(seconds: 20));
          t.total = (await input.stat()).size;
          output = await destination
              .open(
                target,
                mode:
                    SftpFileOpenMode.write |
                    SftpFileOpenMode.create |
                    SftpFileOpenMode.exclusive,
              )
              .timeout(const Duration(seconds: 20));
          created = true;
          writer = output.write(
            input
                .read(chunkSize: 64 * 1024, maxPendingRequests: 16)
                .timeout(const Duration(seconds: 30))
                .map((chunk) {
                  if (t.cancelled) throw StateError('Transfer cancelled');
                  return chunk;
                }),
            chunkSize: 64 * 1024,
            maxPendingRequests: 16,
            onProgress: t.progress,
          );
          var previousBytes = t.bytes;
          var lastProgress = DateTime.now();
          cancelTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
            if (t.bytes != previousBytes) {
              previousBytes = t.bytes;
              lastProgress = DateTime.now();
            }
            if (t.cancelled ||
                DateTime.now().difference(lastProgress) >
                    const Duration(seconds: 30)) {
              unawaited(writer!.abort());
            }
          });
          await writer.done;
          if (t.cancelled) throw StateError('Transfer cancelled');
          if (t.total != null && t.bytes != t.total) {
            throw StateError('Incomplete copy');
          }
          completed = true;
        } finally {
          cancelTimer?.cancel();
          if (!completed) {
            try {
              await writer?.abort();
            } catch (_) {}
          }
          try {
            await input?.close();
          } catch (_) {}
          try {
            await output?.close();
          } catch (_) {}
          if (created && !completed && target != null) {
            try {
              await destination.remove(target);
            } catch (_) {}
          }
          await destination.close();
        }
      }),
    );
    setState(() => _showTransfers = true);
  }

  Future<void> _goToPath() async {
    final controller = TextEditingController(text: _path);
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Remote path'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    // Dialog removal animates; keep its controller alive through that frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && path != null && path.trim().isNotEmpty) {
      await _load(path.trim());
    }
  }

  @override
  void dispose() {
    _queue.removeListener(_queueChanged);
    _queue.dispose();
    _search.dispose();
    unawaited(_sftp?.close().catchError((Object _) {}) ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _leaving ||
        !_queue.items.any(
          (t) =>
              t.state == TransferState.queued ||
              t.state == TransferState.running,
        ),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel pending transfers?'),
          content: const Text(
            'Leaving this file manager cancels its running and queued transfers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel and leave'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(
          () => _message = 'Cancelling transfers and cleaning partial files…',
        );
        await _queue.cancelAll();
        if (!mounted) return;
        setState(() => _leaving = true);
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search this folder',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text('${widget.device.name} files'),
        actions: [
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => setState(() => _showTransfers = !_showTransfers),
            icon: Badge(
              label: Text(
                '${_queue.items.where((t) => t.state == TransferState.queued || t.state == TransferState.running).length}',
              ),
              child: const Icon(Icons.swap_vert),
            ),
          ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search files',
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'Upload file',
            onPressed: _busy || _sftp == null ? null : _upload,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'New folder',
            onPressed: _busy || _sftp == null ? null : _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            onPressed: _busy ? null : () => _load(_path),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_showTransfers) _transferPanel(),
            Row(
              children: [
                IconButton(
                  tooltip: 'Home',
                  onPressed: _busy ? null : () => _load(_home),
                  icon: const Icon(Icons.home_outlined),
                ),
                IconButton(
                  tooltip: 'Parent folder',
                  onPressed: _busy ? null : () => _load('$_path/..'),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Favorite folder',
                  onPressed: _busy ? null : _favorite,
                  icon: Icon(
                    _favorites.contains(_path) ? Icons.star : Icons.star_border,
                  ),
                ),
                if (_favorites.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Favorite folders',
                    icon: const Icon(Icons.bookmarks_outlined),
                    onSelected: _load,
                    itemBuilder: (_) => _favorites
                        .map((p) => PopupMenuItem(value: p, child: Text(p)))
                        .toList(),
                  ),
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : _goToPath,
                    child: Text(_path, maxLines: 2),
                  ),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_message),
              ),
            Expanded(
              child: _visibleEntries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _search.text.isEmpty
                                ? Icons.folder_open_outlined
                                : Icons.search_off,
                            size: 44,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _search.text.isNotEmpty
                                ? 'No matching files'
                                : _busy
                                ? 'Loading folder…'
                                : 'This folder is empty',
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _visibleEntries.length,
                      itemBuilder: (_, i) {
                        final e = _visibleEntries[i];
                        return ListTile(
                          leading: Icon(
                            e.attr.isDirectory
                                ? Icons.folder_outlined
                                : isPreviewImage(e.filename)
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(e.filename),
                          subtitle: e.attr.isDirectory
                              ? null
                              : Text(formatFileSize(e.attr.size)),
                          trailing: PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (action) => _fileAction(e, action),
                            itemBuilder: (_) => [
                              if (!e.attr.isDirectory)
                                const PopupMenuItem(
                                  value: 'preview',
                                  child: Text('Preview'),
                                ),
                              if (!e.attr.isDirectory)
                                const PopupMenuItem(
                                  value: 'download',
                                  child: Text('Download to phone'),
                                ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              const PopupMenuItem(
                                value: 'move',
                                child: Text('Move to folder'),
                              ),
                              if (!e.attr.isDirectory)
                                const PopupMenuItem(
                                  value: 'copy',
                                  child: Text('Copy to another device'),
                                ),
                            ],
                          ),
                          onTap: _busy
                              ? null
                              : () => e.attr.isDirectory
                                    ? _load('$_path/${e.filename}')
                                    : _fileAction(e, 'preview'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
