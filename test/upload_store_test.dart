import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/upload_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UploadStore.channel, null),
  );
  test('upload streams selected bytes and stops at EOF', () async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UploadStore.channel, (call) async {
          if (call.method == 'pick') {
            return {
              'name': 'test.bin',
              'size': 3,
              'uri': 'content://test/file',
            };
          }
          if (call.method == 'read') {
            return reads++ == 0 ? Uint8List.fromList([1, 2, 3]) : Uint8List(0);
          }
          return null;
        });
    expect((await UploadStore.pick())!['size'], 3);
    await UploadStore.open('content://test/file');
    final bytes = await UploadStore.read(() => false).expand((b) => b).toList();
    expect(bytes, [1, 2, 3]);
    await UploadStore.close();
  });
  test('cancelled upload performs no additional native reads', () async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UploadStore.channel, (_) async {
          reads++;
          return Uint8List(0);
        });
    await expectLater(UploadStore.read(() => true).toList(), throwsStateError);
    expect(reads, 0);
  });
}
