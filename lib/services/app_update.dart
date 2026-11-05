import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import 'dart:typed_data' show BytesBuilder;

import '../ssh/ssh_session.dart';

class PreparedUpdate {
  final String id;
  final Map<String, dynamic> details;
  const PreparedUpdate(this.id, this.details);
}

class AppUpdate {
  static const channel = MethodChannel('remote_control/app_update');
  static const defaultWindowsPath =
      'C:/remote_control/build/app/outputs/flutter-apk/node-cockpit-update.apk';
  static const legacyWindowsPath =
      'C:/remote_control/build/app/outputs/flutter-apk/app-debug.apk';

  // Same SSH/SFTP read pipeline, but no Android file writes or APK verification.
  static Future<double> benchmarkNetwork(
    SshSession session,
    String path, {
    required bool Function() cancelled,
    void Function(int, int)? onProgress,
  }) async {
    if (!session.isConnected) {
      throw StateError('Connect to the update PC first.');
    }
    final transfer = _UpdateTransfer(cancelled, 'Download cancelled.');
    try {
      final size = await transfer.open(session, path);
      return await transfer.wait(() async {
        final clock = Stopwatch()..start();
        var count = 0, last = 0;
        await for (final bytes in transfer.read(size)) {
          transfer.checkCancellation();
          count += bytes.length;
          // Give input/cancellation an event-loop turn even for buffered reads.
          if (clock.elapsedMilliseconds - last >= 100 || count == size) {
            await Future<void>.delayed(Duration.zero);
            transfer.checkCancellation();
          }
          if (clock.elapsedMilliseconds - last >= 100 || count == size) {
            onProgress?.call(count, size);
            last = clock.elapsedMilliseconds;
          }
        }
        if (count != size) throw StateError('Incomplete test download.');
        return count /
            (clock.elapsedMicroseconds / 1000000).clamp(0.001, double.infinity);
      });
    } finally {
      await transfer.close();
    }
  }

  static Future<PreparedUpdate> stage(
    Stream<Uint8List> bytes,
    int size, {
    void Function(int)? onProgress,
  }) async {
    final id = await channel.invokeMethod<String>('begin', {'size': size});
    if (id == null) throw StateError('Could not create update download.');
    var received = 0;
    final batch = BytesBuilder(copy: false);
    final progressClock = Stopwatch()..start();
    var lastProgress = -100;
    Future<void> pendingWrite = Future<void>.value();
    Future<void> flush() async {
      if (batch.isEmpty) return;
      final data = batch.takeBytes();
      await pendingWrite;
      pendingWrite = channel
          .invokeMethod<void>('append', {'id': id, 'bytes': data})
          .then((_) {
            received += data.length;
            if (progressClock.elapsedMilliseconds - lastProgress >= 100 ||
                received == size) {
              lastProgress = progressClock.elapsedMilliseconds;
              onProgress?.call(received);
            }
          });
      pendingWrite.ignore();
    }

    try {
      await for (final chunk in bytes) {
        batch.add(chunk);
        if (batch.length >= 512 * 1024) await flush();
      }
      await flush();
      await pendingWrite;
      if (received != size) throw StateError('Incomplete APK download.');
      final details = await channel.invokeMapMethod<String, dynamic>('finish', {
        'id': id,
      });
      if (details == null) throw StateError('APK verification failed.');
      return PreparedUpdate(id, details);
    } catch (_) {
      try {
        await cancel(id);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<PreparedUpdate> download(
    SshSession session,
    String path, {
    required String deviceId,
    required bool Function() cancelled,
    void Function(int, int)? onProgress,
  }) async {
    if (!session.isConnected || session.deviceId != deviceId) {
      throw StateError('Connect to the update PC first.');
    }
    final transfer = _UpdateTransfer(cancelled, 'Update cancelled.');
    try {
      final size = await transfer.open(session, path);
      return await transfer.wait(
        () =>
            stage(
              transfer.read(size),
              size,
              onProgress: (n) => onProgress?.call(n, size),
            ).then((prepared) async {
              // Native staging can finish after cancellation wins the race.
              if (transfer.finished) {
                await cancel(prepared.id);
                throw StateError('Update cancelled.');
              }
              return prepared;
            }),
      );
    } finally {
      await transfer.close();
    }
  }

  static Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});
  static Future<String?> install(String id) =>
      channel.invokeMethod<String>('install', {'id': id});
}

/// Owns one transfer's SFTP channel, never the device's SSH connection.
/// Polling allows cancellation to interrupt setup or a read with no incoming
/// bytes; late setup results are disposed even after their caller has returned.
class _UpdateTransfer {
  final bool Function() _cancelled;
  final String _cancelMessage;
  final _cancelSignal = Completer<void>();
  late final Timer _poller;
  SftpClient? _sftp;
  SftpFile? _file;
  Future<void>? _closingSftp;
  bool _wasCancelled = false, _finished = false;

  _UpdateTransfer(this._cancelled, this._cancelMessage) {
    _poller = Timer.periodic(const Duration(milliseconds: 100), (_) => _poll());
  }

  bool get finished => _finished || _wasCancelled || _cancelled();

  void _poll() {
    if (_finished || _wasCancelled || !_cancelled()) return;
    _wasCancelled = true;
    _cancelSignal.complete();
    // SftpClient.close aborts pending replies immediately. Its SSH channel
    // close acknowledgement can arrive later, so it must not delay Cancel.
    _closeSftp();
  }

  void checkCancellation() {
    _poll();
    if (finished) throw StateError(_cancelMessage);
  }

  Future<T> wait<T>(Future<T> Function() operation) async {
    checkCancellation();
    return await Future.any<T>([
      operation(),
      _cancelSignal.future.then<T>((_) => throw StateError(_cancelMessage)),
    ]);
  }

  Future<int> open(SshSession session, String path) async {
    final sftp = await wait(
      () => session.client!
          .sftp()
          .then((value) {
            if (finished) {
              unawaited(_quietClose(value.close));
              throw StateError(_cancelMessage);
            }
            return _sftp = value;
          })
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw StateError('SFTP did not respond.'),
          ),
    );
    final file = await wait(
      () => sftp
          .open(path.trim().replaceAll('\\', '/'))
          .then((value) {
            if (finished) {
              unawaited(_quietClose(value.close));
              throw StateError(_cancelMessage);
            }
            return _file = value;
          })
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw StateError('APK could not be opened.'),
          ),
    );
    final size = (await wait(
      () => file.stat().timeout(const Duration(seconds: 20)),
    )).size;
    if (size == null || size <= 0 || size > 300 * 1024 * 1024) {
      throw StateError('APK must be between 1 byte and 300 MB.');
    }
    return size;
  }

  Stream<Uint8List> read(int size) => _file!
      .read(length: size, chunkSize: 64 * 1024, maxPendingRequests: 16)
      .timeout(const Duration(seconds: 30))
      .map((chunk) {
        checkCancellation();
        return chunk;
      });

  static Future<void> _quietClose(Future<void> Function() close) async {
    try {
      await close().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  void _closeSftp() {
    final sftp = _sftp;
    if (sftp == null || _closingSftp != null) return;
    _closingSftp = _quietClose(sftp.close);
  }

  Future<void> close() async {
    _poll();
    _finished = true;
    _poller.cancel();
    if (_wasCancelled) {
      _closeSftp();
      return;
    }
    final file = _file;
    if (file != null) await _quietClose(file.close);
    _closeSftp();
    await _closingSftp;
  }
}
