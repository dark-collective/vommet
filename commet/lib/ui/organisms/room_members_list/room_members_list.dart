import 'dart:math';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
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
  media("Media"),
  files("Files"),
  pins("Pins");

  const MemberPanelTab(this.label);
  final String label;
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;
  MemberPanelTab tab = MemberPanelTab.members;
  RoomAttachmentFeed? feed;

  @override
  void initState() {
    isDirectMessage = RoomMembersListWidget.isDirectMessage(widget.room);
    super.initState();
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
  }

  Widget _tabStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
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
      return SizedBox(
        width: width,
        child: CustomScrollView(
          key: ValueKey("member-panel-${tab.name}-${widget.room.localId}"),
          slivers: [
            ...leading,
            if (tab == MemberPanelTab.pins)
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
    return SizedBox(
      width: width,
      child: RoomMemberList(
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
