import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef DesktopPointerCallback = void Function(
  double x,
  double y,
  String action,
  String button,
  int delta,
  double deltaX,
  double deltaY,
);

enum DesktopInputMode { touch, pointer }

enum DesktopPointerSensitivity {
  low(1.0, 'Low · 1×'),
  medium(1.75, 'Medium · 1.75×'),
  high(2.75, 'High · 2.75×');

  const DesktopPointerSensitivity(this.scale, this.label);

  final double scale;
  final String label;
}

/// The input target is exactly the rendered image, excluding letterboxing.
class DesktopSurface extends StatefulWidget {
  final ui.Image image;
  final bool enabled;
  final DesktopInputMode mode;
  final DesktopPointerSensitivity sensitivity;
  final DesktopPointerCallback onPointer;

  const DesktopSurface({
    super.key,
    required this.image,
    required this.enabled,
    this.mode = DesktopInputMode.touch,
    this.sensitivity = DesktopPointerSensitivity.high,
    required this.onPointer,
  });

  @override
  State<DesktopSurface> createState() => _DesktopSurfaceState();
}

class _DesktopSurfaceState extends State<DesktopSurface> {
  static const _movementThreshold = 12.0;
  static const _holdToDragDelay = Duration(milliseconds: 450);
  static const _doubleTapInterval = Duration(milliseconds: 600);
  static const _moveInterval = Duration(milliseconds: 20);

  Offset _last = const Offset(0.5, 0.5);
  Offset? _downPosition;
  Offset? _previousPosition;
  Size? _activeSize;
  int? _activePointer;
  bool _moved = false;
  bool _dragging = false;
  DateTime? _lastMove;
  DateTime? _lastTapAt;
  Timer? _holdTimer;

  Offset _normalized(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _send(Offset point, Size size, String action, {int delta = 0}) {
    if (!widget.enabled) return;
    _last = _normalized(point, size);
    widget.onPointer(_last.dx, _last.dy, action, 'left', delta, 0, 0);
  }

  void _sendRelative(Offset movement, Size size) {
    if (!widget.enabled) return;
    widget.onPointer(
      _last.dx,
      _last.dy,
      'relative',
      'left',
      0,
      movement.dx / size.width * widget.sensitivity.scale,
      movement.dy / size.height * widget.sensitivity.scale,
    );
  }

  void _sendButtonAtCursor(String action) =>
      widget.onPointer(_last.dx, _last.dy, action, 'left', 0, 0, 0);

  void _startHoldDrag() {
    if (!widget.enabled || _activePointer == null || _moved || _dragging) {
      return;
    }
    final start = _downPosition;
    final size = _activeSize;
    if (start == null || size == null) return;
    _lastTapAt = null;
    _dragging = true;
    if (widget.mode == DesktopInputMode.pointer) {
      _sendButtonAtCursor('downAtCursor');
    } else {
      _send(start, size, 'down');
    }
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (!widget.enabled || _activePointer != null) return;
    _activePointer = event.pointer;
    _downPosition = event.localPosition;
    _previousPosition = event.localPosition;
    _activeSize = size;
    _moved = false;
    _dragging = false;
    _holdTimer?.cancel();
    final previousTapAt = _lastTapAt;
    final isTapAndHoldDrag =
        widget.mode == DesktopInputMode.pointer &&
        previousTapAt != null &&
        DateTime.now().difference(previousTapAt) <= _doubleTapInterval;
    if (isTapAndHoldDrag) {
      // Within the double-click window, retain the first tap's cursor location.
      // A press-and-move from here is the trackpad's double-tap drag gesture.
      _lastTapAt = null;
      _dragging = true;
      _sendButtonAtCursor('downAtCursor');
    } else if (widget.mode == DesktopInputMode.pointer) {
      _holdTimer = Timer(_holdToDragDelay, _startHoldDrag);
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _activePointer || !widget.enabled) return;
    final previous = _previousPosition ?? event.localPosition;
    _last = _normalized(event.localPosition, size);
    final start = _downPosition;
    if (!_moved &&
        start != null &&
        (event.localPosition - start).distance >= _movementThreshold) {
      _moved = true;
      _holdTimer?.cancel();
      if (widget.mode == DesktopInputMode.touch) {
        _dragging = true;
        _send(start, size, 'down');
      }
    }

    if (_moved || _dragging) {
      final now = DateTime.now();
      if (_lastMove == null || now.difference(_lastMove!) >= _moveInterval) {
        _lastMove = now;
        if (widget.mode == DesktopInputMode.pointer) {
          _sendRelative(event.localPosition - previous, size);
        } else {
          _send(event.localPosition, size, 'move');
        }
      }
    }
    _previousPosition = event.localPosition;
  }

  void _finishPointer(int pointer, Offset position, Size size) {
    if (pointer != _activePointer) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    final previous = _previousPosition ?? position;
    _last = _normalized(position, size);
    if (_dragging) {
      if (_moved) {
        if (widget.mode == DesktopInputMode.pointer) {
          _sendRelative(position - previous, size);
        } else {
          _send(position, size, 'move');
        }
      }
      _sendButtonAtCursor(
        widget.mode == DesktopInputMode.pointer ? 'upAtCursor' : 'up',
      );
    } else if (!_moved && widget.enabled) {
      if (widget.mode == DesktopInputMode.pointer) {
        // A trackpad tap clicks at the existing desktop cursor. The finger
        // location controls relative movement only; it must not teleport.
        _sendButtonAtCursor('clickAtCursor');
        _lastTapAt = DateTime.now();
      } else {
        _send(position, size, 'click');
      }
    } else if (_moved && widget.mode == DesktopInputMode.pointer) {
      // Flush any final relative movement if it fell inside the move throttle.
      _sendRelative(position - previous, size);
    }
    _clearPointer();
  }

  void _clearPointer() {
    _activePointer = null;
    _downPosition = null;
    _previousPosition = null;
    _activeSize = null;
    _moved = false;
    _dragging = false;
    _lastMove = null;
  }

  void _cancelPointer(int pointer) {
    if (pointer != _activePointer) return;
    _holdTimer?.cancel();
    if (_dragging) {
      _sendButtonAtCursor(
        widget.mode == DesktopInputMode.pointer ? 'upAtCursor' : 'up',
      );
    }
    _clearPointer();
  }

  @override
  void didUpdateWidget(DesktopSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.enabled && oldWidget.enabled) ||
        widget.mode != oldWidget.mode) {
      _lastTapAt = null;
      final pointer = _activePointer;
      if (pointer != null) _cancelPointer(pointer);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (_dragging) {
      _sendButtonAtCursor(
        widget.mode == DesktopInputMode.pointer ? 'upAtCursor' : 'up',
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = math.min(
        constraints.maxWidth / widget.image.width,
        constraints.maxHeight / widget.image.height,
      );
      final size = Size(
        widget.image.width * scale,
        widget.image.height * scale,
      );
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _onPointerDown(event, size),
              onPointerMove: (event) => _onPointerMove(event, size),
              onPointerUp: (event) =>
                  _finishPointer(event.pointer, event.localPosition, size),
              onPointerCancel: (event) => _cancelPointer(event.pointer),
              onPointerSignal: (event) {
                if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                  _send(
                    event.localPosition,
                    size,
                    'wheel',
                    delta: event.scrollDelta.dy.round(),
                  );
                }
              },
              child: RawImage(image: widget.image, fit: BoxFit.fill),
            ),
          ),
        ),
      );
    },
  );
}
