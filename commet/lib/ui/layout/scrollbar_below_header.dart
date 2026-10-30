import 'package:commet/ui/layout/reflow_scroll_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Vommet: a vertical scroll view whose scrollbar starts under a header
/// pinned inside it (the side panel's tab strip), so the scrollbar never
/// covers the header (the tab strip's "more tabs" arrow sat under it).
///
/// The header can move: a banner above it collapses as the list scrolls,
/// so the scrollbar's top follows the header's bottom edge.
class ScrollbarBelowHeader extends StatefulWidget {
  const ScrollbarBelowHeader(
      {required this.headerKey, required this.builder, super.key});

  /// The header's key; without a mounted header the scrollbar runs the
  /// full height.
  final GlobalKey headerKey;

  /// Builds the scroll view. It must use [controller] and [behavior] (which
  /// turns off the scroll view's own scrollbar; nested scroll views keep
  /// theirs).
  final Widget Function(BuildContext context, ScrollController controller,
      ScrollBehavior behavior) builder;

  @override
  State<ScrollbarBelowHeader> createState() => _ScrollbarBelowHeaderState();
}

class _ScrollbarBelowHeaderState extends State<ScrollbarBelowHeader> {
  // Vommet issue 897: lets the Media tab's zoom keep its place in the
  // same frame as the grid reflows.
  final controller = ReflowScrollController();
  final top = ValueNotifier<double>(0);
  bool _measureQueued = false;

  @override
  void dispose() {
    controller.dispose();
    top.dispose();
    super.dispose();
  }

  // Measured after layout: during a scroll notification the header hasn't
  // moved yet.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final self = context.findRenderObject();
      final header = widget.headerKey.currentContext?.findRenderObject();
      if (self is! RenderBox || !self.attached) return;
      if (header is! RenderBox || !header.attached) {
        top.value = 0;
        return;
      }
      final bottom = header
          .localToGlobal(Offset(0, header.size.height), ancestor: self)
          .dy;
      top.value = bottom.clamp(0.0, self.size.height);
    });
  }

  // As Material's own scroll behaviour: scrollbars on desktop only.
  static bool get _desktop => switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final behavior =
        ScrollConfiguration.of(context).copyWith(scrollbars: false);
    final view = widget.builder(context, controller, behavior);
    if (!_desktop) return view;

    _queueMeasure();
    final query = MediaQuery.of(context);
    return NotificationListener<Notification>(
      onNotification: (n) {
        if ((n is ScrollUpdateNotification && n.depth == 0) ||
            (n is ScrollMetricsNotification && n.depth == 0)) {
          _queueMeasure();
        }
        return false;
      },
      child: ValueListenableBuilder<double>(
        valueListenable: top,
        // The scrollbar takes its insets from MediaQuery's padding; the
        // scroll view keeps the real one.
        builder: (context, top, child) => MediaQuery(
          data: query.copyWith(padding: query.padding.copyWith(top: top)),
          child: Scrollbar(controller: controller, child: child!),
        ),
        child: MediaQuery(data: query, child: view),
      ),
    );
  }
}
