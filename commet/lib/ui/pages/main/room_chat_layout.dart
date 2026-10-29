import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Vommet: the panel toggle in a window too narrow for the member list
  /// beside the chat. The list then floats over the chat (or closes again)
  /// instead of the toggle doing nothing visible. Returns true when the
  /// press is handled here and the panel's own toggle must not run.
  static bool toggleFloatingMembers(BuildContext context) =>
      context
          .findAncestorStateOfType<_RoomChatLayoutState>()
          ?._toggleFloating() ??
      false;

  /// Vommet: whether the side panel is on screen, for the header's toggle
  /// arrow (the saved "hide panel" setting alone says nothing about a list
  /// the window is too narrow for). Null outside a RoomChatLayout.
  static bool? panelShownOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelShown>()?.shown;

  /// Vommet issue 622: whether the member panel fills the room's area (its
  /// Media, Files or Links tab expanded over the timeline). Null outside a
  /// RoomChatLayout, where the panel can't expand.
  static bool? panelExpandedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelShown>()?.expanded;

  /// Vommet issue 747: the member panel reports whether its Media tab is
  /// open, which keeps its own width (a share of the room's area).
  static void setMediaTab(BuildContext context, bool media) => context
      .findAncestorStateOfType<_RoomChatLayoutState>()
      ?._setMediaTab(media);

  /// Expands the member panel over the timeline, or back to its side.
  static void setPanelExpanded(BuildContext context, bool expanded) => context
      .findAncestorStateOfType<_RoomChatLayoutState>()
      ?._setExpanded(expanded);
}

class _PanelShown extends InheritedWidget {
  const _PanelShown(
      {required this.shown, required this.expanded, required super.child});
  final bool shown;
  final bool expanded;

  @override
  bool updateShouldNotify(_PanelShown oldWidget) =>
      shown != oldWidget.shown || expanded != oldWidget.expanded;
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

  // Vommet: the member list floats over the chat because the user opened it
  // in a window too narrow to show it beside the chat.
  bool _floating = false;
  bool _tooNarrow = false;

  // Vommet issue 622: the panel fills the room's area, over the timeline.
  bool _expanded = false;

  // Vommet issue 747: the member panel shows its Media tab.
  bool _mediaTab = false;

  void _setMediaTab(bool media) {
    if (media != _mediaTab && mounted) setState(() => _mediaTab = media);
  }

  /// The resizable pane the member panel is sized by now.
  PaneWidth get _pane => _panelState == SidePanelState.defaultView && _mediaTab
      ? PaneWidths.media
      : PaneWidths.right;

  void _setExpanded(bool expanded) {
    if (expanded != _expanded && mounted) {
      setState(() => _expanded = expanded);
    }
  }

  @override
  void initState() {
    super.initState();
    PaneWidths.right.addListener(_onPaneWidth);
    PaneWidths.media.addListener(_onPaneWidth);
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
    PaneWidths.media.removeListener(_onPaneWidth);
    super.dispose();
  }

  void _onPaneWidth() {
    if (mounted) setState(() {});
  }

  void _onPanelState(SidePanelState state) {
    if (state != _panelState && mounted) {
      setState(() {
        _panelState = state;
        if (state != SidePanelState.defaultView) {
          _floating = false;
          _expanded = false;
        }
      });
    }
  }

  bool _toggleFloating() {
    if (!_tooNarrow) return false;
    if (_floating) {
      setState(() => _floating = false);
      return true;
    }
    if (_panelState == SidePanelState.defaultView) {
      setState(() => _floating = true);
      return true;
    }
    if (_panelState == SidePanelState.nothing) {
      // The panel was closed: its own toggle opens the member list, which
      // then floats.
      setState(() => _floating = true);
    }
    return false;
  }

  void _closeFloating() => setState(() => _floating = false);

  // Vommet: on iOS and foldables, the member list stays out while the chat
  // beside it would be too narrow (an unfolded iPhone Duo held upright), and
  // on a half-open foldable held like a book, where the chat only has the half
  // right of the fold. A thread or a search the user opened still shows, and
  // the member list comes back once there is room. Other desktops use the
  // same rule with a wider minimum (ResponsiveDesktop.minChatWidth).
  static const _minChatWidthBesideMembers = 300.0;

  bool _membersHidden(double width) =>
      _panelState == SidePanelState.defaultView && _membersTooNarrow(width);

  bool _membersTooNarrow(double width) {
    final query = MediaQuery.of(context);
    if (!query.foldLayoutRules) {
      // Vommet issue 456: on other desktops too the member list goes first
      // when the window narrows, before the room list shrinks.
      return width - _pane.effective < ResponsiveDesktop.minChatWidth;
    }
    return query.halfOpenVerticalFoldX != null ||
        width - _pane.effective < _minChatWidthBesideMembers;
  }

  bool _bannerColumn(bool membersHidden) =>
      !membersHidden &&
      _panelState == SidePanelState.defaultView &&
      widget.room.getComponent<RoomBannerComponent>()?.banner != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Vommet issue 747: the Media tab's width is a share of this area.
      PaneWidths.media.area = constraints.maxWidth;
      _tooNarrow = _membersTooNarrow(constraints.maxWidth);
      // Widened again: the list is back beside the chat.
      if (!_tooNarrow) _floating = false;
      final membersHidden = _membersHidden(constraints.maxWidth);
      final floating = _floating && membersHidden;
      final expanded = _expanded && _panelState == SidePanelState.defaultView;
      return _PanelShown(
        shown: _panelState != SidePanelState.nothing &&
            (expanded || !membersHidden || floating),
        expanded: expanded,
        child: expanded
            ? _expandedLayout()
            : floating
                ? _floatingLayout()
                : _layout(membersHidden),
      );
    });
  }

  /// The member list over the right of the chat, below the header (whose
  /// toggle closes it again), with the chat dimmed behind it.
  Widget _floatingLayout() {
    return Column(
      children: [
        widget.header,
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                  child: KeyedSubtree(key: _chatKey, child: widget.chat)),
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeFloating,
                  child: const ColoredBox(color: Colors.black54),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: ClipRect(
                  child: Material(
                    elevation: 8,
                    child: KeyedSubtree(
                        key: _panelKey, child: widget.panel(_onPanelState)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Vommet issue 622: the panel over the whole area below the header. The
  /// chat stays alive offstage (its scroll position, a draft), and Escape
  /// or the panel's collapse button bring it back.
  Widget _expandedLayout() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _setExpanded(false),
      },
      child: Column(
        children: [
          widget.header,
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Offstage(
                      child: KeyedSubtree(key: _chatKey, child: widget.chat)),
                ),
                Positioned.fill(
                  child: KeyedSubtree(
                      key: _panelKey, child: widget.panel(_onPanelState)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _layout(bool membersHidden) {
    final chat = KeyedSubtree(key: _chatKey, child: widget.chat);
    Widget panel =
        KeyedSubtree(key: _panelKey, child: widget.panel(_onPanelState));
    // Only the member list follows the pane width (threads, search etc. size
    // themselves); its grab strip lies over the panel's left edge.
    // A thread or the calendar takes the space the chat leaves. The Flexible
    // stays out here, outside the panel's GlobalKey: closing a thread moves the
    // panel into the Stack below before it rebuilds, and a Flexible inside it
    // then lands in the Stack (a TypeError in release builds: grey screen).
    if (_panelState == SidePanelState.thread ||
        _panelState == SidePanelState.calendar) {
      panel = Flexible(child: panel);
    } else if (_panelState == SidePanelState.defaultView && _pane.resizable) {
      panel = Stack(
        children: [
          panel,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: PaneResizeHandle(_pane, growsRight: false),
          ),
        ],
      );
    }

    if (membersHidden) {
      // Offstage keeps the panel (and its state) alive at zero width.
      panel = Offstage(child: panel);
    }

    if (_bannerColumn(membersHidden)) {
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
