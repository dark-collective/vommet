import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/drag_drop_file_target.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/molecules/space_viewer.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:commet/ui/organisms/home_screen/home_screen.dart';
import 'package:commet/ui/organisms/home_screen/single_rooms_list.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/home_screen/important_rooms_list.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu_desktop.dart';
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
    return tiamat.Foundation(
      child: Stack(
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vommet: the list pane is resizable (PaneWidths.left); 320 was
              // upstream's fixed 70 px space bar + 250 px list.
              ValueListenableBuilder(
                valueListenable: PaneWidths.left,
                builder: (context, width, child) => SizedBox(
                  width: 70 + PaneWidths.left.effective,
                  child: Stack(
                    children: [
                      Positioned.fill(child: child!),
                      if (PaneWidth.resizable)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: PaneResizeHandle(PaneWidths.left),
                        ),
                    ],
                  ),
                ),
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
                                    state.selectSpace(space);
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
                                child: buildRoomPicker(context)),
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Vommet: mainView already returns a Flexible/Expanded; wrapping
              // it again nested two ParentDataWidgets (debug assertion).
              mainView(context),
            ],
          ),
          if (state.currentRoom != null)
            DragDropFileTarget(
              onDropComplete: (details) {
                EventBus.onFileDropped.add(details);
              },
            ),
          const BackgroundTaskViewContainer(),
          const OverlayWindowsSurface(),
        ],
      ),
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

  Widget homeView() {
    return Row(
      children: [
        if (state.currentRoom == null)
          Expanded(
            child: Tile(
              caulkPadLeft: true,
              caulkClipTopLeft: true,
              caulkClipBottomLeft: true,
              caulkPadTop: true,
              caulkPadBottom: true,
              child: ScaledSafeArea(
                child: HomeScreen(
                  clientManager: state.clientManager,
                  filterClient: state.filterClient,
                ),
              ),
            ),
          ),
        if (state.currentRoom != null) roomChatView(),
      ],
    );
  }

  Widget roomChatView() {
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
                onTap: state.currentRoom?.permissions.canEditAnything == true
                    ? () => state.navigateRoomSettings()
                    : null,
                menu: RoomQuickAccessMenuViewDesktop(room: state.currentRoom!),
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
          builder: (state, child) {
            Widget result = Tile.surfaceContainer(
              caulkPadLeft: true,
              caulkPadBottom: true,
              caulkClipBottomLeft: true,
              caulkClipTopLeft: true,
              child: child,
            );

            if (state == SidePanelState.thread ||
                state == SidePanelState.calendar) {
              result = Flexible(child: result);
            }

            return result;
          },
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
          child: ImportantRoomsList(
              state: state,
              directMessagesListHeaderDesktop: directMessagesListHeaderDesktop),
        ),
      );
    } else {
      return spaceRoomSelector(context);
    }
  }

  Widget mainView(BuildContext context) {
    if (state.currentView == MainPageSubView.home ||
        state.currentView == MainPageSubView.rooms)
      // Vommet: was Flexible inside the caller's Expanded; release builds
      // applied the outer Expanded, so keep that behaviour.
      return Expanded(child: homeView());
    if (state.currentRoom != null && state.currentView != MainPageSubView.home)
      return roomChatView();
    if (state.currentSpace != null && state.currentRoom == null)
      return Expanded(
        child: Tile(
          caulkPadTop: true,
          caulkPadBottom: true,
          caulkPadLeft: true,
          caulkClipTopLeft: true,
          caulkBorderLeft: true,
          caulkClipBottomLeft: true,
          child: ListView(
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
      );

    return Expanded(child: Placeholder());
  }
}
