// Vommet: small pictures in a mosaic aren't blown up past their own size.

import 'package:commet/ui/molecules/timeline_events/media_mosaic.dart';
import 'package:commet/utils/mosaic_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("two small screenshots would be enlarged in a full-width mosaic", () {
    final layout = Mosaic.layout([1.5, 1.5], maxWidth: 500);
    final upscale = MediaMosaic.largestUpscale(
        layout, const [Size(150, 100), Size(150, 100)], 1);
    expect(upscale, greaterThan(1));

    final shrunk = Mosaic.layout([1.5, 1.5],
        maxWidth: 500 / upscale,
        targetRowHeight: 160 / upscale,
        maxRowHeight: 240 / upscale);
    expect(
        MediaMosaic.largestUpscale(
            shrunk, const [Size(150, 100), Size(150, 100)], 1),
        lessThanOrEqualTo(1.05));
  });

  test("big photos and unknown sizes are left alone", () {
    final layout = Mosaic.layout([1.5, 0.75], maxWidth: 500);
    expect(
        MediaMosaic.largestUpscale(layout, const [Size(4032, 2688), null], 2.5),
        1);
  });

  test("a high-density screen counts physical pixels", () {
    final layout = Mosaic.layout([1.0, 1.0], maxWidth: 400);
    // 600 px square on a 3x screen is 200 logical px.
    final upscale = MediaMosaic.largestUpscale(
        layout, const [Size(600, 600), Size(600, 600)], 3);
    expect(upscale, closeTo(layout.tiles.first.width / 200, 0.01));
  });
}
