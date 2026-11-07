import 'package:flutter/widgets.dart';

/// Vommet issue 1057: geometry and timing for jumping to a message (tapping
/// a reply). The timeline is a reversed list, so in scroll offsets "up" is
/// positive and an alignment of 1.0 puts an item's top at the viewport top.
class ReplyJump {
  /// A nearby (already built) target scrolls there smoothly.
  static const nearDuration = Duration(milliseconds: 450);
  static const nearCurve = Curves.easeOutCubic;

  /// A far target is re-anchored while the list is faded out, then fades in.
  static const fadeOutDuration = Duration(milliseconds: 120);
  static const fadeInDuration = Duration(milliseconds: 220);

  /// Pictures and link previews can still grow after the jump; their height
  /// is watched this long, then the target is put fully in view.
  static const settleWindow = Duration(milliseconds: 1000);
  static const correctionDuration = Duration(milliseconds: 220);
  static const correctionCurve = Curves.easeOut;

  /// Where to reveal an item [itemHeight] tall in a [viewportHeight] view:
  /// centered, or top-aligned when it doesn't fit.
  static double alignmentFor(double itemHeight, double viewportHeight) =>
      itemHeight > viewportHeight ? 1.0 : 0.5;

  /// The scroll offset that shows the anchor item (its bottom on the anchor
  /// line at offset 0) as [alignmentFor] does.
  static double anchoredOffset(double itemHeight, double viewportHeight) {
    if (itemHeight > viewportHeight) return itemHeight - viewportHeight;
    return (itemHeight - viewportHeight) / 2;
  }

  /// The row of a jump target, looked up again after every await: a message
  /// arriving (inserted at 0), redacted or removed meanwhile shifts the rows.
  /// Rows keep their key when their event is replaced, so the key is matched
  /// first, then the event id. -1 when the target is gone.
  static int rowOf(
      List<(GlobalKey, String)> rows, GlobalKey key, String eventId) {
    final index = rows.indexWhere((row) => identical(row.$1, key));
    if (index != -1) return index;
    return rows.indexWhere((row) => row.$2 == eventId);
  }

  /// Whether [item] needs a correction to be fully inside [view]. A target
  /// taller than the view only needs its top edge shown.
  static bool needsCorrection(Rect item, Rect view) {
    const slop = 1.0;
    if (item.height > view.height) {
      return (item.top - view.top).abs() > slop;
    }
    return item.top < view.top - slop || item.bottom > view.bottom + slop;
  }
}

/// The timeline list: hidden on its first frame, and faded out while a far
/// jump re-anchors it (Vommet issue 1057).
class JumpFade extends StatelessWidget {
  const JumpFade(
      {required this.offstage,
      required this.faded,
      required this.child,
      super.key});

  final bool offstage;
  final bool faded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: offstage,
      child: AnimatedOpacity(
        opacity: faded ? 0 : 1,
        duration: faded ? ReplyJump.fadeOutDuration : ReplyJump.fadeInDuration,
        child: child,
      ),
    );
  }
}
