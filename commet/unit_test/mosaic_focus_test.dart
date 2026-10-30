// Vommet issue 741: which picture of a mosaic a reaction goes on is marked
// before it's picked.

import 'package:commet/ui/molecules/timeline_events/media_mosaic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("nothing is marked until the message is hovered or a menu opens", () {
    final focus = MosaicFocus();
    expect(focus.rings("a", isFirst: true), isFalse);
    expect(focus.dims("b"), isFalse);
  });

  test("the oldest picture is the target until another one is pointed at", () {
    final focus = MosaicFocus()..marked = true;
    expect(focus.rings("a", isFirst: true), isTrue);
    expect(focus.rings("b"), isFalse);

    focus.target = "b";
    expect(focus.rings("a", isFirst: true), isFalse);
    expect(focus.rings("b"), isTrue);
  });

  test("while picking, the target is ringed and the others dimmed", () {
    final focus = MosaicFocus()
      ..target = "b"
      ..picking = true;
    expect(focus.rings("b"), isTrue);
    expect(focus.dims("b"), isFalse);
    expect(focus.dims("a", isFirst: true), isTrue);
    expect(focus.dims("c"), isTrue);
  });

  test("the target can't change under an open picker", () {
    final focus = MosaicFocus()
      ..target = "b"
      ..picking = true;
    focus.target = "c";
    expect(focus.target, "b");

    focus.picking = false;
    focus.target = "c";
    expect(focus.target, "c");
  });

  test("a closed picker after the message left the screen is ignored", () {
    final focus = MosaicFocus()..picking = true;
    var notified = 0;
    focus.addListener(() => notified++);
    focus.dispose();
    focus.picking = false;
    expect(notified, 0);
  });

  // Vommet issue 894: a jump to one picture (a reply to it) rings just it.
  test("a jump to one picture rings it and dims the others", () {
    final focus = MosaicFocus()
      ..target = "c"
      ..marked = true;
    expect(focus.rings("b", jumped: "b"), isTrue);
    expect(focus.dims("b", jumped: "b"), isFalse);
    expect(focus.rings("c", jumped: "b"), isFalse);
    expect(focus.dims("c", jumped: "b"), isTrue);
    expect(focus.dims("a", isFirst: true, jumped: "b"), isTrue);
  });
}
