import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/space_header.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:flutter/material.dart';

/// Vommet: the space's header above its room list in one scroll view. A
/// banner header shrinks to the compact row as the list scrolls and stays
/// pinned there (Discord's server banner); without a banner the compact row
/// is pinned from the start.
class SpaceSidebarList extends StatefulWidget {
  const SpaceSidebarList(this.space,
      {required this.child,
      this.onHeaderTap,
      this.headerBackground,
      super.key});

  final Space space;
  final Widget child;
  final VoidCallback? onHeaderTap;

  /// Behind the compact row, so rooms don't show through it when scrolled.
  final Color? headerBackground;

  @override
  State<SpaceSidebarList> createState() => _SpaceSidebarListState();
}

class _SpaceSidebarListState extends State<SpaceSidebarList> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.space.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(SpaceSidebarList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space != widget.space) {
      _sub?.cancel();
      _sub = widget.space.onUpdate.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final full = SpaceHeader.hasBanner(widget.space)
        ? SpaceHeader.fullHeight
        : SpaceHeader.compactHeight;
    final background = widget.headerBackground ??
        Theme.of(context).colorScheme.surfaceContainer;

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
            // The collapsing banner is part of the Discord-style layout
            // experiment; without it the header keeps its full height.
            minHeight: (preferences.experimentBannerLayout.value
                    ? SpaceHeader.compactHeight
                    : full) +
                top,
            maxHeight: full + top,
            builder: (context, height) => ColoredBox(
              color: background,
              child: SpaceHeader(
                widget.space,
                key: ValueKey("space-header-${widget.space.localId}"),
                height: height - top,
                onTap: widget.onHeaderTap,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: widget.child),
      ],
    );
  }
}
