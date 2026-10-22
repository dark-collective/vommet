import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@UseCase(name: "Tooltip", type: Tooltip)
Widget wbTooltip(BuildContext context) {
  return Tile.low1(
    child: const Center(
        child: Padding(
            padding: EdgeInsets.all(8.0),
            child: Tooltip(
              text: "This is a tooltip!",
              child: tiamat.Text.body("Hover me!"),
            ))),
  );
}

class Tooltip extends StatefulWidget {
  const Tooltip(
      {required this.child,
      required this.text,
      this.preferredDirection = AxisDirection.up,
      this.shouldShow,
      super.key});
  final Widget child;
  final String text;
  final AxisDirection preferredDirection;

  /// Asked when the pointer comes over [child]; no tooltip when it says no.
  final bool Function(PointerEnterEvent event)? shouldShow;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  final controller = JustTheController();

  @override
  Widget build(BuildContext context) {
    return JustTheTooltip(
        content: Theme(
          data: Theme.of(context),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: tiamat.Text(
              widget.text,
              type: tiamat.TextType.body,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        triggerMode: TooltipTriggerMode.manual,
        preferredDirection: widget.preferredDirection,
        offset: 5,
        tailLength: 5,
        tailBaseWidth: 5,
        controller: controller,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: MouseRegion(
          onEnter: (event) {
            if (widget.shouldShow?.call(event) ?? true)
              controller.showTooltip();
          },
          onExit: (event) => controller.hideTooltip(),
          child: widget.child,
        ));
  }
}

/// Vommet: shows [text] in a tooltip while the pointer is over [child], but
/// only when a text in [child] is cut off (ellipsised or past its maxLines).
/// It checks the laid-out text on hover, so it needs no style to measure
/// with. Pointer hover only: touch gets nothing (Vommet issue 546).
class TooltipWhenCutOff extends StatefulWidget {
  const TooltipWhenCutOff({required this.text, required this.child, super.key});
  final String text;
  final Widget child;

  /// Whether any text laid out under [object] is cut off.
  static bool isCutOff(RenderObject object) {
    if (object is RenderParagraph && object.didExceedMaxLines) return true;
    var found = false;
    object.visitChildren((child) {
      if (!found && isCutOff(child)) found = true;
    });
    return found;
  }

  @override
  State<TooltipWhenCutOff> createState() => _TooltipWhenCutOffState();
}

class _TooltipWhenCutOffState extends State<TooltipWhenCutOff> {
  bool _shouldShow(PointerEnterEvent event) {
    if (event.kind == PointerDeviceKind.touch) return false;
    // The tooltip itself is drawn in the overlay, so this is [child]'s text.
    final object = context.findRenderObject();
    return object != null && TooltipWhenCutOff.isCutOff(object);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        text: widget.text, shouldShow: _shouldShow, child: widget.child);
  }
}
