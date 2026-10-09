import 'package:commet/utils/image/decode_limits.dart';
import 'package:test/test.dart';

void main() {
  test("tall screenshot keeps a readable width in the timeline", () {
    final size = ImageDecodeLimits.linuxTimeline.fit(800, 19600)!;
    // A height-only cap of 1440 gave 59 px.
    expect(size.width, greaterThan(300));
    expect(size.width * size.height, lessThanOrEqualTo(1920 * 1440));
    expect(size.height / size.width, closeTo(19600 / 800, 0.1));
  });

  test("tall screenshot is near full width in the viewer", () {
    final size = ImageDecodeLimits.linuxViewer.fit(800, 19600)!;
    expect(size.height, lessThanOrEqualTo(16384));
    expect(size.width, greaterThanOrEqualTo(660));
  });

  test("small images are decoded at their own size", () {
    expect(ImageDecodeLimits.linuxTimeline.fit(1920, 1080), isNull);
    expect(ImageDecodeLimits.linuxViewer.fit(800, 600), isNull);
  });

  test("a large photo is scaled down evenly", () {
    final size = ImageDecodeLimits.linuxTimeline.fit(8000, 6000)!;
    expect(size.width * size.height, lessThanOrEqualTo(1920 * 1440));
    expect(size.width / size.height, closeTo(8000 / 6000, 0.01));
  });

  test("a very wide image is capped by its longest side", () {
    final size = ImageDecodeLimits.linuxViewer.fit(40000, 300)!;
    expect(size.width, lessThanOrEqualTo(16384));
    expect(size.height, greaterThanOrEqualTo(1));
  });

  test("no limits never scales", () {
    expect(const ImageDecodeLimits().fit(50000, 50000), isNull);
    expect(ImageDecodeLimits.linuxViewer.fit(0, 100), isNull);
  });
}
