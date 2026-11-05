import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/ongoing_call_strip.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/molecules/space_sidebar_list.dart';
import 'package:commet/ui/molecules/space_viewer.dart';
import 'package:commet/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:commet/ui/organisms/friends/friends_home_tile.dart';
import 'package:commet/ui/organisms/home_screen/home_screen.dart';
import 'package:commet/ui/organisms/home_screen/single_rooms_list.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/room_members_list/room_members_list.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:commet/ui/organisms/space_summary/space_summary.dart';
import 'package:commet/ui/molecules/room_timeline_widget/chat_on_screen.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:flutter/material.dart' as material;
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_main_page.dart';

class MainPageViewMobile extends StatefulWidget {
  const MainPageViewMobile(this.state, {super.key});
  final MainPageState state;

  @override
  State<MainPageViewMobile> createState() => _MainPageViewMobileState();
}

class _MainPageViewMobileState extends State<MainPageViewMobile> {
  late GlobalKey<OverlappingPanelsState> panelsKey;
  bool shouldMainIgnoreInput = false;
  double height = -1;

  String get directMessagesListHeaderMobile => Intl.message("Direct Messages",
      desc: "The header for the direct messages list on desktop",
      name: "directMessagesListHeaderMobile");

  GlobalKey mainPanelKey = GlobalKey();

  // Vommet issue 408: the chat behind the room list isn't on screen.
  final ValueNotifier<bool> chatOnScreen = ValueNotifier(true);

  @override
  void initState() {
    panelsKey = GlobalKey<OverlappingPanelsState>();

    // Vommet New Home: a Home page shows in the main panel, like a room.
    newHomeShowPage.stream.listen((_) {
      panelsKey.currentState?.reveal(RevealSide.main);
    });

    EventBus.openThread.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.right);
    });

    EventBus.closeThread.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.main);
    });

    EventBus.focusTimeline.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.main);
    });

    // Vommet: the pinned message bar's list button.
    EventBus.showPinnedMessages.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.right);
    });

    EventBus.openRoom.stream.listen((a) {
      if (a.threadId == null) {
        panelsKey.currentState?.reveal(RevealSide.main);
      } else {
        panelsKey.currentState?.reveal(RevealSide.right);
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    chatOnScreen.dispose();
    super.dispose();
  }

  bool canPop() {
    switch (panelsKey.currentState?.currentSide) {
      case RevealSide.right:
        return false;
      case RevealSide.main:
        return false;
      case RevealSide.left:
        return true;
      case null:
        //idk in what case this will ever happen...
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: the Telegram-style chat list replaces the rail (issue 291).
    if (unifiedChatListEnabled) return UnifiedMainPageMobile(widget.state);
    return PopScope(
        canPop: canPop(),
        onPopInvokedWithResult: (didPop, result) {
          var event = ScopePopped();
          event.currentMobileSide = panelsKey.currentState?.currentSide;

          EventBus.onPopInvoked.add(event);

          if (event.handled) {
            return;
          }

          if (widget.state.currentView == MainPageSubView.home &&
              widget.state.currentRoom != null) {
            if (widget.state.currentRoom != null) {
              var dm = widget.state.currentRoom!.client
                  .getComponent<DirectMessagesComponent>();
              if (dm?.isRoomDirectMessage(widget.state.currentRoom!) == true) {
                panelsKey.currentState?.reveal(RevealSide.left);
                return;
              }
            }

            widget.state.selectHome();

            return;
          }

          switch (panelsKey.currentState?.currentSide) {
            case RevealSide.right:
              panelsKey.currentState?.reveal(RevealSide.main);
            case RevealSide.main:
              panelsKey.currentState?.reveal(RevealSide.left);
            default:
              break;
          }
        },
        child: Foundation(
            child: Stack(
          children: [
            OverlappingPanels(
              key: panelsKey,
              // Vommet: a narrower strip of the next panel (32 dp with the
              // gap) gives the room list room for long names.
              restWidth:
                  preferences.experimentSidebarSubspaceGuides.value ? 29 : 40,
              onSideChange: (side) {
                // Vommet issue 322: the panels drop the focus of a panel that
                // slides away themselves; unfocusing everything here also
                // took it from the thread's message box that had just opened.
                setState(() {
                  shouldMainIgnoreInput = side != RevealSide.main;
                });
                chatOnScreen.value = side != RevealSide.left;
              },
              left: navigation(context),
              main: Foundation(
                  child: IgnorePointer(
                ignoring: shouldMainIgnoreInput,
                child: ChatOnScreen(
                    visible: chatOnScreen,
                    child: Container(key: mainPanelKey, child: mainPanel())),
              )),
              right: rightPanel(context),
            ),
            const OverlayWindowsSurface(),
          ],
        )));
  }

  Widget? rightPanel(BuildContext context) {
    if (widget.state.currentRoom != null) {
      return Tile(
        caulkPadLeft: true,
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        child: Column(
          children: [
            Tile.low(
              child: ScaledSafeArea(
                  child: Container(),
                  bottom: false,
                  top: true,
                  left: false,
                  right: false),
            ),
            Expanded(
              child: RoomSidePanel(
                  key: ValueKey(
                      "room-side-panel-${widget.state.currentRoom!.localId}"),
                  state: widget.state),
            )
          ],
        ),
      );
    }

    return null;
  }

  Widget navigation(BuildContext newContext) {
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Tile(
                  caulkPadRight: true,
                  caulkClipTopRight: true,
                  caulkClipBottomRight: true,
                  caulkBorderRight: true,
                  mode: TileType.surfaceDim,
                  child: ScaledSafeArea(
                    bottom: false,
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                      child: SideNavigationBar(
                        currentUser: widget.state.getCurrentUser(),
                        onSpaceSelected: (space) {
                          // Vommet: the last room shows highlighted in the
                          // space's room list, with its chat behind it.
                          widget.state
                              .openSpaceHome(space, restoreLastRoom: true);
                        },
                        clearSpaceSelection: () {
                          widget.state.clearSpaceSelection();
                        },
                        onHomeSelected: () {
                          widget.state.selectHome();
                        },
                        onRoomsViewSelected: () {
                          widget.state.selectRoomsView();
                        },
                        onDirectMessageSelected: (room) {
                          widget.state.selectHome();
                          widget.state.selectRoom(room);
                          panelsKey.currentState?.reveal(RevealSide.main);
                        },
                      ),
                    ),
                  ),
                ),
                if (widget.state.currentView == MainPageSubView.home)
                  directMessagesView(),
                if (widget.state.currentView == MainPageSubView.rooms)
                  Flexible(
                      child: Tile.surfaceContainer(
                          caulkClipTopLeft: true,
                          caulkClipBottomLeft: true,
                          caulkPadRight: true,
                          caulkClipTopRight: true,
                          caulkClipBottomRight: true,
                          child: SingleRoomsList(
                            state: widget.state,
                            onSelectRoom: (r) => selectRoom(r),
                          ))),
                if (widget.state.currentView == MainPageSubView.space &&
                    widget.state.currentSpace != null)
                  spaceRoomSelector(newContext),
                const BackgroundTaskViewContainer()
              ],
            ),
          ),
          tiamat.Tile.low(
            caulkPadTop: true,
            caulkClipTopRight: true,
            caulkBorderTop: true,
            caulkPadRight: MediaQuery.of(context).mobile,
            child: ScaledSafeArea(
              bottom: true,
              top: false,
              child: CurrentSessionPanel(
                currentUser: widget.state.currentUser,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget mainPanel() {
    if (widget.state.currentSpace != null && widget.state.currentRoom == null) {
      return Tile(
        child: ScaledSafeArea(
          top: false,
          child: Column(children: [
            // Vommet issue 422: the call you're in, on a space's page too.
            const OngoingCallStrip(),
            Expanded(
              child: SingleChildScrollView(
                child: SpaceSummary(
                  key: ValueKey(
                      "space-summary-key-${widget.state.currentSpace!.localId}"),
                  space: widget.state.currentSpace!,
                  onRoomTap: (room) {
                    widget.state.selectRoom(room);
                  },
                  onSpaceTap: (space) => widget.state.selectSpace(space),
                  onLeaveRoom: widget.state.clearRoomSelection,
                ),
              ),
            ),
          ]),
        ),
      );
    }

    if (widget.state.currentRoom != null) {
      var scaledQuery = MediaQuery.of(context).scale();
      var offset = scaledQuery.viewInsets.bottom;
      if (offset == 0) {
        offset = scaledQuery.padding.bottom;
      }
      return Tile(
        key: ValueKey("room-chat-view-${widget.state.currentRoom!.localId}"),
        child: Column(
          children: [
            if (MediaQuery.of(context).mobile)
              Tile.low(
                caulkClipBottomRight: true,
                caulkClipBottomLeft: true,
                caulkBorderBottom: true,
                child: ScaledSafeArea(
                  bottom: false,
                  left: false,
                  right: false,
                  child: SizedBox(
                    height: 50,
                    child: RoomHeader(
                      widget.state.currentRoom!,
                      onTap: roomInfoPageEnabled ||
                              widget.state.currentRoom?.permissions
                                      .canEditAnything ==
                                  true
                          ? () => widget.state.navigateRoomSettings()
                          : null,
                      menu: phoneRoomHeaderMenu(
                          context,
                          widget.state.currentRoom!,
                          Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: tiamat.IconButton(
                                icon: material.Icons.chevron_right,
                                onPressed: () {
                                  panelsKey.currentState
                                      ?.reveal(RevealSide.right);
                                },
                              ),
                            ),
                          )),
                      onBurgerMenuTap: () {
                        panelsKey.currentState?.reveal(RevealSide.left);
                      },
                    ),
                  ),
                ),
              ),
            // Vommet issue 422: a call in another room stays reachable.
            if (MediaQuery.of(context).mobile)
              OngoingCallStrip(currentRoom: widget.state.currentRoom),
            Expanded(
              child: RoomPrimaryView(
                widget.state.currentRoom!,
                bypassSpecialRoomTypes: widget.state.showAsTextRoom,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      child: FriendsHomeTile(
          child: HomeScreen(
        clientManager: widget.state.clientManager,
        filterClient: widget.state.filterClient,
        onBurgerMenuTap: () {
          panelsKey.currentState?.reveal(RevealSide.left);
        },
      )),
    );
  }

  Widget userList() {
    if (widget.state.currentRoom != null) {
      return Tile.surfaceContainer(
        caulkPadLeft: true,
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        caulkBorderLeft: true,
        caulkBorderTop: true,
        caulkBorderBottom: true,
        child: ScaledSafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: RoomMembersListWidget(
              widget.state.currentRoom!,
              key: ValueKey(
                  "room-participant-list-key-${widget.state.currentRoom!.localId}"),
            ),
          ),
        ),
      );
    }
    return const Placeholder();
  }

  Widget directMessagesView() {
    return Flexible(
      child: Tile.surfaceContainer(
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        caulkPadRight: true,
        caulkClipTopRight: true,
        caulkClipBottomRight: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
          child: ScaledSafeArea(
            top: true,
            bottom: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: HomeColumn(
                      state: widget.state,
                      directMessagesListHeaderDesktop:
                          directMessagesListHeaderMobile),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget spaceRoomSelector(BuildContext newContext) {
    return Flexible(
      child: Tile.surfaceContainer(
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        caulkPadRight: true,
        caulkClipTopRight: true,
        caulkClipBottomRight: true,
        // Vommet: header and room list scroll together; the header collapses.
        child: SpaceSidebarList(
          widget.state.currentSpace!,
          key: ValueKey("space-sidebar-${widget.state.currentSpace!.localId}"),
          onHeaderTap: clearSelectedRoom,
          child: SpaceViewer(
            widget.state.currentSpace!,
            key: ValueKey(
                "space-view-key-${widget.state.currentSpace!.localId}"),
            onRoomSelected: (room, {bypassSpecialRoomType = false}) async {
              selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
            },
          ),
        ),
      ),
    );
  }

  void clearSelectedRoom() {
    Future.delayed(const Duration(milliseconds: 125)).then((value) {
      panelsKey.currentState!.reveal(RevealSide.main);
      setState(() {
        shouldMainIgnoreInput = false;
      });
    });
    widget.state.clearRoomSelection();
  }

  void selectRoom(Room room, {bypassSpecialRoomType = false}) {
    panelsKey.currentState!.reveal(RevealSide.main);
    setState(() {
      shouldMainIgnoreInput = false;
    });

    widget.state.selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
  }
}
