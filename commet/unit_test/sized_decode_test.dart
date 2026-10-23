// Vommet: the target size the WebAssembly build scales to itself where the
// engine would crop (Firefox), see utils/image/sized_decode.dart.
import 'dart:ui';

import 'package:commet/utils/image/sized_decode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a height target keeps the aspect ratio', () {
    expect(scaledSize(90, 90, const TargetImageSize(height: 64)), (64, 64));
    expect(
        scaledSize(300, 200, const TargetImageSize(height: 100)), (150, 100));
    expect(scaledSize(200, 300, const TargetImageSize(width: 100)), (100, 150));
  });

  test('never upscales (a 90 px thumbnail asked for 128 px stays 90 px)', () {
    expect(scaledSize(90, 90, const TargetImageSize(height: 128)), isNull);
    expect(scaledSize(90, 90, const TargetImageSize(width: 128, height: 64)),
        isNull);
  });

  test('no target or the same size keeps the image', () {
    expect(scaledSize(90, 90, null), isNull);
    expect(scaledSize(90, 90, const TargetImageSize()), isNull);
    expect(scaledSize(90, 60, const TargetImageSize(height: 60)), isNull);
  });

  test('both sides given', () {
    expect(
        scaledSize(1000, 500, const TargetImageSize(width: 400, height: 200)),
        (400, 200));
  });
}
