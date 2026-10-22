import 'dart:async';

import 'package:commet/client/space.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rail_metrics.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

/// Vommet: a sidebar rail entry with Discord's pill on the rail's left edge:
/// 8 px tall while the entry has unread messages, 20 px on hover and 40 px
/// for the selected space. The unread pill can be turned off in Appearance
/// settings ([VommetPreferences.railUnreadMarks]); hover and selected stay.
///
/// [child] must span its slot's full width; [inset] is how far the child's
/// left edge sits from the slot's edge ([RailMetrics.margin] more to the
/// rail's).
class RailSlot extends StatefulWidget {
  const RailSlot(
      {required this.child,
      this.unread = false,
      this.space,
      this.inset = 0,
      super.key});

  final Widget child;
  final bool unread;

  /// The space this entry opens; the pill grows while it is selected.
  final Space? space;
  final double inset;

  static const double width = 4;

  @override
  State<RailSlot> createState() => _RailSlotState();
}

class _RailSlotState extends State<RailSlot> {
  final List<StreamSubscription> subs = [];
  bool hovered = false;
  bool selected = false;

  @override
  void initState() {
    super.initState();
    subs.add(
        preferences.railUnreadMarks.onChanged.listen((_) => setState(() {})));
    if (widget.space != null) {
      subs.add(EventBus.onSelectedSpaceChanged.stream.listen((space) {
        final now = space?.identifier == widget.space!.identifier &&
            space?.client.identifier == widget.space!.client.identifier;
        if (now != selected) setState(() => selected = now);
      }));
    }
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  double get pillHeight {
    // Vommet: scaled with "Sidebar icon size" (Vommet issue 506).
    final rail = RailMetrics.current;
    if (selected) return rail.pill(40);
    if (hovered) return rail.pill(20);
    if (widget.unread && preferences.railUnreadMarks.value) return 8;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          widget.child,
          Positioned(
            left: -widget.inset - RailMetrics.current.margin,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: RailSlot.width,
                  height: pillHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(RailSlot.width)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
