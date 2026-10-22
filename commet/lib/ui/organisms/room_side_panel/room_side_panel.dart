import 'dart:async';

import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/molecules/room_banner.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/room_members_list/room_members_list.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_actions_bar.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu_mobile.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/ui/organisms/room_widgets/room_widgets_view.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet_calendar_widget/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum SidePanelState {
  defaultView,
  thread,
  pinnedMessages,
  calendar,
  // Vommet: the room's thread list.
  threads,
  widgets,
  nothing
}

class RoomSidePanel extends StatefulWidget {
  const RoomSidePanel(
      {required this.state, this.builder, this.onStateChanged, super.key});

  final MainPageState state;

  final Widget Function(SidePanelState state, Widget child)? builder;

  /// Vommet: told when the panel switches view (members, thread, closed...).
  final ValueChanged<SidePanelState>? onStateChanged;

  @override
  State<RoomSidePanel> createState() => _RoomSidePanelState();

  /// Vommet issue 468: closing a thread goes back to the thread list it was
  /// opened from, else to the member list, or leaves the panel closed when
  /// it was closed before (the toggle arrow follows `hideRoomSidePanel`).
  static SidePanelState stateAfterThreadClosed(
      {required bool fromThreadsList, required bool panelHidden}) {
    if (fromThreadsList) return SidePanelState.threads;
    return panelHidden ? SidePanelState.nothing : SidePanelState.defaultView;
  }
}

class _RoomSidePanelState extends State<RoomSidePanel> {
  String? _currentThreadId;
  String? get currentThreadId => _currentThreadId;

  // Vommet: closing a thread opened from the thread list goes back to it.
  bool _threadFromList = false;

  // Vommet issue 322: the thread "Reply in Thread" is opening, and whether
  // the open thread's message box takes the focus when it's shown.
  String? _replyInThreadId;
  bool _focusThreadInput = false;

  late SidePanelState _state;
  SidePanelState get state => _state;
  set state(SidePanelState value) {
    _state = value;
    widget.onStateChanged?.call(value);
  }

  late List<StreamSubscription> subs;

  @override
  void initState() {
    _state = preferences.hideRoomSidePanel.value
        ? SidePanelState.nothing
        : SidePanelState.defaultView;

    subs = [
      EventBus.replyInThread.stream
          .listen((rootEventId) => _replyInThreadId = rootEventId),
      EventBus.openThread.stream.listen(onOpenThreadSignal),
      EventBus.closeThread.stream.listen(onCloseThreadSignal),
      // Vommet: the pinned message bar's list button.
      EventBus.showPinnedMessages.stream
          .listen((_) => setState(() => state = SidePanelState.pinnedMessages)),
      EventBus.openPinnedMessages.stream.listen(onShowPinnedMessages),
      EventBus.openThreadsList.stream.listen(onShowThreadsList),
      EventBus.openCalendar.stream.listen(onShowCalendar),
      EventBus.openWidgets.stream.listen(onShowWidgets),
      EventBus.toggleRoomSidePanel.stream.listen(onToggleSidePanel),
      // Vommet: the banner header comes and goes with the banner.
      if (widget.state.currentRoom
              ?.getComponent<RoomBannerComponent>()
              ?.onBannerChanged
          case final Stream<void> bannerChanges)
        bannerChanges.listen((_) {
          if (mounted) setState(() {});
        }),
    ];
    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    final openThread = _currentThreadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (EventBus.openThreadRootId.value == openThread) {
        EventBus.openThreadRootId.value = null;
      }
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncOpenThreadRoot();
    Widget result = buildPanelContent(context);

    result = Material(
      color: Colors.transparent,
      child: result,
    );

    if (widget.builder != null) {
      result = widget.builder!.call(state, result);
    }

    // if (state == _SidePanelState.thread) {
    //   result = Flexible(child: result);
    // }

    return result;
  }

  /// Vommet issue 457: tells the main timeline which thread is showing, so
  /// it shades that thread's root message. Set after the frame: listeners
  /// rebuild other widgets.
  void _syncOpenThreadRoot() {
    String? showing() =>
        state == SidePanelState.thread ? _currentThreadId : null;
    if (EventBus.openThreadRootId.value == showing()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) EventBus.openThreadRootId.value = showing();
    });
  }

  Widget buildPanelContent(BuildContext context) {
    var s = state;
    if (s == SidePanelState.nothing && MediaQuery.of(context).mobile) {
      s = SidePanelState.defaultView;
    }

    switch (s) {
      case SidePanelState.defaultView:
        return buildDefaultView();
      case SidePanelState.thread:
        return buildThread();
      case SidePanelState.pinnedMessages:
        return buildPinnedMessages();
      case SidePanelState.threads:
        return buildThreadsList();
      case SidePanelState.calendar:
        return buildCalendar();
      case SidePanelState.nothing:
        return SizedBox(
          width: 0,
        );
      case SidePanelState.widgets:
        return buildWidgets();
    }
  }

  void onOpenThreadSignal((String, String, String) event) {
    var clientId = event.$1;
    var roomId = event.$2;
    var threadId = event.$3;

    EventBus.doOpenRoom(roomId, clientId: clientId, threadId: threadId);

    setState(() {
      _threadFromList = state == SidePanelState.threads;
      _focusThreadInput = _replyInThreadId == threadId;
      _replyInThreadId = null;
      _currentThreadId = threadId;
      state = SidePanelState.thread;
    });
  }

  void onCloseThreadSignal(void event) {
    setState(() {
      _currentThreadId = null;
      state = RoomSidePanel.stateAfterThreadClosed(
          fromThreadsList: _threadFromList,
          panelHidden: preferences.hideRoomSidePanel.value);
      _threadFromList = false;
    });
  }

  void onShowThreadsList(void event) {
    setState(() {
      if (state == SidePanelState.threads) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.threads;
      }
    });
  }

  Widget buildThreadsList() {
    final room = widget.state.currentRoom!;
    final mobile = MediaQuery.of(context).mobile;
    return SizedBox(
        width: mobile ? null : 320,
        child: Column(
          children: [
            if (mobile)
              RoomQuickAccessMenuViewMobile(
                room: room,
                key: ValueKey("quick_access_menu_${room.localId}"),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const Expanded(child: tiamat.Text.labelEmphasised("Threads")),
                  IconButton(
                    key: const ValueKey("threads-panel-close"),
                    tooltip: "Close",
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => state = SidePanelState.defaultView),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RoomThreadsListWidget(
                room: room,
                key: ValueKey("room-threads-${room.localId}"),
              ),
            ),
          ],
        ));
  }

  Widget buildDefaultView() {
    final room = widget.state.currentRoom!;
    final mobile = MediaQuery.of(context).mobile;
    final hasBanner = room.getComponent<RoomBannerComponent>()?.banner != null;
    // Collapsing banners are part of the Discord-style layout experiment;
    // without it the banner keeps its full height and stays put.
    final collapsing = preferences.experimentBannerLayout.value;
    Widget banner(double height) => RoomBanner(
          room,
          height: height,
          key: ValueKey("room_banner_${room.localId}"),
        );

    // Vommet: the banner and (on phones) the room actions scroll with the
    // member list.
    // - Desktop: the banner shrinks to its 50 px name bar (name and menu),
    //   level with the room header, and stays.
    // - Phone, Discord-style layout: the banner slides up under the actions
    //   row, which stays pinned on its own (one row instead of two); the
    //   room's name with its menu glides from the banner into that row, as
    //   the space name does.
    // - Phone without the experiment: banner and actions row both stay.
    final phoneBar = mobile && collapsing;
    return RoomMembersListWidget(
      room,
      header: [
        if (hasBanner && !phoneBar)
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingHeaderDelegate(
              minHeight: collapsing
                  ? RoomBannerView.compactHeight
                  : RoomBannerView.fullHeight,
              maxHeight: RoomBannerView.fullHeight,
              builder: (context, height) => banner(height),
            ),
          ),
        if (phoneBar)
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingHeaderDelegate(
              minHeight: 50,
              maxHeight: 50 + (hasBanner ? RoomBannerView.fullHeight : 0),
              builder: (context, height) => RoomActionsBar(
                room,
                key: ValueKey("room_actions_bar_${room.localId}"),
                banner: hasBanner
                    ? RoomBanner(room,
                        showTitle: false,
                        key: ValueKey("room_banner_${room.localId}"))
                    : null,
                bannerHeight: height - 50,
              ),
            ),
          ),
        if (mobile && !phoneBar)
          SliverPersistentHeader(
            pinned: true,
            delegate: CollapsingHeaderDelegate(
              minHeight: 50,
              maxHeight: 50,
              builder: (context, height) => RoomQuickAccessMenuViewMobile(
                room: room,
                key: ValueKey("quick_access_menu_${room.localId}"),
              ),
            ),
          ),
      ],
    );
  }

  Widget buildThread() {
    return Tile(
      caulkPadLeft: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      caulkPadBottom: true,
      child: Column(
        children: [
          Flexible(
            child: Stack(
              children: [
                Chat(
                  widget.state.currentRoom!,
                  threadId: currentThreadId,
                  focusMessageInput: _focusThreadInput,
                  key: ValueKey(
                      "room-timeline-key-${widget.state.currentRoom!.localId}_thread_$currentThreadId"),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: tiamat.CircleButton(
                      icon: Icons.close,
                      radius: 24,
                      onPressed: () => EventBus.closeThread.add(null),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void onShowPinnedMessages(void event) {
    setState(() {
      if (state == SidePanelState.pinnedMessages) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.pinnedMessages;
      }
    });
  }

  void onShowCalendar(void event) {
    setState(() {
      if (state == SidePanelState.calendar) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.calendar;
      }
    });
  }

  Widget buildPinnedMessages() {
    return SizedBox(
        width: MediaQuery.of(context).desktop ? 300 : null,
        child: Column(
          children: [
            if (MediaQuery.of(context).mobile)
              RoomQuickAccessMenuViewMobile(
                room: widget.state.currentRoom!,
                key: ValueKey(
                    "quick_access_menu_${widget.state.currentRoom!.localId}"),
              ),
            Expanded(
              child: RoomPinnedMessagesWidget(
                room: widget.state.currentRoom!,
                onEventClicked: (eventId) {
                  EventBus.jumpToEvent.add(eventId);
                  EventBus.focusTimeline.add(null);
                },
              ),
            ),
          ],
        ));
  }

  Widget buildCalendar() {
    var calendar = widget.state.currentRoom?.getComponent<CalendarRoom>();
    if (calendar?.hasCalendar != true) {
      return Placeholder();
    }

    var query = MediaQuery.of(context);

    return tiamat.Tile.low(
      child: Column(
        children: [
          if (MediaQuery.of(context).mobile)
            RoomQuickAccessMenuViewMobile(
              room: widget.state.currentRoom!,
              key: ValueKey(
                  "quick_access_menu_${widget.state.currentRoom!.localId}"),
            ),
          if (MediaQuery.of(context).mobile)
            Divider(
              height: 2,
            ),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            var newQuery = query.copyWith(
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );

            return Container(
              color: Theme.of(context).colorScheme.surface,
              child: ScaledSafeArea(
                top: false,
                bottom: true,
                child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: MediaQuery(
                        data: newQuery,
                        child: CalendarWidgetView(
                            calendar: calendar!.calendar!,
                            watermark: false,
                            useMobileLayout: MediaQuery.of(context).mobile,
                            autoDisposeCalendar: false))),
              ),
            );
          })),
        ],
      ),
    );
  }

  Widget buildWidgets() {
    return SizedBox(
        width: MediaQuery.of(context).desktop ? 250 : null,
        child: Column(
          children: [
            if (MediaQuery.of(context).mobile)
              RoomQuickAccessMenuViewMobile(
                room: widget.state.currentRoom!,
                key: ValueKey(
                    "quick_access_menu_${widget.state.currentRoom!.localId}"),
              ),
            Expanded(child: RoomWidgetsView(widget.state.currentRoom!)),
          ],
        ));
  }

  void onToggleSidePanel(void event) {
    // Vommet: a window too narrow for the member list floats it instead.
    if (RoomChatLayout.toggleFloatingMembers(context)) return;
    preferences.hideRoomSidePanel.set(!preferences.hideRoomSidePanel.value);

    if (preferences.hideRoomSidePanel.value) {
      setState(() {
        state = SidePanelState.nothing;
      });
    } else {
      setState(() {
        state = SidePanelState.defaultView;
      });
    }
  }

  void onShowWidgets(void event) {
    setState(() {
      if (state == SidePanelState.widgets) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.widgets;
      }
    });
  }
}
