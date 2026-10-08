import 'dart:math';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/molecules/user_list.dart';
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

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;
  @override
  void initState() {
    isDirectMessage = RoomMembersListWidget.isDirectMessage(widget.room);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: header, label and members share one scroll view so the banner
    // can collapse (desktop) or scroll away (phone) as the list scrolls.
    return SizedBox(
      width: RoomMembersListWidget.widthFor(context, widget.room),
      child: RoomMemberList(
        key: ValueKey("room-participant-list-key-${widget.room.localId}"),
        widget.room,
        leading: [
          ...widget.header,
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              // Styled like the space list's section headers opposite.
              child: isDirectMessage
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
