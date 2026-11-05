import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/utils/file_size.dart';
void main() {
  test('file sizes choose readable units including unknown and zero', () {
    expect(formatFileSize(null), 'Unknown size');
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(1023), '1023 B');
    expect(formatFileSize(1024), '1.0 KB');
    expect(formatFileSize(1536), '1.5 KB');
    expect(formatFileSize(1048576), '1.0 MB');
    expect(formatFileSize(1073741824), '1.0 GB');
  });
  test('image extensions are case insensitive', () {
    expect(isPreviewImage('photo.JPEG'), true);
    expect(isPreviewImage('photo.webp'), true);
    expect(isPreviewImage('photo.txt'), false);
    expect(isPreviewImage('file'), false);
  });
}
