import 'dart:ui';

import 'package:commet/ui/molecules/room_timeline_widget/reply_jump.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const view = Rect.fromLTRB(0, 100, 400, 700);

  test('centers a target that fits', () {
    expect(ReplyJump.alignmentFor(200, 600), 0.5);
    // Bottom on the anchor line at 0: half the free space below it.
    expect(ReplyJump.anchoredOffset(200, 600), -200);
  });

  test('top-aligns a target taller than the view', () {
    expect(ReplyJump.alignmentFor(900, 600), 1.0);
    expect(ReplyJump.anchoredOffset(900, 600), 300);
  });

  test('a fully visible target needs no correction', () {
    expect(
        ReplyJump.needsCorrection(const Rect.fromLTRB(0, 300, 400, 500), view),
        isFalse);
  });

  test('a target that grew past the top or bottom is corrected', () {
    // Vommet issue 1057: a picture loaded after the jump and pushed the
    // message's top out of view ("lands too low").
    expect(
        ReplyJump.needsCorrection(const Rect.fromLTRB(0, 40, 400, 500), view),
        isTrue);
    expect(
        ReplyJump.needsCorrection(const Rect.fromLTRB(0, 300, 400, 760), view),
        isTrue);
  });

  test('a tall target only needs its top shown', () {
    expect(
        ReplyJump.needsCorrection(const Rect.fromLTRB(0, 100, 400, 1000), view),
        isFalse);
    expect(
        ReplyJump.needsCorrection(const Rect.fromLTRB(0, 20, 400, 1000), view),
        isTrue);
  });
}
