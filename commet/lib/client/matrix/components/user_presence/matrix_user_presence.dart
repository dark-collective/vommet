import 'dart:async';

import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/user_presence/user_presence_lifecycle_watcher.dart';
import 'package:commet/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:commet/client/matrix/components/typing_indicators/matrix_typing_indicators_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/in_memory_cache.dart';
import 'package:matrix/matrix.dart';

class MatrixUserPresenceComponent
    implements UserPresenceComponent<MatrixClient> {
  @override
  MatrixClient client;

  StreamController<(String, UserPresence)> _controller =
      StreamController.broadcast();

  late InMemoryCache<DateTime> lastSeen;

  MatrixUserPresenceComponent(this.client) {
    client.matrixClient.onPresenceChanged.stream.listen(changed);

    client.matrixClient.onSync.stream.listen(onSync);
    lastSeen = InMemoryCache(
        maxRetention: Duration(minutes: 2),
        pollFrequency: Duration(seconds: 100));
    lastSeen.onRemove.listen(onLastSeenRemoved);

    _applySyncPresence();
    preferences.experimentQuickProfileControls.onChanged
        .listen((_) => _applySyncPresence());

    UserPresenceLifecycleWatcher().init();
  }

  @override
  bool get usePublicReadReceipts {
    var publicReadReceipts = client
        .matrixClient
        .accountData[MatrixReadReceiptComponent.publicReadReceiptsKey]
        ?.content["enabled"];
    return publicReadReceipts is bool ? publicReadReceipts : true;
  }

  @override
  Future<void> setUsePublicReadReceipts(bool value) async {
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      MatrixReadReceiptComponent.publicReadReceiptsKey,
      {"enabled": value},
    );
    client.matrixClient.receiptsPublicByDefault = value;
  }

  @override
  bool get typingIndicatorEnabled {
    var publicTypingIndicator = client
        .matrixClient
        .accountData[MatrixTypingIndicatorsComponent.publicTypingIndicatorKey]
        ?.content["enabled"];
    return publicTypingIndicator is bool ? publicTypingIndicator : true;
  }

  @override
  Future<void> setTypingIndicatorEnabled(bool value) async =>
      await client.matrixClient.setAccountData(
        client.matrixClient.userID!,
        MatrixTypingIndicatorsComponent.publicTypingIndicatorKey,
        {"enabled": value},
      );

  @override
  Future<UserPresence> getUserPresence(String userId) async {
    final presence = await client.matrixClient.fetchCurrentPresence(userId);
    _learnServer(presence);
    return _recentlyActive(userId, presence) ?? convertPresence(presence);
  }

  @override
  UserPresence? cachedPresence(String userId) {
    // The SDK's in-memory presence cache (filled by sync): the member list
    // sorts hundreds of members per frame and can't await
    // fetchCurrentPresence for each.
    // ignore: deprecated_member_use
    final presence = client.matrixClient.presences[userId];
    _learnServer(presence);
    final recent = _recentlyActive(userId, presence);
    if (recent != null || presence == null) return recent;
    return convertPresence(presence);
  }

  /// Online if the server tells us nothing better than "offline" (or nothing
  /// at all) but the user sent something in the last two minutes. Vommet:
  /// shared by the member list's sections and the presence dot, which used
  /// different rules, so someone talking could sit under "Offline" with a
  /// green dot.
  UserPresence? _recentlyActive(String userId, CachedPresence? presence) {
    if (!_onlyKnownOffline(presence)) return null;
    final seen = lastSeen.get(userId);
    if (seen != null && DateTime.now().difference(seen).inSeconds < 120) {
      return UserPresence(UserPresenceStatus.online);
    }
    return null;
  }

  /// Whether the server says no more than "offline": no status message and
  /// no last-active time (or no presence at all).
  bool _onlyKnownOffline(CachedPresence? presence) =>
      presence == null ||
      (presence.presence == PresenceType.offline &&
          presence.statusMsg == null &&
          presence.lastActiveTimestamp == null);

  /// Vommet: homeservers that have shown real presence this session (someone
  /// online, idle, with a status or a last-active time). A server with
  /// presence turned off answers "offline" for everyone, so its "offline"
  /// means "unknown" until it shows otherwise. In memory only, so a server
  /// that turns presence on is believed as soon as it shows it.
  final Set<String> _presenceServers = {};

  static String _serverOf(String userId) =>
      userId.substring(userId.indexOf(':') + 1);

  void _learnServer(CachedPresence? presence) {
    if (presence == null || _onlyKnownOffline(presence)) return;
    final server = _serverOf(presence.userid);
    if (!_presenceServers.add(server)) return;
    // Its people shown as unknown so far are really offline.
    // ignore: deprecated_member_use
    for (final other in client.matrixClient.presences.values.toList()) {
      if (other.userid != presence.userid &&
          _onlyKnownOffline(other) &&
          _serverOf(other.userid) == server &&
          _recentlyActive(other.userid, other) == null) {
        _controller.add((other.userid, convertPresence(other)));
      }
    }
  }

  UserPresence convertPresence(CachedPresence presence) {
    final status = switch (presence.presence) {
      PresenceType.offline
          when _onlyKnownOffline(presence) &&
              !_presenceServers.contains(_serverOf(presence.userid)) =>
        UserPresenceStatus.unknown,
      PresenceType.offline => UserPresenceStatus.offline,
      PresenceType.online => UserPresenceStatus.online,
      PresenceType.unavailable => UserPresenceStatus.unavailable,
    };

    UserPresenceMessage? message = null;

    if (presence.statusMsg != null) {
      message = UserPresenceMessage(
          presence.statusMsg!, PresenceMessageType.userCustom);
    }

    return UserPresence(status, message: message);
  }

  void changed(CachedPresence event) {
    _learnServer(event);
    _controller.add((event.userid, convertPresence(event)));
  }

  @override
  Stream<(String, UserPresence)> get onPresenceChanged => _controller.stream;

  static const presenceModes = ["online", "idle", "invisible"];

  /// Only while the profile controls experiment is on; otherwise presence
  /// follows app activity as in Commet.
  @override
  String get presenceMode => preferences.experimentQuickProfileControls.value
      ? preferences.getPresenceMode(client.identifier)
      : "online";

  /// The presence a chosen mode pins, or null when it follows app activity.
  UserPresenceStatus? get _pinnedStatus => switch (presenceMode) {
        "idle" => UserPresenceStatus.unavailable,
        "invisible" => UserPresenceStatus.offline,
        _ => null,
      };

  /// /sync marks the user online unless told otherwise, which would undo
  /// idle and invisible on the next sync.
  void _applySyncPresence() {
    client.matrixClient.syncPresence = switch (presenceMode) {
      "idle" => PresenceType.unavailable,
      "invisible" => PresenceType.offline,
      _ => null,
    };
  }

  @override
  Future<void> setPresenceMode(String mode) async {
    await preferences.setPresenceMode(client.identifier, mode);
    _applySyncPresence();
    await setStatus(UserPresenceStatus.online);
  }

  @override
  Future<void> setStatus(UserPresenceStatus status,
      {String? message, bool clearMessage = false}) async {
    status = _pinnedStatus ?? status;
    final self = client.self!.identifier;

    final current = await client.matrixClient.getPresence(self);

    await client.matrixClient.setPresence(
        self,
        statusMsg: clearMessage ? null : message ?? current.statusMsg,
        switch (status) {
          UserPresenceStatus.offline => PresenceType.offline,
          UserPresenceStatus.unknown => PresenceType.offline,
          UserPresenceStatus.online => PresenceType.online,
          UserPresenceStatus.unavailable => PresenceType.unavailable,
        });
  }

  void onSync(SyncUpdate event) {
    if (event.rooms?.join != null) {
      for (var update in event.rooms!.join!.entries) {
        handleEvents(update.value.ephemeral);
        handleEvents(update.value.state);
        handleTimelineUpdate(update.value.timeline);
      }
    }
  }

  void handleEvents(List<BasicEvent>? events) {
    if (events == null) return;
    var time = DateTime.now();

    for (var event in events) {
      try {
        if (event.type == "m.typing") {
          handleTyping(event, time);
          return;
        }

        if (event.type == "m.receipt") {
          handleReadReceipt(event);
          return;
        }

        if (event.type == "m.room.member") {
          handleRoomMemberEvent(event);
          return;
        }
      } catch (_) {}
    }
  }

  void handleTyping(BasicEvent event, DateTime time) {
    for (var id in event.content["user_ids"] as List<dynamic>) {
      sawUser(id, time);
    }
  }

  void handleReadReceipt(BasicEvent event) {
    for (var event in event.content.values) {
      var read = (event as Map<String, dynamic>)["m.read"];
      if (read == null) continue;

      for (var entry in (read as Map<String, dynamic>).entries) {
        var value = entry.value as Map<String, dynamic>;

        if (value.containsKey("ts")) {
          sawUser(entry.key,
              DateTime.fromMicrosecondsSinceEpoch((value["ts"] as int) * 1000));
        }
      }
    }
  }

  void handleTimelineUpdate(TimelineUpdate? timeline) async {
    if (timeline?.events == null) return;

    for (var event in timeline!.events!) {
      sawUser(event.senderId, event.originServerTs);
    }
  }

  void sawUser(String id, DateTime timestamp) async {
    final presence = await client.matrixClient
        .fetchCurrentPresence(id, fetchOnlyFromCached: true);

    if (!_onlyKnownOffline(presence)) return;

    if (DateTime.now().difference(timestamp).inSeconds < 60) {
      var seen = lastSeen.get(id);

      if (seen == null) {
        lastSeen.put(id, timestamp);
      } else {
        if (timestamp.isAfter(seen)) {
          lastSeen.put(id, timestamp);
        }
      }

      _controller.add((id, UserPresence(UserPresenceStatus.online)));
    }
  }

  void onLastSeenRemoved(String event) async {
    final presence = await client.matrixClient
        .fetchCurrentPresence(event, fetchOnlyFromCached: true);
    if (presence.presence == PresenceType.offline) {
      _controller.add((event, convertPresence(presence)));
    }
  }

  void handleRoomMemberEvent(BasicEvent event) {}
}
