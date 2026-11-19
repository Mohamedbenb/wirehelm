import 'dart:async';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/remote_downloads.dart';
import '../ssh/ssh_session.dart';
import '../ssh/ssh_session_manager.dart';
import '../utils/file_size.dart';
import 'sftp_screen.dart';
import 'ota_preparation_screen.dart';

class RemoteDownloadsScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  final List<Device> peerDevices;

  const RemoteDownloadsScreen({
    super.key,
    required this.device,
    required this.session,
    this.peerDevices = const [],
  });

  @override
  State<RemoteDownloadsScreen> createState() => _RemoteDownloadsScreenState();
}

class _RemoteDownloadsScreenState extends State<RemoteDownloadsScreen>
    with WidgetsBindingObserver {
  late Device _device;
  late SshSession _session;
  late RemoteDownloads _api;
  List<RemoteDownload> _jobs = [];
  String _folder = '', _error = '';
  bool _busy = false, _interacting = false;
  Timer? _timer;

  bool get _online => _session.isConnected && _session.deviceId == _device.id;
  Map<String, Device> get _devices => {
    widget.device.id: widget.device,
    for (final device in widget.peerDevices) device.id: device,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _device = widget.device;
    _session = widget.session;
    _api = RemoteDownloads(_device, _session);
    _session.addListener(_sessionChanged);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_interacting &&
          _online &&
          (ModalRoute.of(context)?.isCurrent ?? false) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _online) _refresh();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _read() async {
    final data = await _api.list();
    if (!mounted) return;
    _jobs = (data['jobs'] as List)
        .map(
          (item) =>
              RemoteDownload.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    _folder = data['folder'] as String;
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy || !_online) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _error = error is StateError ? error.message.toString() : '$error';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (!_interacting) await _perform(_read);
  }

  void _selectDevice(String? id) {
    if (_busy || id == null || id == _device.id) return;
    final device = _devices[id];
    final session = id == widget.device.id
        ? widget.session
        : sshSessions.existingSession(id);
    if (device == null || session == null || !session.isConnected) return;
    _session.removeListener(_sessionChanged);
    setState(() {
      _device = device;
      _session = session;
      _api = RemoteDownloads(device, session);
      _session.addListener(_sessionChanged);
      _jobs = [];
      _folder = '';
    });
    _refresh();
  }

  Future<void> _add() async {
    _interacting = true;
    try {
      final request = await Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => _DownloadForm(
            device: _device,
            session: _session,
            folder: _folder,
          ),
        ),
      );
      if (request == null || !mounted) return;
      await _perform(() async {
        try {
          await _api.start(
            id: RemoteDownloads.newId(),
            url: request['url']!,
            name: request['name']!,
            folder: request['folder']!,
            sha256: request['sha256']!,
          );
        } finally {
          // A lost acknowledgement may still have started the job on the host.
          await _read();
        }
      });
    } finally {
      _interacting = false;
    }
  }

  Future<void> _action(RemoteDownload job, String action) async {
    _interacting = true;
    try {
      if (action == 'cancel') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel download?'),
            content: Text('Remove the partial download of ${job.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep download'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel download'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await _perform(() async {
        await _api.action(job, action);
        await _read();
      });
    } finally {
      _interacting = false;
    }
  }

  Future<void> _files(RemoteDownload job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SftpScreen(
          device: _device,
          session: _session,
          initialPath: job.folder.replaceAll('\\', '/'),
          peerDevices: widget.peerDevices,
        ),
      ),
    );
  }

  Widget _card(RemoteDownload job) {
    final total = job.total;
    final progress = total != null && total > 0
        ? (job.bytes / total).clamp(0.0, 1.0)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(job.label),
            Text(job.folder, style: Theme.of(context).textTheme.bodySmall),
            if (job.phase != 'cancelled') ...[
              const SizedBox(height: 10),
              if (job.active) LinearProgressIndicator(value: progress),
              Text(
                '${formatFileSize(job.bytes)}${total == null ? '' : ' of ${formatFileSize(total)}'}',
              ),
            ],
            if (job.error.isNotEmpty)
              Text(
                job.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (job.active && job.phase != 'stopping')
                  TextButton(
                    onPressed: _busy || !_online
                        ? null
                        : () => _action(job, 'pause'),
                    child: const Text('Pause'),
                  ),
                if (job.canResume)
                  FilledButton.tonal(
                    onPressed: _busy || !_online
                        ? null
                        : () => _action(job, 'resume'),
                    child: Text(job.phase == 'failed' ? 'Retry' : 'Resume'),
                  ),
                if (job.canCancel && job.phase != 'stopping')
                  TextButton(
                    onPressed: _busy || !_online
                        ? null
                        : () => _action(job, 'cancel'),
                    child: const Text('Cancel'),
                  ),
                if (job.phase == 'complete')
                  TextButton.icon(
                    onPressed: !_online ? null : () => _files(job),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open folder'),
                  ),
                if (job.phase == 'complete' &&
                    job.name.toLowerCase().endsWith('.zip'))
                  TextButton.icon(
                    onPressed: !_online
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OtaPreparationScreen(
                                device: _device,
                                session: _session,
                                inputPath: '${job.folder}/${job.name}',
                                sourceSha256: job.expectedSha256,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.security),
                    label: const Text('Prepare OTA'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Remote downloads'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy || !_online ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy || !_online || _folder.isEmpty ? null : _add,
      icon: const Icon(Icons.add),
      label: const Text('New download'),
    ),
    body: Column(
      children: [
        SizedBox(
          height: 4,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(_device.id),
                initialValue: _device.id,
                decoration: const InputDecoration(labelText: 'Download to'),
                items: _devices.values.map((device) {
                  final connected = device.id == widget.device.id
                      ? widget.session.isConnected
                      : sshSessions.isConnected(device.id);
                  return DropdownMenuItem(
                    value: device.id,
                    enabled: connected,
                    child: Text(
                      '${device.name}${connected ? '' : ' · offline'}',
                    ),
                  );
                }).toList(),
                onChanged: _busy ? null : _selectDevice,
              ),
              const SizedBox(height: 8),
              Text(
                _online
                    ? 'Downloads keep running on this device after you disconnect.'
                    : 'Reconnect to refresh this device’s download status.',
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _jobs.isEmpty
              ? Center(
                  child: Text(
                    _busy
                        ? 'Checking downloads…'
                        : 'Your remote downloads will appear here.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                  itemCount: _jobs.length,
                  itemBuilder: (_, index) => _card(_jobs[index]),
                ),
        ),
      ],
    ),
  );
}

class _DownloadForm extends StatefulWidget {
  final Device device;
  final SshSession session;
  final String folder;
  const _DownloadForm({
    required this.device,
    required this.session,
    required this.folder,
  });

  @override
  State<_DownloadForm> createState() => _DownloadFormState();
}

class _DownloadFormState extends State<_DownloadForm> {
  final _key = GlobalKey<FormState>();
  final _url = TextEditingController(),
      _name = TextEditingController(),
      _sha = TextEditingController();
  late final TextEditingController _folder;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _folder = TextEditingController(text: widget.folder);
  }

  @override
  void dispose() {
    for (final controller in [_url, _name, _sha, _folder]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _browse() async {
    final folder = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SftpScreen(
          device: widget.device,
          session: widget.session,
          initialPath: _folder.text,
          selectDirectory: true,
        ),
      ),
    );
    if (mounted && folder != null) _folder.text = folder;
  }

  void _submit() {
    if (_key.currentState!.validate()) {
      Navigator.of(context).pop({
        'url': _url.text.trim(),
        'name': _name.text.trim(),
        'folder': _folder.text.trim(),
        'sha256': _sha.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New download')),
    body: Form(
      key: _key,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Save on ${widget.device.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Download URL'),
            validator: (value) => RemoteDownloads.validateUrl(value ?? ''),
            onChanged: (value) {
              if (!_nameEdited) {
                _name.text = RemoteDownloads.suggestedName(value);
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Filename'),
            onChanged: (_) => _nameEdited = true,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Choose a filename.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _folder,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Destination folder',
              suffixIcon: IconButton(
                onPressed: _browse,
                tooltip: 'Choose folder',
                icon: const Icon(Icons.folder_open),
              ),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Choose a folder.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _sha,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'SHA-256 · optional',
              helperText: 'Paste the checksum supplied by the download source.',
            ),
            validator: (value) =>
                value == null ||
                    value.trim().isEmpty ||
                    RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value.trim())
                ? null
                : 'Enter all 64 hexadecimal characters.',
          ),
          const SizedBox(height: 20),
          const Text(
            'Pause keeps the partial file for resuming. If the server cannot safely resume, the download starts again. An existing file is never overwritten.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.download),
            label: const Text('Start download'),
          ),
        ],
      ),
    ),
  );
}
