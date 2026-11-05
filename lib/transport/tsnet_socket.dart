import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import 'tsnet_client.dart';

/// A full duplex SSHSocket: one native read at a time, ordered native writes,
/// and independent close calls that unblock a pending read in Go.
class TsnetSocket implements SSHSocket {
  final TsnetClient _client;
  final int _id;
  final _done = Completer<void>();
  late final StreamController<Uint8List> _incoming;
  late final _TsnetSink _sink;
  Future<void> _writeTail = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  bool _paused = false;
  Completer<void>? _resume;

  TsnetSocket._(this._client, this._id) {
    _done.future.ignore();
    _sink = _TsnetSink(this);
    _incoming = StreamController<Uint8List>(
      onListen: () => unawaited(_readLoop()),
      onCancel: close,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _resume?.complete();
        _resume = null;
      },
    );
  }

  static Future<TsnetSocket> connect(
    String host,
    int port, {
    TsnetClient? client,
  }) async {
    final transport = client ?? TsnetClient.instance;
    return TsnetSocket._(transport, await transport.dial(host, port));
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;
  @override
  StreamSink<List<int>> get sink => _sink;
  @override
  Future<void> get done => _done.future;

  Future<void> _readLoop() async {
    try {
      while (!_closed && _closing == null) {
        if (_paused) {
          _resume ??= Completer<void>();
          await _resume!.future;
          if (_closed || _closing != null) break;
        }
        Uint8List data;
        try {
          data = await _client.read(_id);
        } on PlatformException catch (error) {
          if (error.code == 'TSNET_READ_TIMEOUT') continue;
          rethrow;
        }
        if (_closed || _closing != null) break;
        if (data.isEmpty) {
          await _shutdown();
          break;
        }
        _incoming.add(data);
      }
    } catch (error, stack) {
      if (!_closed && _closing == null) {
        _incoming.addError(error, stack);
        await _shutdown(error, stack);
      }
    }
  }

  void _add(List<int> bytes) {
    if (_closed || _closing != null) throw StateError('Socket is closed');
    final copy = Uint8List.fromList(bytes);
    _writeTail = _writeTail.then((_) async {
      if (_closed) throw StateError('Socket is closed');
      for (var offset = 0; offset < copy.length; offset += 65536) {
        final end = offset + 65536 < copy.length ? offset + 65536 : copy.length;
        await _client.write(_id, Uint8List.sublistView(copy, offset, end));
      }
    });
    unawaited(
      _writeTail.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!_closed) {
            _incoming.addError(error, stack);
            unawaited(_shutdown(error, stack));
          }
        },
      ),
    );
  }

  @override
  Future<void> flush() => _writeTail;

  @override
  Future<void> close() => _closing ??= _gracefulClose();

  Future<void> _gracefulClose() async {
    try {
      await _writeTail;
    } catch (_) {
      // Write failures have already been delivered to the SSH stream.
    }
    await _shutdown();
  }

  Future<void> _shutdown([Object? error, StackTrace? stack]) async {
    if (_closed) return;
    _closed = true;
    _resume?.complete();
    _resume = null;
    try {
      await _client.closeConnection(_id);
    } catch (closeError, closeStack) {
      error ??= closeError;
      stack ??= closeStack;
    }
    unawaited(_incoming.close());
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error, stack);
    }
  }

  @override
  void destroy() => unawaited(_shutdown());
}

class _TsnetSink implements StreamSink<List<int>> {
  final TsnetSocket _socket;
  bool _addingStream = false;
  _TsnetSink(this._socket);

  @override
  void add(List<int> data) {
    if (_addingStream) throw StateError('addStream is in progress');
    _socket._add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_socket._closed || _socket._closing != null) {
      throw StateError('Socket is closed');
    }
    unawaited(_socket._shutdown(error, stackTrace));
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (_addingStream) throw StateError('addStream is in progress');
    _addingStream = true;
    try {
      await for (final data in stream) {
        _socket._add(data);
        await _socket.flush();
      }
    } finally {
      _addingStream = false;
    }
  }

  @override
  Future<void> close() => _socket.close();
  @override
  Future<void> get done => _socket.done;
}
