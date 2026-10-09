import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:flutter/material.dart';

/// Vommet: the room header, chat and side panel on desktop.
///
/// Normally the header spans the full width above the chat and the panel.
/// When the room has a banner and the panel shows the member list, the panel
/// runs to the top of the window instead, so the banner sits level with the
/// space banner on the left and the header ends beside it.
class RoomChatLayout extends StatefulWidget {
  const RoomChatLayout({
    required this.room,
    required this.header,
    required this.chat,
    required this.panel,
    super.key,
  });

  final Room room;
  final Widget header;
  final Widget chat;

  /// Builds the side panel, which reports its state through [onStateChanged].
  final Widget Function(ValueChanged<SidePanelState> onStateChanged) panel;

  @override
  State<RoomChatLayout> createState() => _RoomChatLayoutState();
}

class _RoomChatLayoutState extends State<RoomChatLayout> {
  // Keep the timeline and the panel (an open thread, a search) alive when
  // they move between the two layouts.
  final _chatKey = GlobalKey();
  final _panelKey = GlobalKey();

  // Same initial state as RoomSidePanel.
  SidePanelState _panelState = preferences.hideRoomSidePanel.value
      ? SidePanelState.nothing
      : SidePanelState.defaultView;

  StreamSubscription? _bannerSub;

  @override
  void initState() {
    super.initState();
    PaneWidths.right.addListener(_onPaneWidth);
    _bannerSub = widget.room
        .getComponent<RoomBannerComponent>()
        ?.onBannerChanged
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _bannerSub?.cancel();
    PaneWidths.right.removeListener(_onPaneWidth);
    super.dispose();
  }

  void _onPaneWidth() {
    if (mounted) setState(() {});
  }

  void _onPanelState(SidePanelState state) {
    if (state != _panelState && mounted) {
      setState(() => _panelState = state);
    }
  }

  bool get _bannerColumn =>
      _panelState == SidePanelState.defaultView &&
      widget.room.getComponent<RoomBannerComponent>()?.banner != null;

  @override
  Widget build(BuildContext context) {
    final chat = KeyedSubtree(key: _chatKey, child: widget.chat);
    Widget panel =
        KeyedSubtree(key: _panelKey, child: widget.panel(_onPanelState));
    // Only the member list follows the pane width (threads, search etc. size
    // themselves); its grab strip lies over the panel's left edge.
    if (_panelState == SidePanelState.defaultView && PaneWidth.resizable) {
      panel = Stack(
        children: [
          panel,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: PaneResizeHandle(PaneWidths.right, growsRight: false),
          ),
        ],
      );
    }

    if (_bannerColumn) {
      return Row(
        children: [
          Expanded(
            child: Column(
              children: [widget.header, Expanded(child: chat)],
            ),
          ),
          panel,
        ],
      );
    }

    return Column(
      children: [
        widget.header,
        Expanded(
          child: Row(children: [
            Expanded(child: chat),
            panel,
          ]),
        ),
      ],
    );
  }
}
