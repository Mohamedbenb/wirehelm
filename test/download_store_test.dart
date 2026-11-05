import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/download_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('remote_control/downloads');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'begin' ? 'transfer-id' : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('publishes only after all chunks arrive', () async {
    var received = 0;
    await DownloadStore.save(
      'file.bin',
      Stream.fromIterable([Uint8List(3), Uint8List(4)]),
      onProgress: (n) => received = n,
    );
    expect(calls, ['begin', 'append', 'finish']);
    expect(received, 7);
  });
  test('removes partial download on transfer error', () async {
    await expectLater(
      DownloadStore.save(
        'file.bin',
        Stream<Uint8List>.error(StateError('disconnected')),
      ),
      throwsStateError,
    );
    expect(calls, ['begin', 'cancel']);
  });
}
