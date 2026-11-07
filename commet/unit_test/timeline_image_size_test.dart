import 'dart:ui';

import 'package:commet/config/timeline_image_size.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 721: the Image size in the timeline setting.
void main() {
  test('unknown or missing values read as Default', () {
    expect(TimelineImageSize.parse(""), TimelineImageSize.standard);
    expect(TimelineImageSize.parse("huge"), TimelineImageSize.standard);
    expect(TimelineImageSize.parse("large"), TimelineImageSize.large);
  });

  test('Default keeps the old 500 x 200 limit at any window size', () {
    for (final window in [const Size(1280, 800), const Size(360, 780)]) {
      expect(TimelineImageSize.standard.maxPictureSize(window),
          const Size(500, 200));
    }
    expect(TimelineImageSize.standard.maxMosaicWidth, 500);
    expect(TimelineImageSize.standard.mosaicRowScale, 1);
    expect(TimelineImageSize.standard.sharpWidth, 500);
  });

  test('Large fills the width and stays under the window height', () {
    final desktop =
        TimelineImageSize.large.maxPictureSize(const Size(1280, 800));
    expect(desktop.width, double.infinity);
    expect(desktop.height, 600); // three quarters of a landscape window

    final phone = TimelineImageSize.large.maxPictureSize(const Size(360, 780));
    expect(phone.height, closeTo(468, 0.001)); // 60% of an upright phone

    // Never smaller than Default, even in a very short window.
    expect(TimelineImageSize.large.maxPictureSize(const Size(900, 200)).height,
        200);
  });
}
