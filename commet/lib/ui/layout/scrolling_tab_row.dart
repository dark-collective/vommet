import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Vommet: a row of tabs that scrolls sideways when it doesn't fit, as
/// Discord's and browsers' tab rows do: a small arrow at each clipped edge
/// slides the row over, a mouse wheel scrolls it, and touch drags it.
class ScrollingTabRow extends StatefulWidget {
  const ScrollingTabRow(
      {required this.children, required this.background, super.key});

  final List<Widget> children;

  /// The strip's colour, which the edge arrows fade into.
  final Color background;

  @override
  State<ScrollingTabRow> createState() => _ScrollingTabRowState();
}

class _ScrollingTabRowState extends State<ScrollingTabRow> {
  final controller = ScrollController();
  bool canLeft = false;
  bool canRight = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !controller.hasClients) return;
    final p = controller.position;
    final left = p.pixels > 1;
    final right = p.pixels < p.maxScrollExtent - 1;
    if (left != canLeft || right != canRight) {
      setState(() {
        canLeft = left;
        canRight = right;
      });
    }
  }

  void _slide(int direction) {
    final p = controller.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.7)
        .clamp(0.0, p.maxScrollExtent);
    controller.animateTo(target,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !controller.hasClients) return;
    final p = controller.position;
    if (p.maxScrollExtent <= 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final delta = (event as PointerScrollEvent).scrollDelta;
      final by = delta.dy != 0 ? delta.dy : delta.dx;
      controller.jumpTo((p.pixels + by).clamp(0.0, p.maxScrollExtent));
    });
  }

  Widget _arrow(int direction) {
    final left = direction < 0;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerRight : Alignment.centerLeft,
            end: left ? Alignment.centerLeft : Alignment.centerRight,
            colors: [widget.background.withValues(alpha: 0), widget.background],
            stops: const [0, 0.45],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: left ? 0 : 14, right: left ? 14 : 0),
          child: Center(
            child: IconButton(
              key: ValueKey("scrolling-tab-row-${left ? "left" : "right"}"),
              tooltip: left ? "Earlier tabs" : "More tabs",
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
              onPressed: () => _slide(direction),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.background,
      child: NotificationListener<ScrollMetricsNotification>(
        // The row's width changes with the panel's.
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _update());
          return false;
        },
        child: Stack(
          children: [
            Listener(
              onPointerSignal: _onWheel,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: widget.children),
              ),
            ),
            if (canLeft) _arrow(-1),
            if (canRight) _arrow(1),
          ],
        ),
      ),
    );
  }
}
