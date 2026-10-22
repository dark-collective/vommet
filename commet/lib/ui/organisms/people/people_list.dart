// Vommet issue 580: the list the People rail button opens in the room list
// column, like a space: a new-message pencil, "Find a person", invitations
// to direct messages, then every direct message newest first. The chosen
// DM opens in the normal chat pane.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/list_trust_marker.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/molecules/invitation_display.dart';
import 'package:commet/ui/organisms/invitation_view/invite_preview_page.dart';
import 'package:commet/ui/organisms/people/people_model.dart';
import 'package:commet/ui/organisms/people/people_strings.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PeopleList extends StatefulWidget {
  const PeopleList({
    required this.clientManager,
    this.filterClient,
    this.selectedRoom,
    this.onSelectRoom,
    this.onNewMessage,
    super.key,
  });

  final ClientManager clientManager;
  final Client? filterClient;

  /// The open chat, highlighted in the list.
  final Room? selectedRoom;
  final void Function(Room room)? onSelectRoom;

  /// The pencil: start a new direct message.
  final VoidCallback? onNewMessage;

  static const searchKey = ValueKey("PeopleSearch");

  @override
  State<PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<PeopleList> {
  final TextEditingController search = TextEditingController();
  final List<StreamSubscription> subs = [];
  final List<StreamSubscription> inviteSubs = [];
  bool refreshPending = false;

  INotifyingList<Room> get allDirectMessages =>
      widget.clientManager.directMessages.directMessageRooms;

  List<Room> visibleRooms() => PeopleModel.rooms(allDirectMessages,
      query: search.text, client: widget.filterClient);

  @override
  void initState() {
    super.initState();
    final dms = allDirectMessages;
    subs.addAll([
      dms.onAdd.listen((_) => refresh()),
      dms.onRemove.listen((_) => refresh()),
      dms.onListUpdated.listen((_) => refresh()),
      // A new message moves its DM to the top.
      widget.clientManager.directMessages.onEventReceived.stream
          .listen((_) => refresh()),
      widget.clientManager.onClientAdded.stream.listen((_) => watchInvites()),
      widget.clientManager.onClientRemoved.stream.listen((_) => watchInvites()),
    ]);
    watchInvites();
    // Vommet issues 290/499: Alt+Up/Down follow this list.
    RoomListNavigation.register(this, visibleRooms);
  }

  void watchInvites() {
    for (final sub in inviteSubs) {
      sub.cancel();
    }
    inviteSubs.clear();
    for (final client in widget.clientManager.clients) {
      final component = client.getComponent<InvitationComponent>();
      if (component == null) continue;
      inviteSubs.add(component.invitations.onListUpdated.listen((_) {
        refresh();
      }));
    }
    refresh();
  }

  /// One rebuild per burst (each sync reports every DM it touched).
  void refresh() {
    if (refreshPending) return;
    refreshPending = true;
    scheduleMicrotask(() {
      refreshPending = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    RoomListNavigation.unregister(this);
    for (final sub in [...subs, ...inviteSubs]) {
      sub.cancel();
    }
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      // Right-click (press and hold) for the direct messages guide.
      GuideArea(guide: Guides.directMessages, child: buildList(context));

  Widget buildList(BuildContext context) {
    final rooms = visibleRooms();
    final invites = PeopleModel.directInvitations(widget.clientManager.clients,
        client: widget.filterClient);
    final query = search.text.trim();

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: header(context)),
      SliverToBoxAdapter(child: searchField(context)),
      if (invites.isNotEmpty && query.isEmpty) ...[
        SliverToBoxAdapter(
            child: sectionLabel(
                PeopleStrings.peopleInvitesHeader(invites.length))),
        SliverList.builder(
          itemCount: invites.length,
          itemBuilder: (context, i) => inviteRow(context, invites[i]),
        ),
      ],
      SliverToBoxAdapter(
          child: sectionLabel(
              PeopleStrings.peopleDirectMessagesHeader(rooms.length))),
      if (rooms.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: tiamat.Text.labelLow(query.isEmpty
                ? PeopleStrings.peopleListEmpty
                : PeopleStrings.peopleSearchNoResults(query)),
          ),
        )
      else
        SliverList.builder(
          itemCount: rooms.length,
          itemBuilder: (context, i) {
            final room = rooms[i];
            return PeopleRow(
              room,
              key: ValueKey("PeopleList-${room.localId}"),
              selected: room == widget.selectedRoom,
              onTap: () => widget.onSelectRoom?.call(room),
            );
          },
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ]);
  }

  Widget header(BuildContext context) {
    // Vommet issue 456: the room list's collapse button, on desktop.
    final collapse = RoomListHeaderAction.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(children: [
        Expanded(
          child: Text(PeopleStrings.labelPeople,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        tiamat.Tooltip(
          text: PeopleStrings.promptPeopleNewMessage,
          child: tiamat.IconButton(
            icon: Icons.edit_square,
            size: 20,
            onPressed: widget.onNewMessage,
          ),
        ),
        if (collapse != null) collapse,
      ]),
    );
  }

  Widget searchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
      child: SizedBox(
        height: 36,
        child: TextField(
          key: PeopleList.searchKey,
          controller: search,
          onChanged: (_) => setState(() {}),
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: PeopleStrings.peopleSearchHint,
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: PeopleStrings.peopleSearchClear,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(search.clear)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: tiamat.Text.labelLow(text),
      );

  Widget inviteRow(
      BuildContext context, (InvitationComponent, Invitation) entry) {
    final (component, invite) = entry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
      child: InvitationDisplay(
        invite,
        key: ValueKey("PeopleInvite-${invite.roomId}"),
        acceptInvitation: component.acceptInvitation,
        rejectInvitation: component.rejectInvitation,
        // Tap to see the invite before accepting, as on Home.
        onTap: (invitation) => InvitePreviewPage.open(context,
            component: component, invitation: invitation),
      ),
    );
  }
}

/// One direct message in the People list: picture with the person's
/// presence (two pictures for a group), name, last message, time and unread
/// count; name and message are bold while it's unread.
class PeopleRow extends StatefulWidget {
  const PeopleRow(this.room, {this.selected = false, this.onTap, super.key});

  final Room room;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<PeopleRow> createState() => _PeopleRowState();
}

class _PeopleRowState extends State<PeopleRow> {
  final List<StreamSubscription> subs = [];
  String? partner;
  UserPresence? presence;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    subs.add(room.onUpdate.listen((_) {
      if (mounted) setState(() {});
    }));

    partner = room.client
        .getComponent<DirectMessagesComponent>()
        ?.getDirectMessagePartnerId(room);
    final presenceComponent = room.client.getComponent<UserPresenceComponent>();
    final id = partner;
    if (id == null || presenceComponent == null) return;

    presenceComponent.getUserPresence(id).then((p) {
      if (mounted) setState(() => presence = p);
    });
    subs.add(presenceComponent.onPresenceChanged
        .where((e) => e.$1 == id)
        .listen((e) {
      if (mounted) setState(() => presence = e.$2);
    }));
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  String? get sender {
    final id = room.lastMessage?.senderId;
    if (id == null) return null;
    if (id == room.client.self?.identifier) return "You";
    if (partner != null && !PeopleModel.isGroup(room)) return null;
    return room.getMemberOrFallback(id).displayName;
  }

  @override
  Widget build(BuildContext context) {
    final redaction = RedactionScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unread = room.notificationCount > 0 || roomHasUnread(room);
    final timestamp = room.lastEventTimestamp;
    final time = timestamp.millisecondsSinceEpoch == 0
        ? null
        : formatChatTime(timestamp, DateTime.now(),
            use24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
            yesterday: PeopleStrings.peopleYesterday);
    final body = room.lastMessage?.plainTextBody;
    final who = sender;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    final color = unread ? scheme.onSurface : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
      child: AdaptiveContextMenu(
        items: RoomTextButton.createRoomContextMenuItems(context, room),
        child: Material(
          color: widget.selected
              ? scheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
              child: Row(children: [
                picture(context),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(redaction.roomDisplayName(room),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: scheme.onSurface)),
                        ),
                        // Amber/red DM marker after the name (Vommet issue 131).
                        if (partner != null) ListTrustMarker(room),
                        const Spacer(),
                        if (time != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(time,
                                style: textTheme.labelSmall?.copyWith(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant)),
                          ),
                      ]),
                      Row(children: [
                        Expanded(
                          child: Text(
                              [
                                if (who != null) "$who:",
                                if (body != null)
                                  redaction.text(body.replaceAll("\n", " ")),
                              ].join(" "),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall
                                  ?.copyWith(fontWeight: weight, color: color)),
                        ),
                        if (room.notificationCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: NotificationBadge(room.notificationCount),
                          )
                        else if (unread)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: DotIndicator(),
                          ),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static const double _size = 40;

  Widget picture(BuildContext context) {
    final redaction = RedactionScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final others = PeopleModel.groupMemberIds(room);

    Widget avatar;
    if (others.length > 1) {
      // A group DM: two people, overlapping.
      final a = room.getMemberOrFallback(others[0]);
      final b = room.getMemberOrFallback(others[1]);
      avatar = SizedBox(
        width: _size,
        height: _size,
        child: Stack(children: [
          Positioned(
            left: 0,
            top: 0,
            child: tiamat.Avatar(
                radius: _size * 0.3,
                image: a.avatar,
                placeholderText: redaction.name(a.displayName, a.identifier),
                placeholderColor: a.defaultColor),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainer, shape: BoxShape.circle),
              child: tiamat.Avatar(
                  radius: _size * 0.3,
                  image: b.avatar,
                  placeholderText: redaction.name(b.displayName, b.identifier),
                  placeholderColor: b.defaultColor),
            ),
          ),
        ]),
      );
    } else {
      avatar = tiamat.Avatar(
          radius: _size / 2,
          image: room.avatar,
          placeholderText: redaction.roomDisplayName(room),
          placeholderColor: room.defaultColor);
    }

    final dot = presence?.status.getColor();
    if (dot == null || others.length > 1) return avatar;
    return Stack(clipBehavior: Clip.none, children: [
      avatar,
      Positioned(
        right: -1,
        bottom: -1,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surfaceContainer, width: 2.5),
          ),
        ),
      ),
    ]);
  }
}
