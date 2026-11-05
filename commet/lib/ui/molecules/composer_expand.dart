import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Vommet composer round 6 (phones): once a draft reaches this many lines
/// on screen, ⤢ in the box's top-right corner makes the same box fill the
/// room between the header and the keyboard (like Telegram).
const int composerExpandMinLines = 3;

/// The composer's flex while expanded, against the timeline's 1: the box
/// takes all but a fraction of a pixel.
const int composerExpandFlex = 1 << 20;

/// Lines of a laid-out text field: its height over one line's.
int composerLineCount(double height, double lineHeight) =>
    lineHeight <= 0 ? 1 : (height / lineHeight).round();

/// The chat's timeline slot: the timeline gives its height to the
/// expanded composer without being laid out again at another size, so its
/// scroll position stays where it was.
Widget composerTimelineSlot(
        {required bool composerExpanded, required Widget child}) =>
    Flexible(
      fit: composerExpanded ? FlexFit.loose : FlexFit.tight,
      child: KeepLayoutWhileHidden(hidden: composerExpanded, child: child),
    );

/// The chat's composer slot: its own height, or all of it while expanded.
Widget composerSlot({required bool expanded, required Widget child}) =>
    Flexible(
      flex: expanded ? composerExpandFlex : 0,
      fit: FlexFit.tight,
      child: child,
    );

/// While [hidden], takes no room, paints nothing and takes no taps, but
/// keeps [child] laid out at its last shown size (so a list keeps its
/// scroll offset and nothing inside is rebuilt).
class KeepLayoutWhileHidden extends SingleChildRenderObjectWidget {
  const KeepLayoutWhileHidden(
      {required this.hidden, required super.child, super.key});

  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeepLayoutWhileHidden(hidden);

  @override
  void updateRenderObject(
      BuildContext context, _RenderKeepLayoutWhileHidden renderObject) {
    renderObject.hidden = hidden;
  }
}

class _RenderKeepLayoutWhileHidden extends RenderProxyBox {
  _RenderKeepLayoutWhileHidden(this._hidden);

  bool _hidden;
  double? _shownHeight;

  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  Size _hiddenSize(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, 0));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _hidden ? _hiddenSize(constraints) : super.computeDryLayout(constraints);

  @override
  void performLayout() {
    final child = this.child;
    if (!_hidden) {
      if (child == null) {
        size = constraints.smallest;
        return;
      }
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
      _shownHeight = size.height;
      return;
    }
    child?.layout(
        BoxConstraints.tightFor(
            width: constraints.maxWidth, height: _shownHeight ?? 0),
        parentUsesSize: false);
    size = _hiddenSize(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_hidden && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_hidden) super.visitChildrenForSemantics(visitor);
  }
}

/// ⤢ / ⤡ in the box's top-right corner.
class ComposerExpandButton extends StatelessWidget {
  const ComposerExpandButton(
      {required this.expanded, required this.onTap, super.key});

  final bool expanded;
  final void Function() onTap;

  static const String labelExpand = "Expand message box";
  static const String labelCollapse = "Shrink message box";

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: expanded ? labelCollapse : labelExpand,
      child: InkResponse(
        key: ValueKey(expanded ? "composer-collapse" : "composer-expand"),
        radius: 16,
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(expanded ? Icons.close_fullscreen : Icons.open_in_full,
              size: 16, color: color.withAlpha(170)),
        ),
      ),
    );
  }
}
