import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../customization/local_customization.dart';
import '../models/device.dart';
import '../services/remote_downloads.dart';
import '../ssh/ssh_session.dart';
import '../utils/file_size.dart';
import 'sftp_screen.dart';

class OtaPreparationScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  final String inputPath, sourceSha256;

  const OtaPreparationScreen({
    super.key,
    required this.device,
    required this.session,
    this.inputPath = '',
    this.sourceSha256 = '',
  });

  @override
  State<OtaPreparationScreen> createState() => _OtaPreparationScreenState();
}

class _OtaPreparationScreenState extends State<OtaPreparationScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _setup = TextEditingController(text: 'C:/avbroot-pixel10');
  final _input = TextEditingController(), _hash = TextEditingController();
  final _folder = TextEditingController(), _name = TextEditingController();
  final _avbPass = TextEditingController(), _otaPass = TextEditingController();
  late final RemoteDownloads _api;
  Map<String, dynamic>? _phone, _info;
  List<Map<String, dynamic>> _jobs = [];
  String _error = '';
  bool _acting = false;
  Future<Map<String, dynamic>>? _polling;
  Timer? _timer;

  bool get _online =>
      widget.session.isConnected && widget.session.deviceId == widget.device.id;
  String get _profileKey => 'ota_setup_${widget.device.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    _api = RemoteDownloads(widget.device, widget.session);
    _input.text = widget.inputPath;
    _hash.text = widget.sourceSha256;
    _suggestOutput();
    _initialize();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          _online &&
          (ModalRoute.of(context)?.isCurrent ?? false) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  Future<void> _initialize() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _profileKey,
      );
      final phone = await LocalCustomization.call('otaDevice');
      if (!mounted) return;
      setState(() {
        if (saved != null) _setup.text = saved;
        _phone = phone;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    for (final controller in [
      _setup,
      _input,
      _hash,
      _folder,
      _name,
      _avbPass,
      _otaPass,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_acting || _polling != null || !_online) return;
    final polling = _api.ota('list');
    _polling = polling;
    try {
      final data = await polling;
      if (mounted) {
        setState(() {
          _jobs = (data['jobs'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _polling = null;
    }
  }

  String _message(Object error) =>
      error is StateError ? error.message.toString() : '$error';

  Future<void> _act(Future<void> Function() action) async {
    if (_acting || !_online) return;
    setState(() {
      _acting = true;
      _error = '';
    });
    try {
      try {
        await _polling;
      } catch (_) {}
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() => _acting = false);
        _refresh();
      }
    }
  }

  Map<String, dynamic> get _values => {
    'setup': _setup.text.trim(),
    'input': _input.text.trim(),
    'device': _phone?['device'] ?? '',
    'timestamp': _phone?['timestamp'] ?? 0,
    'kernelSuVersion': _phone?['kernelSuVersion'] ?? '',
  };

  void _suggestOutput() {
    final input = _input.text.replaceAll('\\', '/');
    final separator = input.lastIndexOf('/');
    if (separator >= 0) {
      _folder.text = _parentFolder(input)!;
      final name = input
          .substring(separator + 1)
          .replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
      _name.text = '$name-wirehelm-kernelsu.zip';
    }
  }

  String? _parentFolder(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    if (separator < 0) return null;
    final parent = normalized.substring(0, separator);
    if (parent.isEmpty || RegExp(r'^/?[A-Za-z]:$').hasMatch(parent)) {
      return '$parent/';
    }
    return parent;
  }

  Future<FolderListing> _readZipFolder(
    String path, {
    required bool fallbackToHome,
  }) async {
    final result = await _api.ota('browse', {
      'path': path,
      'fallbackToHome': fallbackToHome,
    });
    final entries = (result['entries'] as List).cast<Map<String, dynamic>>();
    return (
      path: result['path'] as String,
      entries: [
        for (final entry in entries)
          SftpName(
            filename: entry['name'] as String,
            longname: entry['name'] as String,
            attr: SftpFileAttrs(
              mode: SftpFileMode.value(
                entry['directory'] == true ? 0x4000 : 0x8000,
              ),
              size: entry['bytes'] as int?,
            ),
          ),
      ],
    );
  }

  Future<void> _browse(TextEditingController controller) async {
    final pickingOta = controller == _input;
    final initialPath = pickingOta
        ? (_parentFolder(_input.text.trim()) ?? _setup.text.trim())
        : controller.text.trim();
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SftpScreen(
          device: widget.device,
          session: widget.session,
          initialPath: initialPath.isEmpty ? '.' : initialPath,
          selectDirectory: !pickingOta,
          selectFile: pickingOta,
          fileExtension: pickingOta ? '.zip' : null,
          readFolder: pickingOta ? _readZipFolder : null,
        ),
      ),
    );
    if (!mounted || selected == null || selected == controller.text) return;
    setState(() {
      controller.text = selected;
      if (pickingOta) {
        _info = null;
        _hash.clear();
        _suggestOutput();
      }
      if (controller == _setup) _info = null;
    });
  }

  Future<void> _inspect() => _act(() async {
    final result = await _api.ota('inspect', _values);
    if (!mounted) return;
    setState(() => _info = result);
    await (await SharedPreferences.getInstance()).setString(
      _profileKey,
      _setup.text.trim(),
    );
  });

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await _act(() async {
      try {
        await _api.ota('start', {
          ..._values,
          'id': RemoteDownloads.newId(),
          'sha256': _hash.text.trim(),
          'outputFolder': _folder.text.trim(),
          'outputName': _name.text.trim(),
          'avbPassphrase': _avbPass.text,
          'otaPassphrase': _otaPass.text,
        });
      } finally {
        _avbPass.clear();
        _otaPass.clear();
      }
    });
  }

  Widget _folderPath(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_acting,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: 'Choose folder',
          onPressed: _acting || !_online ? null : () => _browse(controller),
          icon: const Icon(Icons.folder_open),
        ),
      ),
      validator: (text) =>
          text == null || text.trim().isEmpty ? 'Choose a folder.' : null,
      onChanged: (_) {
        if (controller == _setup) {
          setState(() => _info = null);
        }
      },
    ),
  );

  Widget _otaZipInput() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _acting || !_online ? null : () => _browse(_input),
          icon: const Icon(Icons.folder_open),
          label: const Text('Choose OTA ZIP'),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _input,
          enabled: !_acting,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Full OTA ZIP path'),
          validator: (text) =>
              (text ?? '').trim().toLowerCase().endsWith('.zip')
              ? null
              : 'Choose a ZIP file.',
          onChanged: (_) => setState(() {
            _info = null;
            _hash.clear();
          }),
        ),
      ],
    ),
  );

  Widget _password(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_acting,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      decoration: InputDecoration(labelText: label),
    ),
  );

  static const _phases = {
    'starting': 'Starting',
    'source': 'Checking source OTA',
    'keys': 'Checking signing keys',
    'extracting': 'Extracting this OTA’s boot images',
    'compatibility': 'Detecting kernel compatibility',
    'rooting': 'Patching KernelSU',
    'signing': 'Signing OTA',
    'verifying': 'Verifying signed OTA',
    'checksum': 'Computing output checksum',
    'complete': 'Verified OTA ready',
    'failed': 'Preparation failed',
    'cancelled': 'Cancelled',
    'interrupted': 'Interrupted · start again to retry',
    'stopping': 'Stopping',
  };

  Widget _job(Map<String, dynamic> job) {
    final phase = job['phase'] as String;
    final active = !const {
      'complete',
      'failed',
      'cancelled',
      'interrupted',
    }.contains(phase);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              job['name'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(_phases[phase] ?? phase),
            Text(
              job['build'] as String,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (active)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if ((job['error'] as String? ?? '').isNotEmpty)
              Text(
                job['error'] as String,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if ((job['warning'] as String? ?? '').isNotEmpty)
              Text(job['warning'] as String),
            if (phase == 'complete') ...[
              Text(formatFileSize(job['bytes'] as int?)),
              SelectableText('SHA-256\n${job['sha256']}'),
              TextButton.icon(
                onPressed: !_online
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SftpScreen(
                            device: widget.device,
                            session: widget.session,
                            initialPath: (job['folder'] as String).replaceAll(
                              '\\',
                              '/',
                            ),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open folder'),
              ),
            ],
            if (active && phase != 'stopping')
              TextButton(
                onPressed: _acting || !_online
                    ? null
                    : () => _act(() async {
                        await _api.ota('cancel', {'id': job['id']});
                      }),
                child: const Text('Cancel preparation'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Prepare rooted OTA'),
      actions: [
        IconButton(
          tooltip: 'Refresh jobs',
          onPressed: _acting || !_online ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Prepare on ${widget.device.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Target ${_phone?['device'] ?? 'checking phone…'} · KernelSU ${_phone?['kernelSuVersion'] ?? ''}',
          ),
          const Text(
            'Create a rooted OTA signed with your existing keys. Preparation continues on the computer after you disconnect.',
          ),
          if (!_online)
            const Text('Reconnect to this computer to manage preparation.'),
          _folderPath(_setup, 'Signing setup folder'),
          _otaZipInput(),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _acting || !_online || _phone == null ? null : _inspect,
            child: const Text('Inspect inputs'),
          ),
          if (_info != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_info!['build'] as String),
                    Text(
                      'Security patch ${_info!['patchLevel']} · ${formatFileSize(_info!['inputBytes'] as int)}',
                    ),
                    Text(
                      '${_info!['avbrootVersion']} · KernelSU ${_info!['kernelSuVersion']}',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'AVB public key SHA-256\n${_info!['avbFingerprint']}',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'OTA certificate SHA-256\n${_info!['otaFingerprint']}',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _hash,
            enabled: !_acting,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Source OTA SHA-256',
              helperText: 'Paste the checksum from the official download page.',
              helperMaxLines: 2,
            ),
            validator: (text) =>
                RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(text?.trim() ?? '')
                ? null
                : 'Supply the source OTA’s 64-character SHA-256.',
          ),
          _folderPath(_folder, 'Output folder'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            enabled: !_acting,
            decoration: const InputDecoration(
              labelText: 'New output ZIP filename',
            ),
            validator: (text) =>
                text == null || !text.toLowerCase().endsWith('.zip')
                ? 'Choose a ZIP filename.'
                : null,
          ),
          _password(_avbPass, 'AVB key passphrase'),
          _password(_otaPass, 'OTA key passphrase'),
          const SizedBox(height: 12),
          const Text(
            'Keys stay on the computer. Passphrases are used for this run and are not saved with the job.',
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_acting) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _acting || !_online || _info == null ? null : _start,
            icon: const Icon(Icons.security),
            label: const Text('Prepare and verify OTA'),
          ),
          const SizedBox(height: 24),
          Text(
            'Preparation jobs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Your preparation jobs will appear here.'),
            ),
          ..._jobs.map(_job),
        ],
      ),
    ),
  );
}
