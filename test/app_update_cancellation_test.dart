import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/app_update.dart';
import 'package:remote_control/ssh/ssh_session.dart';

class _File extends Fake implements SftpFile {
  final readStarted = Completer<void>();
  final statStarted = Completer<void>();
  Future<SftpFileAttrs>? pendingStat;
  int closeCalls = 0;
  late final input = StreamController<Uint8List>(
    onListen: () => readStarted.complete(),
  );

  @override
  Future<SftpFileAttrs> stat() {
    statStarted.complete();
    return pendingStat ?? Future.value(SftpFileAttrs(size: 1024));
  }

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int)? onProgress,
    int chunkSize = 16384,
    int maxPendingRequests = 64,
  }) => input.stream;

  @override
  Future<void> close() async {
    closeCalls++;
  }

  void abortRead() {
    if (input.hasListener) input.addError(StateError('SFTP channel closed'));
    unawaited(input.close());
  }
}

class _Sftp extends Fake implements SftpClient {
  final _File file;
  final openStarted = Completer<void>();
  Future<SftpFile>? pendingOpen;
  Future<void>? closeAcknowledgement;
  int closeCalls = 0;
  _Sftp(this.file);

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) {
    openStarted.complete();
    return pendingOpen ?? Future.value(file);
  }

  @override
  Future<void> close() {
    closeCalls++;
    file.abortRead();
    return closeAcknowledgement ?? Future.value();
  }
}

class _Client extends Fake implements SSHClient {
  final _Sftp sftpClient;
  final sftpStarted = Completer<void>();
  Future<SftpClient>? pendingSftp;
  int closeCalls = 0;
  _Client(this.sftpClient);

  @override
  Future<SftpClient> sftp() {
    sftpStarted.complete();
    return pendingSftp ?? Future.value(sftpClient);
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

class _Session extends Fake implements SshSession {
  @override
  final _Client client;
  _Session(this.client);
  @override
  bool get isConnected => true;
  @override
  String get deviceId => 'device';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdate.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'begin') return 'staged';
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdate.channel, null);
  });

  for (final benchmark in [true, false]) {
    test(
      '${benchmark ? 'benchmark' : 'APK download'} cancels a stalled read without waiting for channel acknowledgement',
      () async {
        final file = _File();
        final sftp = _Sftp(file)
          ..closeAcknowledgement = Completer<void>().future;
        final client = _Client(sftp);
        final session = _Session(client);
        var cancelled = false;
        final Future<Object> result = benchmark
            ? AppUpdate.benchmarkNetwork(
                session,
                '/update.apk',
                cancelled: () => cancelled,
              )
            : AppUpdate.download(
                session,
                '/update.apk',
                deviceId: 'device',
                cancelled: () => cancelled,
              );
        final assertion = expectLater(result, throwsStateError);
        await file.readStarted.future;
        cancelled = true;
        await assertion.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);

        expect(sftp.closeCalls, 1);
        expect(client.closeCalls, 0);
        if (!benchmark) {
          expect(calls, ['begin', 'cancel']);
        }
      },
    );
  }

  test('cancels pending setup and closes a late SFTP client', () async {
    final sftp = _Sftp(_File());
    final opened = Completer<SftpClient>();
    final client = _Client(sftp)..pendingSftp = opened.future;
    var cancelled = false;
    final assertion = expectLater(
      AppUpdate.benchmarkNetwork(
        _Session(client),
        '/update.apk',
        cancelled: () => cancelled,
      ),
      throwsStateError,
    );
    await client.sftpStarted.future;
    cancelled = true;
    await assertion.timeout(const Duration(seconds: 1));
    opened.complete(sftp);
    await Future<void>.delayed(Duration.zero);

    expect(sftp.closeCalls, 1);
    expect(client.closeCalls, 0);
  });

  test('closes a file returned after cancellation interrupted open', () async {
    final file = _File();
    final opened = Completer<SftpFile>();
    final sftp = _Sftp(file)..pendingOpen = opened.future;
    final client = _Client(sftp);
    var cancelled = false;
    final assertion = expectLater(
      AppUpdate.download(
        _Session(client),
        '/update.apk',
        deviceId: 'device',
        cancelled: () => cancelled,
      ),
      throwsStateError,
    );
    await sftp.openStarted.future;
    cancelled = true;
    await assertion.timeout(const Duration(seconds: 1));
    opened.complete(file);
    await Future<void>.delayed(Duration.zero);

    expect(file.closeCalls, 1);
    expect(sftp.closeCalls, 1);
    expect(client.closeCalls, 0);
    expect(calls, isEmpty);
  });

  test(
    'cancels a stalled stat request before any APK staging begins',
    () async {
      final file = _File()..pendingStat = Completer<SftpFileAttrs>().future;
      final sftp = _Sftp(file);
      final client = _Client(sftp);
      var cancelled = false;
      final assertion = expectLater(
        AppUpdate.download(
          _Session(client),
          '/update.apk',
          deviceId: 'device',
          cancelled: () => cancelled,
        ),
        throwsStateError,
      );
      await file.statStarted.future;
      cancelled = true;
      await assertion.timeout(const Duration(seconds: 1));

      expect(sftp.closeCalls, 1);
      expect(client.closeCalls, 0);
      expect(calls, isEmpty);
    },
  );
}
