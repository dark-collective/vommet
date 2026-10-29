import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_notifications_model.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issues 814, 841 and 873: the last week of notifications for one
/// account filter, shared by the New Home Notifications card, the bell's
/// count and the bell's pop-over, so reading something in one shows in the
/// others. It loads while anything listens and reloads when a sync changes
/// the rooms' notification counts.
///
/// The list comes from the homeserver (`GET /notifications`, which knows
/// what was read). Where that fails, or misses a room that has unread
/// notifications (Synapse drops ordinary ones after about a day), the
/// room's newest message is checked against the push rules here.
class NotificationsFeed extends ChangeNotifier {
  NotificationsFeed._(this.clientManager, this.filterClient);

  static final Map<String, NotificationsFeed> _feeds = {};

  /// The feed for [manager]'s accounts, or only [filterClient]'s.
  static NotificationsFeed of(ClientManager manager, Client? filterClient) =>
      _feeds.putIfAbsent(
          "${identityHashCode(manager)}/${filterClient?.identifier ?? "*"}",
          () => NotificationsFeed._(manager, filterClient));

  final ClientManager clientManager;
  final Client? filterClient;

  StreamSubscription? syncSub;
  Timer? pending;
  DateTime? lastFetch;
  String signature = "";
  bool loading = true;
  List<NotificationEntry> entries = const [];
  int generation = 0;
  int _listening = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_listening++ == 0) _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (_listening > 0 && --_listening == 0) _stop();
  }

  void _start() {
    syncSub = clientManager.onSync.stream.listen((_) => changed());
    signature = countsSignature();
    final since =
        lastFetch == null ? null : DateTime.now().difference(lastFetch!);
    if (since == null || since >= minInterval) {
      load();
    } else {
      pending = Timer(minInterval - since, load);
    }
  }

  void _stop() {
    syncSub?.cancel();
    syncSub = null;
    pending?.cancel();
  }

  /// The entries as the list shows them (see [arrangeNotifications]).
  NotificationsList arranged({bool hideRead = false}) =>
      arrangeNotifications(entries,
          now: DateTime.now(), oneEntry: oneEntry, hideRead: hideRead);

  /// How many unread items the list has: the bell's count.
  int get unreadCount => arranged(hideRead: true).unread.length;

  /// Clients whose homeserver didn't answer `/notifications` this session.
  static final Set<String> unsupported = {};

  /// The pages read per account, 50 notifications each.
  static const int maxPages = 4;

  /// The fewest seconds between two homeserver fetches.
  static const Duration minInterval = Duration(seconds: 5);

  Iterable<MatrixClient> get clients => clientManager.clients
      .whereType<MatrixClient>()
      .where((c) => filterClient == null || c == filterClient);

  bool shows(Room room) =>
      !hiddenFromNewHome(room) && room.pushRule != PushRule.dontNotify;

  /// The rooms' notification counts: a sync that changes them (a new
  /// notification, or something read here or elsewhere) reloads the list.
  String countsSignature() {
    final parts = <String>[];
    for (final client in clients) {
      for (final room in client.rooms) {
        final n = room.notificationCount + room.highlightedNotificationCount;
        if (n > 0) parts.add("${room.localId}=$n");
      }
    }
    parts.sort();
    return parts.join(",");
  }

  void changed() {
    final next = countsSignature();
    if (next == signature) return;
    signature = next;
    if (pending?.isActive ?? false) return;
    final since =
        lastFetch == null ? minInterval : DateTime.now().difference(lastFetch!);
    final wait = since >= minInterval
        ? const Duration(milliseconds: 800)
        : minInterval - since;
    pending = Timer(wait, load);
  }

  Future<void> load() async {
    final gen = ++generation;
    lastFetch = DateTime.now();
    final all = <NotificationEntry>[];
    for (final client in clients.toList()) {
      try {
        all.addAll(await _entriesOf(client));
      } catch (e, s) {
        matrix.Logs().w("[New Home] Notifications card failed", e, s);
      }
    }
    if (gen != generation) return;
    entries = all;
    loading = false;
    notifyListeners();
  }

  Future<List<NotificationEntry>> _entriesOf(MatrixClient client) async {
    final result = <NotificationEntry>[];
    final fromServer = unsupported.contains(client.identifier)
        ? null
        : await _fromServer(client);
    if (fromServer != null) result.addAll(fromServer);
    // Rooms with unread notifications the list doesn't have (or every room,
    // when the homeserver has no list): their newest message, if it
    // notifies.
    final unreadRooms = {
      for (final e in result)
        if (!e.read) e.roomId
    };
    final now = DateTime.now();
    for (final room in client.rooms.whereType<MatrixRoom>()) {
      if (!shows(room) || unreadRooms.contains(room.identifier)) continue;
      final unread =
          room.notificationCount > 0 || room.highlightedNotificationCount > 0;
      if (!unread && fromServer != null) continue;
      final event = room.matrixRoom.lastEvent;
      if (event == null ||
          now.difference(event.originServerTs) > notificationsWindow) {
        continue;
      }
      final entry = await _entryOf(client, room, event,
          read: !unread,
          count: room.notificationCount,
          actions: client.matrixClient.pushruleEvaluator.match(event));
      if (entry != null) result.add(entry);
    }
    return result;
  }

  /// The homeserver's notifications of the last week, or null when it
  /// failed (a homeserver without the endpoint isn't asked again).
  Future<List<NotificationEntry>?> _fromServer(MatrixClient client) async {
    final mx = client.matrixClient;
    final since = DateTime.now().subtract(notificationsWindow);
    final result = <NotificationEntry>[];
    String? from;
    try {
      for (var page = 0; page < maxPages; page++) {
        final response = await mx.getNotifications(from: from, limit: 50);
        var older = false;
        for (final n in response.notifications) {
          final time = DateTime.fromMillisecondsSinceEpoch(n.ts);
          if (time.isBefore(since)) {
            older = true;
            continue;
          }
          final room = client.getRoom(n.roomId);
          if (room is! MatrixRoom || !shows(room)) continue;
          final event = matrix.Event.fromMatrixEvent(n.event, room.matrixRoom);
          // The server's flag can lag behind a read receipt sent from here.
          final roomRead = room.notificationCount == 0 &&
              room.highlightedNotificationCount == 0;
          final entry = await _entryOf(client, room, event,
              read: n.read || roomRead,
              time: time,
              highlight: _highlights(n.actions));
          if (entry != null) result.add(entry);
        }
        from = response.nextToken;
        if (older || from == null || response.notifications.isEmpty) break;
      }
    } on matrix.MatrixException catch (e) {
      final status = e.response?.statusCode;
      if (e.errcode == "M_UNRECOGNIZED" || status == 404 || status == 405) {
        unsupported.add(client.identifier);
      }
      matrix.Logs().i("[New Home] /notifications unavailable: ${e.errcode}");
      return null;
    } catch (e) {
      matrix.Logs().i("[New Home] /notifications failed: $e");
      return result.isEmpty ? null : result;
    }
    return result;
  }

  static bool _highlights(List<Object?> actions) => actions.any((a) =>
      a is Map &&
      a["set_tweak"] == "highlight" &&
      (a["value"] == null || a["value"] == true));

  Future<NotificationEntry?> _entryOf(
      MatrixClient client, MatrixRoom room, matrix.Event event,
      {required bool read,
      DateTime? time,
      bool? highlight,
      int count = 1,
      matrix.EvaluatedPushRuleAction? actions}) async {
    if (actions != null && !actions.notify) return null;
    if (event.senderId == client.matrixClient.userID) return null;
    var shown = event;
    if (event.type == matrix.EventTypes.Encrypted) {
      try {
        shown = await client.matrixClient.encryption?.decryptRoomEvent(event) ??
            event;
      } catch (_) {}
    }
    final preview = notificationPreview(shown.type, shown.content,
        spoiler: MediaSpoiler.isSpoiler(shown.content));
    if (preview == null) return null;
    return NotificationEntry(
        clientId: client.identifier,
        roomId: room.identifier,
        eventId: event.eventId,
        senderId: event.senderId,
        time: time ?? event.originServerTs,
        read: read,
        highlight: highlight ?? actions?.highlight ?? false,
        threadId: shown.relationshipType == matrix.RelationshipTypes.thread
            ? shown.relationshipEventId
            : null,
        preview: preview,
        count: count < 1 ? 1 : count);
  }

  /// DMs and rooms set to every message get one entry.
  bool oneEntry(String roomKey) {
    final i = roomKey.indexOf("/");
    final clientId = roomKey.substring(0, i);
    final room = clientManager.clients
        .where((c) => c.identifier == clientId)
        .firstOrNull
        ?.getRoom(roomKey.substring(i + 1));
    if (room == null) return false;
    return isDirectRoom(room) || room.pushRule == PushRule.notify;
  }

  Room? roomOf(NotificationEntry e) => clientManager.clients
      .where((c) => c.identifier == e.clientId)
      .firstOrNull
      ?.getRoom(e.roomId);
}

bool isDirectRoom(Room room) =>
    room.client
        .getComponent<DirectMessagesComponent>()
        ?.isRoomDirectMessage(room) ==
    true;
