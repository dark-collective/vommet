import 'dart:async';

import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_tracker.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 1077: one thread's follow state, as you set it or as it was
/// set for you. Shaped like an MSC4306 thread subscription: [automatic] is
/// the event that followed it for you (your reply, a mention), null when you
/// followed it by hand.
class ThreadFollowEntry {
  const ThreadFollowEntry({
    required this.follow,
    required this.ts,
    this.automatic,
  });

  final bool follow;

  /// When it was set, in ms since the epoch.
  final int ts;

  final String? automatic;

  static ThreadFollowEntry? parse(Object? value) {
    if (value is! Map) return null;
    final follow = value["follow"];
    final ts = value["ts"];
    if (follow is! bool || ts is! num) return null;
    final automatic = value["automatic"];
    return ThreadFollowEntry(
      follow: follow,
      ts: ts.toInt(),
      automatic: automatic is String ? automatic : null,
    );
  }

  Map<String, Object?> toJson() => {
        "follow": follow,
        "ts": ts,
        if (automatic != null) "automatic": automatic,
      };
}

/// Vommet issue 1077: the threads you follow. They drive the threads list's
/// "Following" filter, the "Threads I follow" read state and the "Only
/// threads I follow" reply notifications.
///
/// A thread without an entry is followed when you started it, replied in it
/// (the server's `current_user_participated`) or it has a thread reply rule
/// (a mention followed it before this existed). An entry wins: following or
/// unfollowing by hand, or an automatic follow by a mention. An unfollow
/// sticks until you reply in the thread again.
///
/// Saved per room in account data (`threads`: root id → entry), so it
/// follows you to every device. The spec has no followed-thread state yet;
/// MSC4306 thread subscriptions are the match, unsupported by our homeserver
/// and SDK so far.
class ThreadFollows {
  static const String type = "im.vommet.thread_follows";

  /// Entries kept per room; the oldest go first.
  static const int maxPerRoom = 300;

  /// Bumps whenever a room's follows change, here or on another device.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, StreamSubscription> _watching = {};

  /// Threads you're known to have replied in since their stored root
  /// arrived (whose `current_user_participated` is from back then): seen in
  /// the server's copy of the root, a thread list page or your own reply.
  /// Per account and room; the app session only.
  static final Map<String, Set<String>> _repliedIn = {};

  /// Most threads kept per room in [_repliedIn].
  static const int _maxRepliedIn = 1000;

  static String _roomKey(matrix.Room room) =>
      "${room.client.userID}|${room.id}";

  /// Notes that you replied in [rootId]; threads without an entry count as
  /// followed from then on, like the server's summary says.
  static void noteRepliedIn(matrix.Room room, String rootId) {
    final roots = _repliedIn.putIfAbsent(_roomKey(room), () => {});
    if (roots.length >= _maxRepliedIn && !roots.contains(rootId)) {
      roots.remove(roots.first);
    }
    // No [changed] bump: what shows it already knows (it came from there),
    // and the lists listen to [changed] and would reload for nothing.
    roots.add(rootId);
  }

  static bool _knownRepliedIn(matrix.Room room, String rootId) =>
      _repliedIn[_roomKey(room)]?.contains(rootId) == true;

  static Map<String, ThreadFollowEntry> parse(Map<String, Object?>? content) {
    final threads = content?["threads"];
    if (threads is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in threads.entries)
        if (key is String)
          if (ThreadFollowEntry.parse(value) case final entry?) key: entry,
    };
  }

  /// The room's entries; [changed] starts following other devices' edits.
  static Map<String, ThreadFollowEntry> of(matrix.Room room) {
    watch(room.client);
    return stored(room);
  }

  /// The room's entries, without watching for changes.
  static Map<String, ThreadFollowEntry> stored(matrix.Room room) =>
      parse(room.roomAccountData[type]?.content);

  static ThreadFollowEntry? entryOf(matrix.Room room, String rootId) =>
      of(room)[rootId];

  /// Whether a thread is followed, from its [entry] if any, else from
  /// whether it has a thread reply rule ([hasRule]) or you started or took
  /// part in it ([startedOrParticipated]).
  static bool decide(
    ThreadFollowEntry? entry, {
    required bool hasRule,
    required bool startedOrParticipated,
  }) =>
      entry?.follow ?? (hasRule || startedOrParticipated);

  /// Whether you follow [rootId] in [room]. [root] (the root event, when
  /// known) and [participated] (the server says you replied) feed the
  /// default for threads without an entry.
  static bool isFollowed(
    matrix.Room room,
    String rootId, {
    matrix.Event? root,
    bool participated = false,
  }) {
    final me = room.client.userID;
    return decide(
      stored(room)[rootId],
      hasRule: ThreadReplyRules.hasThread(room.client.globalPushRules, rootId),
      startedOrParticipated: participated ||
          _knownRepliedIn(room, rootId) ||
          (root != null &&
              (root.senderId == me ||
                  ThreadReadScopes.startedOrParticipated(root))),
    );
  }

  /// Whether an automatic follow by an event at [eventTs] applies over
  /// [entry]: an unfollow sticks until you reply again ([ownReply]) after it.
  static bool autoFollowApplies(
    ThreadFollowEntry? entry, {
    required bool ownReply,
    required int eventTs,
  }) =>
      entry == null || entry.follow || (ownReply && eventTs > entry.ts);

  /// [content] with [rootId] set to [entry], keeping the newest
  /// [maxPerRoom] entries.
  static Map<String, Object?> withEntry(
    Map<String, Object?>? content,
    String rootId,
    ThreadFollowEntry entry,
  ) {
    final entries = {...parse(content), rootId: entry};
    final kept = entries.entries.toList()
      ..sort((a, b) => b.value.ts.compareTo(a.value.ts));
    return {
      ...?content,
      "threads": {
        for (final e in kept.take(maxPerRoom)) e.key: e.value.toJson(),
      },
    };
  }

  /// Follows or unfollows [rootId] in [room]; [automatic] is the event that
  /// follows it for you. Also adds or removes its thread reply rule, so
  /// "Only threads I follow" notifies for it or stops.
  ///
  /// A room's writes run one after another, each on top of the last one's
  /// content, so overlapping follows don't lose each other.
  static Future<void> set(
    matrix.Room room,
    String rootId,
    bool follow, {
    String? automatic,
  }) {
    final key = "${room.client.userID}|${room.id}";
    final next = (_writes[key] ?? Future<void>.value()).then(
      (_) => _set(room, rootId, follow, automatic: automatic),
    );
    final done = next.catchError((Object _) {});
    _writes[key] = done;
    unawaited(
      done.then((_) {
        if (identical(_writes[key], done)) _writes.remove(key);
      }),
    );
    return next;
  }

  /// Each room's latest write, which never fails.
  static final Map<String, Future<void>> _writes = {};

  static Future<void> _set(
    matrix.Room room,
    String rootId,
    bool follow, {
    String? automatic,
  }) async {
    final client = room.client;
    final userId = client.userID;
    if (userId == null) return;
    final entry = ThreadFollowEntry(
      follow: follow,
      ts: DateTime.now().millisecondsSinceEpoch,
      automatic: automatic,
    );
    final before = room.roomAccountData[type];
    final content = withEntry(before?.content, rootId, entry);
    // Show it now rather than when the sync echoes it back; the next write
    // builds on it.
    final local = matrix.BasicEvent(type: type, content: content);
    room.roomAccountData[type] = local;
    changed.value++;
    try {
      await client.setAccountDataPerRoom(userId, room.id, type, content);
    } catch (_) {
      // Undo it, unless a sync replaced it meanwhile.
      if (identical(room.roomAccountData[type], local)) {
        if (before == null) {
          room.roomAccountData.remove(type);
        } else {
          room.roomAccountData[type] = before;
        }
        changed.value++;
      }
      rethrow;
    }
    final rules = client.globalPushRules;
    final put = ThreadReplyTracker.putOn(client);
    final delete = ThreadReplyTracker.deleteOn(client);
    if (follow) {
      await ThreadReplyRules.addThread(
        rules,
        room.id,
        rootId,
        put: put,
        delete: delete,
      );
    } else {
      await ThreadReplyRules.removeThread(rules, rootId, delete: delete);
    }
  }

  /// The threads followed in [byRoom] (room id → its entries), newest
  /// first. [byDefault] (room id → threads you started or took part in,
  /// with their last activity) adds the ones without an entry.
  static List<({String roomId, String rootId})> followedRoots(
    Map<String, Map<String, ThreadFollowEntry>> byRoom, {
    Map<String, List<({String rootId, int ts})>> byDefault = const {},
  }) {
    final followed = [
      for (final MapEntry(key: roomId, value: entries) in byRoom.entries)
        for (final MapEntry(key: rootId, value: entry) in entries.entries)
          if (entry.follow) (roomId: roomId, rootId: rootId, ts: entry.ts),
      for (final MapEntry(key: roomId, value: threads) in byDefault.entries)
        for (final t in threads)
          if (byRoom[roomId]?[t.rootId] == null)
            (roomId: roomId, rootId: t.rootId, ts: t.ts),
    ]..sort((a, b) => b.ts.compareTo(a.ts));
    return [for (final t in followed) (roomId: t.roomId, rootId: t.rootId)];
  }

  /// Rooms whose threads you took part in are looked up when the account
  /// switches: the most recently active ones only.
  static const int defaultLookupRooms = 20;

  /// Adds thread reply rules for the threads you follow in [roomId] (every
  /// room without its own "All threads" when null), right after its replies
  /// switched to "Only threads I follow": the ones you followed, and the
  /// ones you started or took part in (from the server's list, in [roomId]
  /// or the [defaultLookupRooms] most recently active rooms). [rules] are
  /// from before the switch.
  static Future<void> addRules(
    matrix.Client client,
    matrix.PushRuleSet? rules, {
    String? roomId,
  }) async {
    final rooms = roomId == null
        ? client.rooms
            .where(
              (r) =>
                  ThreadReplyRules.roomChoice(rules, r.id) !=
                  ThreadReplyNotify.all,
            )
            .toList()
        : [client.getRoomById(roomId)].nonNulls.toList();
    final recent = [...rooms]..sort(
        (a, b) => _lastActivity(b).compareTo(_lastActivity(a)),
      );
    final byDefault = <String, List<({String rootId, int ts})>>{};
    for (final room in recent.take(defaultLookupRooms)) {
      byDefault[room.id] = await _participatedRoots(room);
    }
    await ThreadReplyRules.addThreads(
      rules,
      followedRoots(
        {for (final room in rooms) room.id: stored(room)},
        byDefault: byDefault,
      ),
      put: ThreadReplyTracker.putOn(client),
    );
  }

  static int _lastActivity(matrix.Room room) =>
      room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;

  /// The server's first page of threads you started or took part in.
  static Future<List<({String rootId, int ts})>> _participatedRoots(
    matrix.Room room,
  ) async {
    try {
      final response = await room.client.getThreadRoots(
        room.id,
        include: matrix.Include.participated,
        limit: 50,
      );
      return [
        for (final root in response.chunk)
          (rootId: root.eventId, ts: lastActivityOf(root)),
      ];
    } catch (e, s) {
      Log.onError(e, s, content: "Could not list the threads you're in");
      return const [];
    }
  }

  /// A thread root's last reply time from its aggregation, else its own.
  static int lastActivityOf(matrix.MatrixEvent root) {
    final relations = root.unsigned?["m.relations"];
    final thread =
        relations is Map ? relations[matrix.RelationshipTypes.thread] : null;
    final latest = thread is Map ? thread["latest_event"] : null;
    final ts = latest is Map ? latest["origin_server_ts"] : null;
    return ts is num ? ts.toInt() : root.originServerTs.millisecondsSinceEpoch;
  }

  /// Makes [changed] follow other devices' edits for [client].
  static void watch(matrix.Client client) {
    if (_watching.containsKey(client)) return;
    _watching[client] = client.onSync.stream.listen((sync) {
      final rooms = sync.rooms?.join?.values ?? const [];
      if (rooms.any((r) => r.accountData?.any((e) => e.type == type) == true)) {
        changed.value++;
      }
    });
  }
}
