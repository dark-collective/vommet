import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/room_row_size.dart';
import 'package:commet/ui/molecules/dm_chats_picker.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/room_avatar_badge.dart';
import 'package:commet/ui/atoms/list_trust_marker.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/utils/dm_topic_line.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomPanel extends StatefulWidget {
  const RoomPanel(this.room,
      {this.onTap,
      super.key,
      this.shouldShowAvatarForRoom,
      this.nameSuffix,
      this.nameHighlight,
      this.searchLine,
      this.searchLineHighlight,
      this.leadingMenuItems = const []});

  final Room room;
  final Function()? onTap;

  @override
  State<RoomPanel> createState() => _RoomPanelState();

  final bool Function(Room room)? shouldShowAvatarForRoom;

  /// Vommet: muted text after the name (a New Home Rooms section's space).
  final String? nameSuffix;

  /// Vommet (New Home search): the matched part of the name.
  final ({int start, int end})? nameHighlight;

  /// Vommet (New Home search): the line under the name instead of the last
  /// message (a room's space path, a topic snippet), and its matched part.
  final String? searchLine;
  final ({int start, int end})? searchLineHighlight;

  /// Vommet: items above the room's usual menu ("Go to <space>").
  final List<tiamat.ContextMenuItem> leadingMenuItems;
}

class _RoomPanelState extends State<RoomPanel> {
  late List<StreamSubscription> subs;
  String? directMessagePartner;
  UserPresence? presence = null;
  List<Member> typingUsers = [];

  /// Vommet issue 639: this row's room is the open one.
  bool selected = false;

  bool isOpenRoom(Room? room) =>
      room != null &&
      room.identifier == widget.room.identifier &&
      room.client.identifier == widget.room.client.identifier;

  @override
  void initState() {
    subs = List.empty(growable: true);
    subs.add(widget.room.onUpdate.listen((_) => setState(() {})));
    // Vommet issue 796: Standard or Large rows.
    subs.add(roomRowSizePreference.onChanged.listen((_) {
      if (mounted) setState(() {});
    }));
    selected = isOpenRoom(EventBus.selectedRoom);
    subs.add(EventBus.onSelectedRoomChanged.stream.listen((room) {
      final now = isOpenRoom(room);
      if (now != selected && mounted) setState(() => selected = now);
    }));

    var dm = widget.room.client.getComponent<DirectMessagesComponent>();
    directMessagePartner = dm?.getDirectMessagePartnerId(widget.room);

    var typing = widget.room.getComponent<TypingIndicatorComponent>();

    if (typing != null) {
      subs.add(typing.onTypingUsersUpdated.listen((_) {
        setState(() {
          typingUsers = typing.typingUsers;
        });
      }));

      typingUsers = typing.typingUsers;
    }

    if (directMessagePartner != null) {
      final presenceComponent =
          widget.room.client.getComponent<UserPresenceComponent>();

      if (presenceComponent == null) {
        return;
      }

      presenceComponent.getUserPresence(directMessagePartner!).then((s) {
        // Vommet: the panel can be gone by the time the presence arrives.
        if (!mounted) return;
        setState(() {
          presence = s;
        });
      });

      subs.add(presenceComponent.onPresenceChanged
          .where((tuple) => tuple.$1 == directMessagePartner)
          .listen(userPresenceChanged));
    }

    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDm = directMessagePartner != null;
    final redaction = RedactionScope.of(context);
    String? eventSender = widget.room.lastMessage?.senderId;
    final eventSenderId = eventSender;

    if (eventSender != null) {
      if (eventSender == widget.room.client.self!.identifier) {
        eventSender = "You";
      } else {
        if (isDm) {
          eventSender = null;
        } else {
          var member = widget.room.getMemberOrFallback(eventSender);
          eventSender = redaction.name(member.displayName, eventSender);
        }
      }
    }

    return AdaptiveContextMenu(
      items: [
        ...widget.leadingMenuItems,
        ...RoomTextButton.createRoomContextMenuItems(context, widget.room),
      ],
      child: RoomPanelView(
        displayName: redaction.roomDisplayName(widget.room),
        avatar: widget.room.avatar,
        onTap: widget.onTap ??
            () {
              EventBus.doOpenRoom(widget.room.identifier,
                  clientId: widget.room.client.identifier);
            },
        color: widget.room.defaultColor,
        showUserAvatar: widget.shouldShowAvatarForRoom == null
            ? false
            : widget.shouldShowAvatarForRoom!(widget.room),
        userColor: widget.room.client.self?.defaultColor,
        userDisplayName: widget.room.client.self?.displayName,
        userAvatar: widget.room.client.self?.avatar,
        directMessagePartner: directMessagePartner,
        // Vommet: amber/red DM marker after the name (Vommet issue 131).
        nameTrailing: isDm
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                ListTrustMarker(widget.room),
                // Vommet issue 99: more than one room with them.
                DmChatsCountChip(room: widget.room),
              ])
            : null,
        nameSuffix: widget.nameSuffix,
        nameHighlight: widget.nameHighlight,
        // Vommet: a DM's topic (bridge rich presence) under the name; in
        // search results, the search line.
        subtitle: widget.searchLine ??
            (isDm ? dmTopicLine(redaction.roomTopic(widget.room.topic)) : null),
        subtitleHighlight: widget.searchLineHighlight,
        userPresence: presence,
        recentEventSender: eventSender,
        recentEventSenderColor: eventSenderId != null
            ? redaction.nameColor(
                widget.room.getColorOfUser(eventSenderId), eventSenderId)
            : null,
        body: widget.searchLine != null || widget.room.lastMessage == null
            ? null
            : redaction.text(widget.room.lastMessage!.plainTextBody),
        // Vommet: the dot follows Discord's unread rule (muted: no dot)
        // (Vommet issue 99: any of a person's rooms.)
        notificationCount: (isDm ? DmChats.of(widget.room) : const <Room>[])
                    .any(roomHasUnread) ||
                roomHasUnread(widget.room)
            ? 1
            : 0,
        typingMembers: typingUsers,
        // Vommet issue 719: grey or red, as in the room list.
        highlightNotificationCount: widget.room.badgeCount,
        highlightNoisy: widget.room.badgeNoisy,
        avatarBadge: roomAvatarBadge(widget.room),
        selectedColor: selected
            ? Theme.of(context).extension<ExtraColors>()?.selectedRoom
            : null,
      ),
    );
  }

  void userPresenceChanged((String, UserPresence) event) {
    if (mounted) {
      setState(() {
        presence = event.$2;
      });
    }
  }
}
