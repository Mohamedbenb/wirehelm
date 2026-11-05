import 'dart:async';

import 'package:flutter/foundation.dart';

enum TransferState { queued, running, completed, cancelled, failed }

class FileTransfer extends ChangeNotifier {
  FileTransfer(this.name, this.run);
  final String name;
  final Future<void> Function(FileTransfer transfer) run;
  TransferState state = TransferState.queued;
  int bytes = 0;
  int? total;
  String? error;
  bool cancelled = false;
  final clock = Stopwatch();
  double get bytesPerSecond => clock.elapsedMilliseconds == 0
      ? 0
      : bytes * 1000 / clock.elapsedMilliseconds;
  void progress(int count) {
    bytes = count;
    notifyListeners();
  }

  void cancel() {
    cancelled = true;
    notifyListeners();
  }
}

class FileTransferQueue extends ChangeNotifier {
  final List<FileTransfer> items = [];
  bool _running = false, _closed = false;
  Completer<void>? _idle;
  Future<void> cancelAll() async {
    for (final t in items) {
      t.cancel();
    }
    await _idle?.future;
  }

  bool get active => _running;
  void add(FileTransfer transfer) {
    if (_closed) return;
    items.add(transfer);
    transfer.addListener(notifyListeners);
    notifyListeners();
    unawaited(_drain());
  }

  void retry(FileTransfer transfer) {
    if (transfer.state != TransferState.failed &&
        transfer.state != TransferState.cancelled) {
      return;
    }
    transfer.cancelled = false;
    transfer.error = null;
    transfer.bytes = 0;
    transfer.state = TransferState.queued;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_running || _closed) return;
    _running = true;
    _idle = Completer<void>();
    try {
      while (!_closed) {
        final pending = items.where((t) => t.state == TransferState.queued);
        if (pending.isEmpty) break;
        final t = pending.first;
        if (t.cancelled) {
          t.state = TransferState.cancelled;
          continue;
        }
        t.state = TransferState.running;
        t.clock
          ..reset()
          ..start();
        notifyListeners();
        try {
          await t.run(t);
          t.state = t.cancelled
              ? TransferState.cancelled
              : TransferState.completed;
        } catch (e) {
          t.state = t.cancelled
              ? TransferState.cancelled
              : TransferState.failed;
          t.error = '$e';
        } finally {
          t.clock.stop();
        }
        if (!_closed) notifyListeners();
      }
    } finally {
      _running = false;
      _idle?.complete();
      _idle = null;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    for (final t in items) {
      t.cancel();
      t.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
