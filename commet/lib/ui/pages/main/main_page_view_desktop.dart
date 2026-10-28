import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'dart:async';

import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/drag_drop_file_target.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/molecules/space_viewer.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/molecules/compact_room_list.dart';
import 'package:commet/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:commet/ui/organisms/home_screen/home_screen.dart';
import 'package:commet/ui/organisms/home_screen/single_rooms_list.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu_desktop.dart';
import 'package:commet/ui/organisms/friends/friends_home_tile.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/organisms/space_summary/space_summary.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';

class MainPageViewDesktop extends StatelessWidget {
  const MainPageViewDesktop(this.state, {super.key});
  final MainPageState state;

  String get directMessagesListHeaderDesktop => Intl.message(
        "Direct Messages",
        desc: "The header for the direct messages list on desktop",
        name: "directMessagesListHeaderDesktop",
      );

  @override
  Widget build(BuildContext context) {
    // Vommet: the Telegram-style chat list replaces the rail (issue 291).
    if (unifiedChatListEnabled) return UnifiedMainPageDesktop(state);
    return tiamat.Foundation(
      // Vommet issue 456: the side column gives the chat room as the window
      // narrows: full, then room pictures only, then hidden behind the room
      // header's menu button. Ctrl+Shift+B collapses the list by hand.
      child: RoomListCollapseShortcut(
          child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: Listenable.merge([
            PaneWidths.left,
            ResponsiveDesktop.collapsed,
            ResponsiveDesktop.drawerOpen,
          ]),
          builder: (context, _) => buildLayout(context, constraints.maxWidth),
        ),
      )),
    );
  }

  Widget buildLayout(BuildContext context, double width) {
    // Vommet: on a half-open foldable held like a book, the column ends at
    // the fold, so the chat starts on the other half instead of running
    // across it.
    final foldX = MediaQuery.of(context).halfOpenVerticalFoldX;
    final column = foldX != null
        ? DesktopSideColumn.full
        : ResponsiveDesktop.sideColumnFor(width, PaneWidths.left.effective,
            collapsedByHand: ResponsiveDesktop.collapsed.value);
    final hidden = column == DesktopSideColumn.hidden;
    if (!hidden && ResponsiveDesktop.drawerOpen.value) {
      // Widened again: the column is back in place, so close the drawer.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ResponsiveDesktop.drawerOpen.value = false);
    }

    return Stack(
      children: [
        Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hidden)
              sideColumn(context,
                  compact: column == DesktopSideColumn.compact,
                  width: foldX,
                  // Collapsed by hand with room for names: its edge drags
                  // back out.
                  expandable: column == DesktopSideColumn.compact &&
                      ResponsiveDesktop.collapsed.value &&
                      ResponsiveDesktop.sideColumnFor(
                              width, PaneWidths.left.effective) ==
                          DesktopSideColumn.full),
            // Vommet: mainView already returns a Flexible/Expanded; wrapping
            // it again nested two ParentDataWidgets (debug assertion).
            mainView(context, sideHidden: hidden),
          ],
        ),
        if (state.currentRoom != null)
          DragDropFileTarget(
            onDropComplete: (details) {
              EventBus.onFileDropped.add(details);
            },
          ),
        if (hidden && ResponsiveDesktop.drawerOpen.value) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => ResponsiveDesktop.drawerOpen.value = false,
              child: const ColoredBox(color: Colors.black54),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SideColumnDrawer(
              child: Material(
                elevation: 8,
                child: sideColumn(context, compact: false, collapsible: false),
              ),
            ),
          ),
        ],
        const BackgroundTaskViewContainer(),
        const OverlayWindowsSurface(),
      ],
    );
  }

  /// The space bar, the room list and the session panel. [width] overrides
  /// the column's width (a half-open fold); [collapsible] offers collapsing
  /// the list to room pictures, also by dragging its edge past the narrowest
  /// width; [expandable] lets a collapsed list's edge drag back out.
  Widget sideColumn(BuildContext context,
      {required bool compact,
      double? width,
      bool collapsible = true,
      bool expandable = false}) {
    final listWidth = compact
        ? ResponsiveDesktop.compactListWidth
        : PaneWidths.left.effective;
    return SizedBox(
      // Vommet: the list pane is resizable (PaneWidths.left); 320 was
      // upstream's fixed 70 px space bar + 250 px list.
      width: width ?? ResponsiveDesktop.spaceBarWidth + listWidth,
      child: Stack(
        children: [
          Positioned.fill(
              child: sideColumnContent(context, compact, collapsible)),
          if (PaneWidths.left.resizable && !compact && collapsible)
            Positioned.fill(
              left: ResponsiveDesktop.spaceBarWidth,
              child: ValueListenableBuilder(
                valueListenable: PaneWidths.left.pulledPastMin,
                builder: (context, pulled, _) => pulled
                    ? const RoomListCollapseHint()
                    : const SizedBox.shrink(),
              ),
            ),
          if (PaneWidths.left.resizable && !compact)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: PaneResizeHandle(PaneWidths.left,
                  onCollapse: collapsible && width == null
                      ? () => ResponsiveDesktop.setCollapsed(true)
                      : null),
            ),
          if (PaneWidths.left.resizable && expandable)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: CollapsedPaneHandle(
                  onExpand: () => ResponsiveDesktop.setCollapsed(false)),
            ),
        ],
      ),
    );
  }

  Widget sideColumnContent(
      BuildContext context, bool compact, bool collapsible) {
    // Vommet: this column sits at the left edge, so the right
    // inset (e.g. the status bar along the side of an unfolded
    // iPhone Duo) is not its business; without this the space
    // bar, room list and session panel each kept 84 pt clear in
    // the middle of the window.
    return MediaQuery.removePadding(
      context: context,
      removeRight: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tile(
                  caulkPadTop: true,
                  caulkPadRight: true,
                  caulkClipTopRight: true,
                  caulkClipBottomRight: true,
                  caulkBorderRight: true,
                  mode: TileType.surfaceDim,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                    child: ScaledSafeArea(
                      top: false,
                      bottom: false,
                      child: SideNavigationBar(
                        currentUser: state.currentUser,
                        onSpaceSelected: (space) {
                          state.openSpaceHome(space, restoreLastRoom: true);
                        },
                        onHomeSelected: () {
                          state.selectHome();
                        },
                        clearSpaceSelection: () {
                          state.clearSpaceSelection();
                        },
                        onRoomsViewSelected: () {
                          state.selectRoomsView();
                        },
                        onDirectMessageSelected: (room) {
                          state.selectHome();
                          state.selectRoom(room);
                        },
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: tiamat.Tile.surfaceContainer(
                      caulkClipBottomLeft: true,
                      caulkClipTopRight: true,
                      caulkPadTop: true,
                      caulkClipBottomRight: true,
                      caulkClipTopLeft: true,
                      child: compact
                          ? CompactRoomList(state)
                          : roomListWithCollapse(context, collapsible)),
                ),
              ],
            ),
          ),
          tiamat.Tile.low(
            caulkPadTop: true,
            caulkClipTopRight: true,
            caulkBorderTop: true,
            caulkPadRight: MediaQuery.of(context).mobile,
            child: ScaledSafeArea(
              top: false,
              child: CurrentSessionPanel(
                currentUser: state.currentUser,
                compact: compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get openSideColumnTooltip => Intl.message("Spaces and rooms",
      name: "openSideColumnTooltip",
      desc: "Tooltip on the menu button that opens the hidden space bar and "
          "room list over the chat in a narrow window");

  /// The room list, its header rows offering the button that collapses it
  /// to room pictures.
  Widget roomListWithCollapse(BuildContext context, bool collapsible) {
    if (!collapsible) return buildRoomPicker(context);
    return RoomListHeaderAction(child: buildRoomPicker(context));
  }

  /// Opens the hidden side column over the chat.
  void openSideColumn() => ResponsiveDesktop.drawerOpen.value = true;

  Widget maybeGutter(bool sideHidden, Widget child) =>
      sideHidden ? withMenuGutter(child) : child;

  /// While the side column is hidden, a view without a room header keeps a
  /// strip on its left for the menu button.
  Widget withMenuGutter(Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
          child: tiamat.Tooltip(
            text: openSideColumnTooltip,
            child: tiamat.IconButton(
              icon: Icons.menu,
              size: 20,
              onPressed: openSideColumn,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  SizedBox spaceRoomSelector(BuildContext context) {
    return SizedBox(
      // Vommet: fills the resizable pane (was 250).
      width: double.infinity,
      // Vommet: header and room list scroll together; the header collapses.
      child: SpaceSidebarList(
        state.currentSpace!,
        key: ValueKey("space-sidebar-${state.currentSpace!.localId}"),
        onHeaderTap: state.clearRoomSelection,
        child: SpaceViewer(
          state.currentSpace!,
          key: ValueKey(
            "space-view-key-${state.currentSpace!.localId}",
          ),
          onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
            state.selectRoom(room,
                bypassSpecialRoomType: bypassSpecialRoomType);
          },
        ),
      ),
    );
  }

  Widget homeView({bool sideHidden = false}) {
    return Row(
      children: [
        if (state.currentRoom == null)
          Expanded(
            child: FriendsHomeTile(
              caulkPadLeft: true,
              caulkClipTopLeft: true,
              caulkClipBottomLeft: true,
              caulkPadTop: true,
              caulkPadBottom: true,
              child: ScaledSafeArea(
                child: maybeGutter(
                  sideHidden,
                  HomeScreen(
                    clientManager: state.clientManager,
                    filterClient: state.filterClient,
                  ),
                ),
              ),
            ),
          ),
        if (state.currentRoom != null) roomChatView(sideHidden: sideHidden),
      ],
    );
  }

  Widget roomChatView({bool sideHidden = false}) {
    return Expanded(
      key: ValueKey("room-chat-view-${state.currentRoom!.localId}"),
      // Vommet: RoomChatLayout moves the panel up beside the header when the
      // room has a banner; the pieces below are upstream's.
      child: RoomChatLayout(
        room: state.currentRoom!,
        header: Tile.low(
          caulkPadBottom: true,
          caulkPadLeft: true,
          caulkClipBottomLeft: true,
          caulkBorderLeft: true,
          caulkBorderBottom: true,
          child: ScaledSafeArea(
            top: true,
            bottom: false,
            child: SizedBox(
              height: 50,
              child: RoomHeader(
                state.currentRoom!,
                onTap: roomInfoPageEnabled ||
                        state.currentRoom?.permissions.canEditAnything == true
                    ? () => state.navigateRoomSettings()
                    : null,
                menu: RoomQuickAccessMenuViewDesktop(room: state.currentRoom!),
                showBurger: sideHidden,
                onBurgerMenuTap: sideHidden ? openSideColumn : null,
              ),
            ),
          ),
        ),
        chat: Tile(
          caulkPadLeft: true,
          caulkClipTopLeft: true,
          caulkClipTopRight: true,
          caulkBorderRight: true,
          caulkPadBottom: true,
          caulkClipBottomLeft: true,
          caulkClipBottomRight: true,
          caulkBorderLeft: true,
          child: RoomPrimaryView(state.currentRoom!,
              bypassSpecialRoomTypes: state.showAsTextRoom),
        ),
        panel: (onStateChanged) => RoomSidePanel(
          key: ValueKey(
            "room-sidepanel-key-${state.currentRoom!.localId}",
          ),
          state: state,
          onStateChanged: onStateChanged,
          // Vommet: RoomChatLayout makes a thread or the calendar flexible;
          // a Flexible in here would move with the panel's GlobalKey.
          builder: (state, child) => Tile.surfaceContainer(
            caulkPadLeft: true,
            caulkPadBottom: true,
            caulkClipBottomLeft: true,
            caulkClipTopLeft: true,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget buildRoomPicker(BuildContext context) {
    if (state.currentView == MainPageSubView.rooms) {
      return SingleRoomsList(
        state: state,
        onSelectRoom: (room) {
          state.selectRoom(room);
        },
      );
    }

    if (state.currentSpace == null) {
      return ScaledSafeArea(
        top: true,
        bottom: false,
        child: SizedBox(
          height: double.infinity,
          child: HomeColumn(
              state: state,
              directMessagesListHeaderDesktop: directMessagesListHeaderDesktop),
        ),
      );
    } else {
      return spaceRoomSelector(context);
    }
  }

  Widget mainView(BuildContext context, {bool sideHidden = false}) {
    if (state.currentView == MainPageSubView.home ||
        state.currentView == MainPageSubView.rooms)
      // Vommet: was Flexible inside the caller's Expanded; release builds
      // applied the outer Expanded, so keep that behaviour.
      return Expanded(child: homeView(sideHidden: sideHidden));
    if (state.currentRoom != null && state.currentView != MainPageSubView.home)
      return roomChatView(sideHidden: sideHidden);
    if (state.currentSpace != null && state.currentRoom == null)
      return Expanded(
        child: Tile(
          caulkPadTop: true,
          caulkPadBottom: true,
          caulkPadLeft: true,
          caulkClipTopLeft: true,
          caulkBorderLeft: true,
          caulkClipBottomLeft: true,
          child: maybeGutter(
            sideHidden,
            ListView(
              padding: EdgeInsets.zero,
              children: [
                SpaceSummary(
                  key: ValueKey(
                    "space-summary-key-${state.currentSpace!.localId}",
                  ),
                  space: state.currentSpace!,
                  onRoomTap: (room) => state.selectRoom(room),
                  onSpaceTap: (space) => state.selectSpace(space),
                  onLeaveRoom: state.clearRoomSelection,
                ),
              ],
            ),
          ),
        ),
      );

    return Expanded(child: Placeholder());
  }
}

/// Vommet: the hidden side column opened over the chat (Vommet issue 456);
/// picking a room closes it.
class SideColumnDrawer extends StatefulWidget {
  const SideColumnDrawer({required this.child, super.key});

  final Widget child;

  @override
  State<SideColumnDrawer> createState() => _SideColumnDrawerState();
}

class _SideColumnDrawerState extends State<SideColumnDrawer> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = EventBus.onSelectedRoomChanged.stream.listen((room) {
      if (room != null) ResponsiveDesktop.drawerOpen.value = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
