import 'package:commet/utils/unread_index.dart';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/ui/molecules/dm_chats_picker.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notification_debug.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 949: reads what every badge shows, per room, from the app's
/// own badge code (see notification_debug.dart). [main] gives New Home's
/// side list (which rooms its Direct messages section shows) and the
/// account filter; without it, every account and the newest room per person.
DebugSnapshot collectNotificationDebug(ClientManager manager,
    {MainPageState? main}) {
  final filter = main?.filterClient;
  final clients =
      manager.clients.where((c) => filter == null || c == filter).toList();

  // New Home's Direct messages section, as the side list shows it.
  final dmSection = <Room>{};
  final otherSections = <Room>{};
  if (main != null) {
    for (final (section, rooms) in newHomeSideList(main)) {
      if (section.type == HomeSection.directMessages) {
        dmSection.addAll(rooms);
      } else {
        otherSections.addAll(rooms);
      }
    }
  } else {
    for (final room in manager.directMessages.directMessageRooms) {
      if (!hiddenFromNewHome(room)) dmSection.add(room);
    }
  }

  final feed = NotificationsFeed.of(manager, filter);
  final cardLoaded = !feed.loading;
  final rooms = <DebugRoom>[];
  final spaces = <DebugSpace>[];
  for (final client in clients) {
    final dms = client.getComponent<DirectMessagesComponent>();
    final shown = NotificationUtils.shownSpaceRooms(client.spaces);
    final topLevel = client.spaces.where((s) => s.isTopLevel).toList();
    for (final space in topLevel) {
      spaces.add(DebugSpace(space.localId,
          badge: space.badgeCount, dot: spaceHasUnread(space)));
    }
    for (final room in client.rooms) {
      if (isStickerRoom(room) || isSupersededRoom(room)) continue;
      final isDm = dms?.isRoomDirectMessage(room) ?? false;
      // A person's older rooms fold into their newest one.
      if (isDm && dms!.isOlderDirectMessage(room)) continue;
      final inAnySpace =
          client.spaces.any((space) => space.containsRoom(room.identifier));
      final group = isDm ? DmChats.of(room) : const <Room>[];
      final older = group.where((r) => r != room);
      // As NotificationUtils.getNotificationCounts counts chats.
      bool counted(Room r) =>
          NotificationUtils.badgeShown(
              isDirectMessage: isDm,
              superseded: isSupersededRoom(r),
              inAnySpace: client.spaces
                  .any((space) => space.containsRoom(r.identifier)),
              inShownSpace: shown.contains(r.localId)) &&
          (UnreadIndex.rowOf(r).badge > 0);
      final trayChat = counted(room);
      final read = room is MatrixRoom ? _readState(room) : null;
      final server = room is MatrixRoom ? room.matrixRoom.highlightCount : 0;
      final state = UnreadIndex.rowOf(room);
      final unread = state.unread;
      rooms.add(DebugRoom(
        kind: isDm
            ? DebugRoomKind.dm
            : inAnySpace
                ? DebugRoomKind.inSpace
                : DebugRoomKind.outside,
        rule: room.pushRule,
        favourite: room.isFavorite,
        lowPriority: room is MatrixRoom &&
            room.matrixRoom.tags[matrix.TagType.lowPriority] != null,
        groupSize: group.isEmpty ? 1 : group.length,
        olderGroupCount:
            older.fold(0, (s, r) => s + UnreadIndex.roomOf(r).badge),
        spaceBadges: {
          for (final space in topLevel)
            space.localId: UnreadIndex.of(client)
                .sum((group.isEmpty ? [room] : group).where((r) => space
                    .roomsWithChildren
                    .any((child) => child.localId == r.localId)))
                .badge,
        },
        spaces: [
          for (final space in topLevel)
            if (space.roomsWithChildren.any((r) =>
                (group.isEmpty ? [room] : group)
                    .any((member) => member.localId == r.localId)))
              space.localId,
        ],
        // Underlying SDK facts remain raw; surface values below use the index.
        count: room.notificationCount,
        serverHighlights: server,
        localHighlights:
            (room.highlightedNotificationCount - server).clamp(0, 1 << 30),
        markedUnread: room is MatrixRoom && room.matrixRoom.markedUnread,
        receipt: read?.receipt ?? DebugReceipt.none,
        receiptThread: read?.thread ?? DebugReceiptThread.unthreaded,
        receiptOnNewest: read?.onNewest ?? false,
        newestIsOwn: read?.newestIsOwn ?? false,
        fullyReadOnNewest: read?.fullyRead ?? false,
        readEvidence: read?.evidence,
        threadScope: room is MatrixRoom
            ? ThreadReadScopes.scopeFor(room.matrixRoom)
            : null,
        badge: state.badge,
        badgeNoisy: state.noisy,
        dot: state.activity,
        rowDot: isDm && state.activity,
        railIcon: isDm ? state.badge : 0,
        homeAdds: isDm ? state.badge : 0,
        inDmSection: isDm && dmSection.contains(room),
        inOtherSection: isDm && otherSections.contains(room),
        trayChat: trayChat,
        olderTrayChats: 0,
        unreadCard: unread && !hiddenFromNewHome(room),
        cardUnread: feed.entries
            .where((e) =>
                !e.read &&
                (group.isEmpty ? [room] : group)
                    .any((r) => r.identifier == e.roomId) &&
                e.clientId == client.identifier)
            .length,
      ));
    }
  }

  final invites = clients.fold(
      0,
      (s, c) =>
          s + (c.getComponent<InvitationComponent>()?.invitations.length ?? 0));
  final dmCounts = manager.homeUnread(filter: filter) - invites;
  final rows = rooms.where((r) => r.inDmSection);
  final single = {
    for (final r in manager.singleRooms(filterClient: filter)) r.localId: r
  }.values;
  final sliding = clients
      .map((c) => c is MatrixClient ? c.matrixClient : null)
      .nonNulls
      .where((c) => c.slidingSync);
  return DebugSnapshot(
    rooms: rooms,
    spaces: spaces,
    totals: DebugTotals(
      home: invites + (homeBadgeCountsDms.value ? dmCounts : 0),
      homeInvites: invites,
      homeCountsDms: homeBadgeCountsDms.value,
      people: manager.homeUnread(
          filter: filter, countDms: homeBadgeCountsDms.value),
      peopleInvites: invites,
      otherDmSections: rooms
          .where((r) => r.isDm && r.inOtherSection)
          .fold(0, (s, r) => s + r.badge),
      dmHeader: rows.fold(0, (s, r) => s + r.badge),
      dmRows: rows.length,
      roomsRail: UnreadTotals.rooms(
          single.map((r) => (r.localId, UnreadIndex.roomOf(r)))).badge,
      roomsRailDots: single.where((r) => UnreadIndex.roomOf(r).unread).length,
      trayChats: NotificationUtils.getNotificationCounts().$2,
      trayOtherAccounts: filter == null
          ? 0
          : NotificationUtils.getNotificationCounts().$2 -
              NotificationUtils.getNotificationCounts(filter: filter).$2,
      unreadCard: rooms.where((r) => r.unreadCard).length,
      cardLoaded: cardLoaded,
      cardUnread: feed.entries.where((e) => !e.read).length,
      cardEarlier: feed.entries.where((e) => e.read).length,
    ),
    build: BuildConfig.VERSION_TAG,
    // dart:io's Platform throws on web (the dialog drew a gray box).
    platform: kIsWeb ? "web" : Platform.operatingSystem,
    layout: switch (currentLayoutStyle) {
      LayoutStyle.discord => "Discord",
      LayoutStyle.telegram => "Telegram",
      LayoutStyle.custom => "Custom mix",
    },
    accounts: clients.length,
    countSource: sliding.isEmpty
        ? DebugCountSource.classicSync
        : sliding.every(
                (c) => c.slidingSyncController.unreadCounts.serverCountsTrusted)
            ? DebugCountSource.slidingTrusted
            : DebugCountSource.slidingLocal,
  );
}

typedef _Read = ({
  DebugReceipt receipt,
  DebugReceiptThread thread,
  bool onNewest,
  bool newestIsOwn,
  bool fullyRead,
  DebugReadEvidence evidence,
});

/// The same activity candidate and receipt evidence as the production model,
/// reduced to privacy-safe flags before it enters the dump's data model.
DebugReadEvidence notificationReadEvidence(MatrixRoom wrapper) {
  final room = wrapper.matrixRoom;
  final newest = room.lastEvent;
  final visible = unreadActivityEvent(wrapper)?.event;
  final order = unreadOrder(room);
  return DebugReadEvidence(
    hasVisibleEvent: visible != null,
    visibleInOrder: visible != null && order.contains(visible.eventId),
    visibleDiffersFromNewest:
        visible != null && visible.eventId != newest?.eventId,
    localReceipt: visible != null && hasLocalOwnReceipt(room, visible),
    newestCoverage: newest == null
        ? null
        : receiptCoverage(newest.eventId, ownReceiptIds(room, newest), order),
    visibleCoverage: visible == null
        ? null
        : receiptCoverage(visible.eventId, ownReceiptIds(room, visible), order),
    fullyReadCoverage: visible == null
        ? null
        : receiptCoverage(visible.eventId,
            [if (room.fullyRead.isNotEmpty) room.fullyRead], order),
  );
}

/// One applicable own receipt for context. Known position wins over its
/// timestamp; unknown coverage remains unknown instead of claiming "behind".
_Read _readState(MatrixRoom wrapper) {
  final room = wrapper.matrixRoom;
  final newest = room.lastEvent;
  final state = room.receiptState;
  final root = newest?.relationshipType == matrix.RelationshipTypes.thread
      ? newest?.relationshipEventId
      : null;
  final candidates = [
    (
      state.global.ownPublic,
      DebugReceipt.public,
      DebugReceiptThread.unthreaded
    ),
    (
      state.global.ownPrivate,
      DebugReceipt.private,
      DebugReceiptThread.unthreaded
    ),
    if (root == null) ...[
      (
        state.mainThread?.ownPublic,
        DebugReceipt.public,
        DebugReceiptThread.main
      ),
      (
        state.mainThread?.ownPrivate,
        DebugReceipt.private,
        DebugReceiptThread.main
      ),
    ],
    if (root != null) ...[
      (
        state.byThread[root]?.ownPublic,
        DebugReceipt.public,
        DebugReceiptThread.thread
      ),
      (
        state.byThread[root]?.ownPrivate,
        DebugReceipt.private,
        DebugReceiptThread.thread
      ),
    ],
  ];
  var receipt = DebugReceipt.none;
  var thread = DebugReceiptThread.unthreaded;
  var bestPosition = 1 << 30;
  var found = false;
  final order = unreadOrder(room);
  for (final (data, kind, where) in candidates) {
    if (data == null) continue;
    final at =
        data.eventId == newest?.eventId ? -1 : order.indexOf(data.eventId);
    final position = at < 0 && data.eventId != newest?.eventId ? 1 << 30 : at;
    if (found && position >= bestPosition) continue;
    found = true;
    bestPosition = position;
    receipt = kind;
    thread = where;
  }
  return (
    receipt: receipt,
    thread: thread,
    onNewest: newest != null && readByOwnReceipts(room, newest),
    newestIsOwn: newest != null && newest.senderId == room.client.userID,
    fullyRead: newest != null && room.fullyRead == newest.eventId,
    evidence: notificationReadEvidence(wrapper),
  );
}
