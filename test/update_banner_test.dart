import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/widgets/app_update_banner.dart';

void main() {
  test('banner only offers a strictly newer build', () {
    expect(newerUpdateBuild('{"version":"1.0.0","build":6}', 5), 6);
    expect(newerUpdateBuild('{"version":"1.0.0","build":5}', 5), isNull);
    expect(newerUpdateBuild('{"version":"1.0.0","build":4}', 5), isNull);
    expect(newerUpdateBuild('{"version":"1.0.0","build":"6"}', 5), isNull);
    expect(newerUpdateBuild('{}', 5), isNull);
  });
}
