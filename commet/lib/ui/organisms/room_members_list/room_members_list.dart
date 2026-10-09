import 'dart:math';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/tab_swipe.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(this.room, {this.header = const [], super.key});
  final Room room;

  /// Vommet: slivers above the label (the room banner, the phone's room
  /// actions), scrolling with the list.
  final List<Widget> header;

  /// The list's fixed width on desktop, or null to fill the panel.
  static double? widthFor(BuildContext context, Room room) {
    if (!MediaQuery.of(context).desktop) return null;
    // Vommet: the resizable right pane (the list pads itself inside it).
    final width = PaneWidths.right.effective;
    return isDirectMessage(room) ? max(width, 316) : width;
  }

  static bool isDirectMessage(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ??
      false;

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

/// Vommet: the member panel's tabs (Discord's channel panel).
enum MemberPanelTab {
  members("Members"),
  threads("Threads"),
  media("Media"),
  files("Files"),
  pins("Pins");

  const MemberPanelTab(this.label);
  final String label;
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;
  // Vommet: the open tab per room, so closing a thread opened from the
  // Threads tab comes back to it.
  static final Map<String, MemberPanelTab> _lastTab = {};

  late MemberPanelTab tab =
      _lastTab[widget.room.localId] ?? MemberPanelTab.members;

  // One per tab: while tabs fade, the outgoing and incoming pages both draw
  // their strip.
  final _stripKeys = {for (final t in MemberPanelTab.values) t: GlobalKey()};
  RoomAttachmentFeed? feed;

  @override
  void initState() {
    isDirectMessage = RoomMembersListWidget.isDirectMessage(widget.room);
    super.initState();
    if (tab == MemberPanelTab.media || tab == MemberPanelTab.files) {
      feed = RoomAttachmentFeed(widget.room)..addListener(_onFeed);
      feed!.start();
    }
  }

  @override
  void dispose() {
    feed?.removeListener(_onFeed);
    feed?.dispose();
    super.dispose();
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  // The tabs are part of the Discord-style layout experiment.
  bool get _tabs =>
      preferences.experimentBannerLayout.value && !isDirectMessage;

  void _select(MemberPanelTab value) {
    if (value == MemberPanelTab.media || value == MemberPanelTab.files) {
      if (feed == null) {
        feed = RoomAttachmentFeed(widget.room)..addListener(_onFeed);
        feed!.start();
      }
    }
    setState(() => tab = value);
    _lastTab[widget.room.localId] = value;
  }

  Widget _tabStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: _stripKeys[tab],
      color: scheme.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            for (final value in MemberPanelTab.values)
              InkWell(
                key: ValueKey("member-panel-tab-${value.name}"),
                onTap: () => _select(value),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          width: 2,
                          color: value == tab
                              ? scheme.primary
                              : Colors.transparent),
                    ),
                  ),
                  child: Text(value.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: value == tab
                              ? scheme.primary
                              : scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Swipes change tabs only on the tab's content: below the tab strip and
  /// clear of the panel's left edge. On the banner, the actions, the strip
  /// or the edge they always move the panel itself.
  bool _inTabContent(Offset global) {
    final strip = _stripKeys[tab]?.currentContext?.findRenderObject();
    if (strip is! RenderBox || !strip.attached) return false;
    final topLeft = strip.localToGlobal(Offset.zero);
    return global.dy > topLeft.dy + strip.size.height &&
        global.dx > topLeft.dx + 24;
  }

  /// Vommet: with tabs, swipe between them (see TabSwipeDetector) and fade
  /// from one to the next. Every tab draws the same banner and tab strip
  /// over its own scroll view, so a fade keeps them still where a slide
  /// would move them.
  Widget _swipeable(double? width, Widget page) {
    if (!_tabs) return SizedBox(width: width, child: page);
    const tabs = MemberPanelTab.values;
    return SizedBox(
      width: width,
      child: TabSwipeDetector(
        canSwipe: (direction) {
          final next = tab.index + direction;
          return next >= 0 && next < tabs.length;
        },
        onSwipe: (direction) => _select(tabs[tab.index + direction]),
        startsHere: _inTabContent,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: KeyedSubtree(key: ValueKey(tab), child: page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leading = [
      ...widget.header,
      if (_tabs)
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
              minHeight: 44,
              maxHeight: 44,
              builder: (context, _) => _tabStrip(context)),
        ),
    ];
    final width = RoomMembersListWidget.widthFor(context, widget.room);

    if (_tabs && tab != MemberPanelTab.members) {
      final feed = this.feed;
      return _swipeable(
        width,
        CustomScrollView(
          key: ValueKey("member-panel-${tab.name}-${widget.room.localId}"),
          slivers: [
            ...leading,
            if (tab == MemberPanelTab.threads)
              SliverFillRemaining(
                child: RoomThreadsListWidget(
                  room: widget.room,
                  key: ValueKey("room-threads-tab-${widget.room.localId}"),
                ),
              )
            else if (tab == MemberPanelTab.pins)
              SliverFillRemaining(
                child: RoomPinnedMessagesWidget(
                  room: widget.room,
                  onEventClicked: (eventId) {
                    EventBus.jumpToEvent.add(eventId);
                    EventBus.focusTimeline.add(null);
                  },
                ),
              )
            else if (feed != null) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                sliver: tab == MemberPanelTab.media
                    ? RoomMediaGrid(feed)
                    : RoomFilesList(feed),
              ),
              SliverToBoxAdapter(
                child: RoomAttachmentsFooter(
                    feed,
                    tab == MemberPanelTab.media
                        ? RoomAttachmentKind.media
                        : RoomAttachmentKind.files),
              ),
            ],
          ],
        ),
      );
    }

    // Vommet: header, label and members share one scroll view so the banner
    // can collapse (desktop) or scroll away (phone) as the list scrolls.
    return _swipeable(
      width,
      RoomMemberList(
        key: ValueKey("room-participant-list-key-${widget.room.localId}"),
        widget.room,
        leading: [
          ...leading,
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              // Styled like the space list's section headers opposite.
              child: isDirectMessage || _tabs
                  ? null
                  : const Padding(
                      padding: EdgeInsets.fromLTRB(0, 4, 0, 8),
                      child: tiamat.Text.labelEmphasised("Room Members"),
                    ),
            ),
          ),
        ],
        listPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
