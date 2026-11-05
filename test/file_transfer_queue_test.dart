import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/file_transfer_queue.dart';

void main() {
  test('serializes transfers and continues after failure', () async {
    final queue = FileTransferQueue();
    final gate = Completer<void>();
    final events = <String>[];
    final first = FileTransfer('first', (t) async {
      events.add('first');
      await gate.future;
      throw StateError('offline');
    });
    final second = FileTransfer('second', (t) async {
      events.add('second');
      t.progress(42);
    });
    queue.add(first);
    queue.add(second);
    expect(events, ['first']);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first', 'second']);
    expect(first.state, TransferState.failed);
    expect(second.state, TransferState.completed);
    expect(second.bytes, 42);
    queue.dispose();
  });
  test('cancelled queued jobs never execute, retry starts them', () async {
    final queue = FileTransferQueue();
    final gate = Completer<void>();
    var executed = 0;
    queue.add(FileTransfer('blocker', (_) => gate.future));
    final next = FileTransfer('next', (_) async {
      executed++;
    });
    queue.add(next);
    next.cancel();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(executed, 0);
    expect(next.state, TransferState.cancelled);
    queue.retry(next);
    await Future<void>.delayed(Duration.zero);
    expect(executed, 1);
    expect(next.state, TransferState.completed);
    queue.dispose();
  });
  test('disposal cancels active job and never starts queued job', () async {
    final queue = FileTransferQueue();
    final gate = Completer<void>();
    final first = FileTransfer('first', (_) => gate.future);
    var executed = false;
    queue.add(first);
    queue.add(
      FileTransfer('second', (_) async {
        executed = true;
      }),
    );
    queue.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(first.cancelled, true);
    expect(executed, false);
  });
}
