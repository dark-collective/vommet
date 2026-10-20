import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/room_avatar_badge.dart';
import 'package:commet/ui/atoms/list_trust_marker.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';

class RoomPanel extends StatefulWidget {
  const RoomPanel(this.room,
      {this.onTap, super.key, this.shouldShowAvatarForRoom});

  final Room room;
  final Function()? onTap;

  @override
  State<RoomPanel> createState() => _RoomPanelState();

  final bool Function(Room room)? shouldShowAvatarForRoom;
}

class _RoomPanelState extends State<RoomPanel> {
  late List<StreamSubscription> subs;
  String? directMessagePartner;
  UserPresence? presence = null;
  List<Member> typingUsers = [];

  @override
  void initState() {
    subs = List.empty(growable: true);
    subs.add(widget.room.onUpdate.listen((_) => setState(() {})));

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

      presenceComponent
          .getUserPresence(directMessagePartner!)
          .then((s) => setState(() {
                presence = s;
              }));

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
      items: RoomTextButton.createRoomContextMenuItems(context, widget.room),
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
        nameTrailing: isDm ? ListTrustMarker(widget.room) : null,
        userPresence: presence,
        recentEventSender: eventSender,
        recentEventSenderColor: eventSenderId != null
            ? redaction.nameColor(
                widget.room.getColorOfUser(eventSenderId), eventSenderId)
            : null,
        body: widget.room.lastMessage == null
            ? null
            : redaction.text(widget.room.lastMessage!.plainTextBody),
        // Vommet: the dot follows Discord's unread rule (muted: no dot)
        notificationCount: roomHasUnread(widget.room) ? 1 : 0,
        typingMembers: typingUsers,
        highlightNotificationCount:
            widget.room.displayHighlightedNotificationCount,
        avatarBadge: roomAvatarBadge(widget.room),
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
