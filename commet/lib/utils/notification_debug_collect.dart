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
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notification_debug.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/vommet_unread.dart';
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
  if (main != null) {
    for (final (section, rooms) in newHomeSideList(main)) {
      if (section.type == HomeSection.directMessages) dmSection.addAll(rooms);
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
          (r.displayNotificationCount > 0 ||
              r.displayHighlightedNotificationCount > 0);
      final trayChat = counted(room);
      final read = room is MatrixRoom ? _readState(room.matrixRoom) : null;
      final server = room is MatrixRoom ? room.matrixRoom.highlightCount : 0;
      final unread = roomHasUnread(room);
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
        olderGroupCount: older.fold(0, (s, r) => s + r.notificationCount),
        spaces: [
          for (final space in topLevel)
            if (space.roomsWithChildren.any((r) => r.localId == room.localId))
              space.localId,
        ],
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
        threadScope: room is MatrixRoom
            ? ThreadReadScopes.scopeFor(room.matrixRoom)
            : null,
        badge: room.badgeCount,
        badgeNoisy: room.badgeNoisy,
        dot: unread,
        rowDot: isDm && (unread || group.any(roomHasUnread)),
        // As SideNavigationBarDirectMessages.unreadWith adds them up.
        railIcon: !isDm
            ? 0
            : group.length < 2
                ? room.notificationCount
                : group.fold(0, (s, r) => s + r.notificationCount),
        // Home and People add up every room's raw count (Vommet issue 99:
        // older ones too).
        homeAdds: !isDm
            ? 0
            : room.notificationCount +
                older.fold(0, (s, r) => s + r.notificationCount),
        inDmSection: isDm && dmSection.contains(room),
        trayChat: trayChat,
        olderTrayChats:
            older.where((r) => !isStickerRoom(r)).where(counted).length,
        unreadCard: unread && !hiddenFromNewHome(room),
        cardUnread: feed.entries
            .where((e) =>
                !e.read &&
                e.roomId == room.identifier &&
                e.clientId == client.identifier)
            .length,
      ));
    }
  }

  final invites = clients.fold(
      0,
      (s, c) =>
          s + (c.getComponent<InvitationComponent>()?.invitations.length ?? 0));
  final dmCounts = manager.directMessages.highlightedRoomsList
      .where((r) => filter == null || r.client == filter)
      .fold(0, (s, r) => s + r.notificationCount);
  final rows = rooms.where((r) => r.inDmSection);
  final single = manager.singleRooms(filterClient: filter);
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
      people: NewHomeInvites.instance.badge.value,
      peopleInvites: NewHomeInvites.instance.count.value,
      dmHeader: rows.fold(0, (s, r) => s + r.badge),
      dmRows: rows.length,
      roomsRail: single.fold(0, (s, r) => s + r.badgeCount),
      roomsRailDots: single.where(roomHasUnread).length,
      trayChats: NotificationUtils.getNotificationCounts().$2,
      unreadCard: rooms.where((r) => r.unreadCard).length,
      cardLoaded: cardLoaded,
      cardUnread: feed.entries.where((e) => !e.read).length,
      cardEarlier: feed.entries.where((e) => e.read).length,
    ),
    build: BuildConfig.VERSION_TAG,
    platform: Platform.operatingSystem,
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
});

/// The account's newest own read receipt in [room], and whether it covers
/// the newest event. Event ids are compared, never kept.
_Read _readState(matrix.Room room) {
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
    (state.mainThread?.ownPublic, DebugReceipt.public, DebugReceiptThread.main),
    (
      state.mainThread?.ownPrivate,
      DebugReceipt.private,
      DebugReceiptThread.main
    ),
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
  var ts = -1;
  for (final (data, kind, where) in candidates) {
    if (data == null || data.ts <= ts) continue;
    ts = data.ts;
    receipt = kind;
    thread = where;
  }
  return (
    receipt: receipt,
    thread: thread,
    onNewest: newest != null && readByOwnReceipts(room, newest),
    newestIsOwn: newest != null && newest.senderId == room.client.userID,
    fullyRead: newest != null && room.fullyRead == newest.eventId,
  );
}
