import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import '../services/remote_screenshot.dart';

class RemoteScreenshotScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  const RemoteScreenshotScreen({
    super.key,
    required this.device,
    required this.session,
  });
  @override
  State<RemoteScreenshotScreen> createState() => _RemoteScreenshotScreenState();
}

class _RemoteScreenshotScreenState extends State<RemoteScreenshotScreen> {
  Uint8List? _image;
  RemoteScreenshotCapture? _remoteCapture;
  String? _error;
  bool _busy = false;
  int _downloaded = 0;
  @override
  void initState() {
    super.initState();
    _capture();
  }

  Future<void> _capture() async {
    final previous = _remoteCapture;
    _remoteCapture = null;
    if (previous != null) {
      unawaited(cleanupRemoteScreenshot(widget.session, previous));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capture = await takeRemoteScreenshot(widget.device, widget.session);
      if (mounted) {
        setState(() {
          _remoteCapture = capture;
          _image = capture.preview;
        });
      } else {
        unawaited(cleanupRemoteScreenshot(widget.session, capture));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
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

  Future<void> _save() async {
    final capture = _remoteCapture;
    if (capture == null) return;
    setState(() {
      _busy = true;
      _downloaded = 0;
    });
    try {
      await downloadOriginalScreenshot(widget.session, capture, (received) {
        if (mounted) setState(() => _downloaded = received);
      });
      if (mounted) setState(() => _remoteCapture = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Downloads/Node Cockpit')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
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

  @override
  void dispose() {
    final capture = _remoteCapture;
    if (capture != null) {
      unawaited(cleanupRemoteScreenshot(widget.session, capture));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.device.name} screenshot'),
      actions: [
        IconButton(
          tooltip: 'Take screenshot',
          onPressed: _busy ? null : _capture,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Showing a smaller preview. Download retrieves the original full-resolution PNG.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_image != null && _error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_error!),
            ),
          Expanded(
            child: _image == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _error == null
                              ? Icons.screenshot_monitor
                              : Icons.broken_image_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _busy
                              ? 'Taking screenshot…'
                              : _error == null
                              ? 'No screenshot yet'
                              : 'Screenshot failed',
                        ),
                        if (!_busy && _error != null) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SelectableText(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _capture,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  )
                : InteractiveViewer(
                    minScale: 0.1,
                    maxScale: 8,
                    child: Center(
                      child: Image.memory(
                        _image!,
                        errorBuilder: (_, error, stack) =>
                            Text('Cannot display screenshot: $error'),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _image == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.download),
                label: Text(
                  _busy
                      ? (_downloaded > 0
                            ? 'Downloaded ${(_downloaded / (1024 * 1024)).toStringAsFixed(1)} MB…'
                            : 'Downloading original…')
                      : 'Download original screenshot',
                ),
              ),
            ),
          ),
  );
}
