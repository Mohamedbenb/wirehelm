import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_ignore.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:flutter_test/flutter_test.dart';

class _BufferedSocket implements SSHSocket {
  final input = StreamController<Uint8List>();
  final output = StreamController<List<int>>();
  final completion = Completer<void>();
  _BufferedSocket() {
    output.stream.listen((_) {});
  }
  @override
  Stream<Uint8List> get stream => input.stream;
  @override
  StreamSink<List<int>> get sink => output.sink;
  @override
  Future<void> get done => completion.future;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {
    if (completion.isCompleted) return;
    completion.complete();
    await input.close();
    await output.close();
  }

  @override
  void destroy() {
    unawaited(close());
  }
}

void main() {
  test(
    'buffered SSH packets yield to timers before the backlog is drained',
    () async {
      const total = 10000;
      final socket = _BufferedSocket();
      final heartbeat = Completer<int>();
      final drained = Completer<void>();
      var processed = 0;
      final transport = SSHTransport(
        socket,
        printTrace: (line) {
          if (line?.contains('SSH_Message_Ignore') != true) return;
          processed++;
          if (processed == 1) Timer.run(() => heartbeat.complete(processed));
          if (processed == total) drained.complete();
        },
      );
      final packet = SSHPacket.pack(
        SSH_Message_Ignore.empty().encode(),
        align: 8,
      );
    final buffer = BytesBuilder(copy: false);
      for (var i = 0; i < total; i++) {
        buffer.add(packet);
      }
    try {
      socket.input.add(Uint8List.fromList(utf8.encode('SSH-2.0-FairnessTest\r\n')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.remoteVersion, isNotNull);
      socket.input.add(buffer.takeBytes());
        final atHeartbeat = await heartbeat.future.timeout(
          const Duration(seconds: 10),
        );
        expect(
          atHeartbeat,
          lessThan(total),
          reason:
              'Timer/input events must run while SSH packets remain buffered.',
        );
        await drained.future.timeout(const Duration(seconds: 10));
        expect(processed, total);
      } finally {
        transport.close();
        await socket.close();
      }
    },
  );
}
