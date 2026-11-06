import 'package:commet/utils/image_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('share file name keeps a plain name', () {
    expect(ImageShare.shareFileName("cat.jpg", "jpg"), "cat.jpg");
  });

  test('share file name falls back to image.<ext>', () {
    expect(ImageShare.shareFileName(null, "png"), "image.png");
    expect(ImageShare.shareFileName("  ", "png"), "image.png");
    expect(ImageShare.shareFileName("..", "png"), "image.png");
  });

  test('share file name adds a missing extension', () {
    expect(ImageShare.shareFileName("holiday", "webp"), "holiday.webp");
  });

  test('share file name drops folders', () {
    expect(ImageShare.shareFileName("../../etc/x.png", "png"), "x.png");
    expect(ImageShare.shareFileName(r"a\b\c.gif", "gif"), "c.gif");
  });
}
