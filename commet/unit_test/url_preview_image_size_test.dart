import 'package:commet/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 336: a link preview naming a huge image (a 250 MB animated PNG)
// crashed the app. Oversized images are left out, the rest decode capped.
void main() {
  int? decodeHeight({int? bytes, int? width, int? height}) =>
      MatrixUrlPreviewComponent.previewImageDecodeHeight(
          bytes: bytes, width: width, height: height);

  test("images over the byte limit are skipped", () {
    expect(decodeHeight(bytes: 250 * 1024 * 1024, width: 640, height: 480),
        isNull);
    expect(
        decodeHeight(
            bytes: MatrixUrlPreviewComponent.maxPreviewImageBytes + 1,
            width: 640,
            height: 480),
        isNull);
    expect(
        decodeHeight(
            bytes: MatrixUrlPreviewComponent.maxPreviewImageBytes,
            width: 640,
            height: 480),
        480);
  });

  test("images with too many pixels are skipped", () {
    expect(decodeHeight(bytes: 1000, width: 20000, height: 20000), isNull);
    expect(decodeHeight(width: 1000000, height: 100), isNull);
  });

  test("small images decode at their own height", () {
    expect(decodeHeight(bytes: 50000, width: 1200, height: 630), 630);
    expect(decodeHeight(width: 2048, height: 2048), 2048);
  });

  test("large images decode with their longest side capped", () {
    expect(decodeHeight(width: 4096, height: 2048), 1024);
    expect(decodeHeight(width: 2000, height: 8000), 2048);
    // A very wide strip stays at least one pixel high.
    expect(decodeHeight(width: 8000, height: 1), 1);
  });

  test("unknown size or dimensions fall back to a fixed decode height", () {
    expect(decodeHeight(), MatrixUrlPreviewComponent.unknownPreviewImageHeight);
    expect(decodeHeight(bytes: 1000, width: 640),
        MatrixUrlPreviewComponent.unknownPreviewImageHeight);
    expect(decodeHeight(width: 0, height: 0),
        MatrixUrlPreviewComponent.unknownPreviewImageHeight);
  });
}
