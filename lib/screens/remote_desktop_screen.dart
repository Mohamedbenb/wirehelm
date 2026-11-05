import 'dart:async';

import 'dart:ui' as ui;

import '../widgets/desktop_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../services/remote_desktop.dart';
import '../services/remote_keyboard.dart';
import '../ssh/ssh_session.dart';

enum _LiveDesktopMenuAction {
  responsive,
  balanced,
  dataSaver,
  directTouch,
  trackpad,
  sensitivityLow,
  sensitivityMedium,
  sensitivityHigh,
}

class RemoteDesktopScreen extends StatefulWidget {
  final Device device;
  final SshSession session;

  const RemoteDesktopScreen({
    super.key,
    required this.device,
    required this.session,
  });

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen>
    with WidgetsBindingObserver {
  RemoteDesktopStream? _stream;
  StreamSubscription<Uint8List>? _frames;
  StreamSubscription<String>? _errors;
  ui.Image? _frame;
  Uint8List? _pendingFrame;
  bool _decodingFrame = false;
  int _generation = 0;
  String? _error;
  bool _starting = false;
  bool _fullScreen = false;
  DesktopInputMode _inputMode = DesktopInputMode.pointer;
  DesktopPointerSensitivity _sensitivity = DesktopPointerSensitivity.high;
  DesktopStreamMode _streamMode = DesktopStreamMode.responsive;
  double _lastTouchX = 0.5, _lastTouchY = 0.5;
  bool get _live => _stream != null && !_starting && _error == null;

  void _releaseFrameAfterPaint(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _restoreScreenChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  }

  Future<void> _setFullScreen(bool enabled) async {
    if (_fullScreen == enabled) return;
    if (enabled) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _restoreScreenChrome();
    }
    if (mounted) setState(() => _fullScreen = enabled);
  }

  Future<void> _start() async {
    if (_starting || _live) return;
    _generation++;
    _pendingFrame = null;
    final previous = _frame;
    setState(() {
      _starting = true;
      _error = null;
      _frame = null;
    });
    _releaseFrameAfterPaint(previous);
    final stream = RemoteDesktopStream(
      device: widget.device,
      session: widget.session,
      mode: _streamMode,
    );
    _stream = stream;
    _frames = stream.frames.listen(
      _onFrame,
      onError: _onError,
      onDone: () {
        if (mounted && _stream == stream && !_starting) {
          setState(() => _error ??= 'Desktop stream ended.');
        }
      },
    );
    _errors = stream.errors.listen(_onError);
    try {
      await stream.start();
      if (mounted && _stream == stream) setState(() => _starting = false);
    } catch (error) {
      if (mounted && _stream == stream) {
        setState(() {
          _starting = false;
          _error = '$error';
        });
      }
      await _disposeStream(stream);
    }
  }

  void _onFrame(Uint8List image) {
    if (!mounted) return;
    _pendingFrame = image;
    if (!_decodingFrame) unawaited(_decodePendingFrame());
  }

  Future<void> _decodePendingFrame() async {
    _decodingFrame = true;
    while (mounted && _pendingFrame != null) {
      final bytes = _pendingFrame!;
      final generation = _generation;
      _pendingFrame = null;
      ui.Codec? codec;
      try {
        codec = await ui.instantiateImageCodec(bytes);
        final decoded = await codec.getNextFrame();

        if (!mounted || generation != _generation) {
          decoded.image.dispose();
          break;
        }
        final previous = _frame;
        setState(() {
          _frame = decoded.image;
          _starting = false;
        });
        _releaseFrameAfterPaint(previous);
      } catch (error) {
        if (mounted) _onError(error);
      } finally {
        codec?.dispose();
      }
    }
    _decodingFrame = false;
  }

  void _onError(Object error) {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = '$error';
    });
    final stream = _stream;
    if (stream != null) unawaited(_disposeStream(stream));
  }

  Future<void> _stop() async {
    final stream = _stream;
    if (stream == null) return;
    _generation++;
    _pendingFrame = null;
    final previous = _frame;
    setState(() {
      _starting = false;

      _frame = null;
    });
    _releaseFrameAfterPaint(previous);
    await _disposeStream(stream);
  }

  Future<void> _sendText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type to desktop'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Text is sent only when you tap Send',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await sendRemoteKeyboard(
        widget.device,
        widget.session,
        windows: _stream?.windows ?? widget.device.shellStyle == 'windows',
        text: text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Text received by the remote device')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _clickAtPointer(String button) async {
    if (!_live) return;
    final action = _inputMode == DesktopInputMode.pointer
        ? 'clickAtCursor'
        : 'click';
    try {
      await _stream?.sendPointer(
        x: _lastTouchX,
        y: _lastTouchY,
        action: action,
        button: button,
      );
    } catch (error) {
      _onError(error);
    }
  }

  Future<void> _changeStreamMode(DesktopStreamMode mode) async {
    if (mode == _streamMode) return;
    final restart = _live;
    if (restart) await _stop();
    if (!mounted) return;
    setState(() => _streamMode = mode);
    if (restart) unawaited(_start());
  }

  Future<void> _disposeStream(RemoteDesktopStream stream) async {
    if (_stream == stream) {
      _stream = null;
      _generation++;
      _pendingFrame = null;
      final frames = _frames;
      final errors = _errors;
      _frames = null;
      _errors = null;
      await frames?.cancel();
      await errors?.cancel();
    }
    await stream.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_stop());
      if (_fullScreen) unawaited(_setFullScreen(false));
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    if (_fullScreen) unawaited(_restoreScreenChrome());
    final stream = _stream;
    if (stream != null) unawaited(_disposeStream(stream));
    _frame?.dispose();
    super.dispose();
  }

  Widget _desktopView(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_frame == null) {
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _error == null
                        ? Icons.desktop_windows_outlined
                        : Icons.desktop_access_disabled_outlined,
                    size: 48,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _starting
                        ? 'Connecting to the desktop…'
                        : _error == null
                        ? 'Live desktop is off'
                        : 'Could not start live view',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (!_starting && !_live) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_error == null ? 'Start live view' : 'Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return DesktopSurface(
        image: _frame!,
        enabled: _live,
        mode: _inputMode,
        sensitivity: _sensitivity,
        onPointer: (x, y, action, button, delta, deltaX, deltaY) {
          if (!_live) return;
          if (action != 'relative' &&
              action != 'clickAtCursor' &&
              action != 'downAtCursor' &&
              action != 'upAtCursor') {
            _lastTouchX = x;
            _lastTouchY = y;
          }
          unawaited(
            _stream
                ?.sendPointer(
                  x: x,
                  y: y,
                  action: action,
                  button: button,
                  delta: delta,
                  deltaX: deltaX,
                  deltaY: deltaY,
                )
                .catchError(_onError),
          );
        },
      );
    },
  );

  Widget _fullScreenView(BuildContext context) => PopScope(
    canPop: !_fullScreen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _fullScreen) unawaited(_setFullScreen(false));
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _desktopView(context),
          if (_starting)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_live)
                    IconButton.filledTonal(
                      tooltip: 'Type text',
                      onPressed: _sendText,
                      icon: const Icon(Icons.keyboard_outlined),
                    ),
                  if (_frame != null) _optionsMenuButton(fullscreen: true),
                  if (_live)
                    IconButton.filledTonal(
                      tooltip: 'Stop live desktop',
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  IconButton.filledTonal(
                    tooltip: 'Exit full screen',
                    onPressed: () => _setFullScreen(false),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ],
              ),
            ),
          ),
          if (_live)
            Positioned(
              left: 8,
              bottom: 8,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Left click',
                      onPressed: () => _clickAtPointer('left'),
                      icon: const Icon(Icons.ads_click),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Right click',
                      onPressed: () => _clickAtPointer('right'),
                      icon: const Icon(Icons.mouse_outlined),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  void _onMenuSelected(_LiveDesktopMenuAction action) {
    switch (action) {
      case _LiveDesktopMenuAction.responsive:
        unawaited(_changeStreamMode(DesktopStreamMode.responsive));
      case _LiveDesktopMenuAction.balanced:
        unawaited(_changeStreamMode(DesktopStreamMode.balanced));
      case _LiveDesktopMenuAction.dataSaver:
        unawaited(_changeStreamMode(DesktopStreamMode.dataSaver));
      case _LiveDesktopMenuAction.directTouch:
        setState(() => _inputMode = DesktopInputMode.touch);
      case _LiveDesktopMenuAction.trackpad:
        setState(() => _inputMode = DesktopInputMode.pointer);
      case _LiveDesktopMenuAction.sensitivityLow:
        setState(() => _sensitivity = DesktopPointerSensitivity.low);
      case _LiveDesktopMenuAction.sensitivityMedium:
        setState(() => _sensitivity = DesktopPointerSensitivity.medium);
      case _LiveDesktopMenuAction.sensitivityHigh:
        setState(() => _sensitivity = DesktopPointerSensitivity.high);
    }
  }

  Future<void> _showOptionsDialog() => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.55;
      Widget heading(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
      Widget choice(
        String title,
        bool selected,
        _LiveDesktopMenuAction action,
      ) => ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(title),
        trailing: selected
            ? Icon(Icons.check, color: theme.colorScheme.primary)
            : null,
        onTap: () {
          Navigator.pop(dialogContext);
          _onMenuSelected(action);
        },
      );

      return AlertDialog(
        title: const Text('Live desktop options'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  heading('Stream quality'),
                  choice(
                    'Fast response · 960 px, up to 30 fps',
                    _streamMode == DesktopStreamMode.responsive,
                    _LiveDesktopMenuAction.responsive,
                  ),
                  choice(
                    'Balanced · 1280 px, 8 fps',
                    _streamMode == DesktopStreamMode.balanced,
                    _LiveDesktopMenuAction.balanced,
                  ),
                  choice(
                    'Data saver · 640 px, 4 fps',
                    _streamMode == DesktopStreamMode.dataSaver,
                    _LiveDesktopMenuAction.dataSaver,
                  ),
                  const Divider(height: 12),
                  heading('Pointer control'),
                  choice(
                    'Trackpad',
                    _inputMode == DesktopInputMode.pointer,
                    _LiveDesktopMenuAction.trackpad,
                  ),
                  choice(
                    'Direct touch',
                    _inputMode == DesktopInputMode.touch,
                    _LiveDesktopMenuAction.directTouch,
                  ),
                  const Divider(height: 12),
                  heading('Trackpad sensitivity'),
                  for (final sensitivity in DesktopPointerSensitivity.values)
                    choice(
                      sensitivity.label,
                      sensitivity == _sensitivity,
                      switch (sensitivity) {
                        DesktopPointerSensitivity.low =>
                          _LiveDesktopMenuAction.sensitivityLow,
                        DesktopPointerSensitivity.medium =>
                          _LiveDesktopMenuAction.sensitivityMedium,
                        DesktopPointerSensitivity.high =>
                          _LiveDesktopMenuAction.sensitivityHigh,
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );

  Widget _optionsMenuButton({bool fullscreen = false}) => fullscreen
      ? IconButton.filledTonal(
          tooltip: 'Stream, pointer and sensitivity options',
          onPressed: _showOptionsDialog,
          icon: const Icon(Icons.tune),
        )
      : IconButton(
          tooltip: 'Stream, pointer and sensitivity options',
          onPressed: _showOptionsDialog,
          icon: const Icon(Icons.tune),
        );

  @override
  Widget build(BuildContext context) {
    if (_fullScreen) return _fullScreenView(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live desktop'),
        actions: [
          if (_frame != null)
            IconButton(
              tooltip: 'Type text',
              onPressed: _live ? _sendText : null,
              icon: const Icon(Icons.keyboard_outlined),
            ),
          if (_frame != null)
            IconButton(
              tooltip: 'Full screen · landscape',
              onPressed: () => _setFullScreen(true),
              icon: const Icon(Icons.fullscreen),
            ),
          if (_frame != null) _optionsMenuButton(),
          if (_starting || _live)
            IconButton(
              tooltip: 'Stop live desktop',
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_starting) const LinearProgressIndicator(),
            Expanded(child: _desktopView(context)),
            if (_live)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _clickAtPointer('left'),
                      icon: const Icon(Icons.ads_click),
                      label: const Text('Left click'),
                    ),
                    TextButton.icon(
                      onPressed: () => _clickAtPointer('right'),
                      icon: const Icon(Icons.mouse_outlined),
                      label: const Text('Right click'),
                    ),
                  ],
                ),
              ),
            if (_frame != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: _error == null ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error != null
                            ? 'Live view stopped. Tap Details for the error.'
                            : _inputMode == DesktopInputMode.pointer
                            ? 'Trackpad: swipe to move · tap to click in place · double-tap and hold to drag · ${_sensitivity.label}'
                            : 'Direct touch: tap to click, drag to move items · right-click button',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_error != null)
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Live desktop error'),
                            content: SingleChildScrollView(
                              child: SelectableText(_error!),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Details'),
                      ),
                    if (_error != null)
                      TextButton(onPressed: _start, child: const Text('Retry')),
                  ],
                ),
              ),
            if (_frame == null && !_starting && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  'The stream uses your encrypted SSH connection and stops when you leave the screen or after 10 minutes. Start it only when you want to view and control the signed-in desktop.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
