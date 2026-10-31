import 'package:commet/utils/download_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("DownloadUtils.freeFileName (mosaic Save all)", () {
    test("keeps a free name", () {
      expect(
          DownloadUtils.freeFileName("photo.jpg", (_) => false), "photo.jpg");
    });

    test("numbers a taken name before its extension", () {
      final taken = {"photo.jpg", "photo (2).jpg"};
      expect(DownloadUtils.freeFileName("photo.jpg", taken.contains),
          "photo (3).jpg");
    });

    test("numbers a name without an extension", () {
      expect(
          DownloadUtils.freeFileName("image", {"image"}.contains), "image (2)");
    });

    test("keeps the file in its folder", () {
      expect(DownloadUtils.freeFileName("../a/b\\c.png", (_) => false),
          ".._a_b_c.png");
      expect(DownloadUtils.freeFileName("  ", (_) => false), "untitled");
    });
  });
}
