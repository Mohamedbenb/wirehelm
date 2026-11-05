import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/services/app_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var reject = false;
  setUp(() {
    calls.clear();
    reject = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdate.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'begin') return 'id';
          if (call.method == 'finish') {
            if (reject) {
              throw PlatformException(
                code: 'UPDATE_FAILED',
                message: 'Signing key mismatch',
              );
            }
            return {'version': '1.0.0', 'build': 2};
          }
          if (call.method == 'install') return 'permission_required';
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdate.channel, null),
  );
  test('streams APK and validates before installation is requested', () async {
    final result = await AppUpdate.stage(
      Stream.fromIterable([Uint8List(3), Uint8List(4)]),
      7,
    );
    expect(result.id, 'id');
    expect(calls, ['begin', 'append', 'finish']);
    expect(await AppUpdate.install(result.id), 'permission_required');
  });
  test(
    'one MB in 16 KB network packets needs only two native writes',
    () async {
      var received = 0;
      await AppUpdate.stage(
        Stream.fromIterable(List.generate(64, (_) => Uint8List(16384))),
        1048576,
        onProgress: (n) => received = n,
      );
      expect(calls.where((c) => c == 'append').length, 2);
      expect(received, 1048576);
    },
  );
  test('incomplete and disconnected transfers discard their APK', () async {
    await expectLater(
      AppUpdate.stage(Stream.value(Uint8List(3)), 7),
      throwsStateError,
    );
    expect(calls, ['begin', 'append', 'cancel']);
    calls.clear();
    await expectLater(
      AppUpdate.stage(Stream<Uint8List>.error(StateError('Disconnected')), 7),
      throwsStateError,
    );
    expect(calls, ['begin', 'cancel']);
  });
  test('native verification refusal never enables an installation', () async {
    reject = true;
    await expectLater(
      AppUpdate.stage(Stream.value(Uint8List(7)), 7),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.last, 'cancel');
    expect(calls, isNot(contains('install')));
  });
}
