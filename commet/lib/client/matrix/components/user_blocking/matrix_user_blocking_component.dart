import 'dart:async';

import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: blocking through the account's ignore list (`m.ignored_user_list`).
///
/// Unlike the SDK's `ignoreUser`, this doesn't clear the local cache and
/// resync everything: the server hides new events from blocked users, and
/// [MatrixRoom.convertEvent] hides the ones already cached.
class MatrixUserBlockingComponent
    implements UserBlockingComponent<MatrixClient> {
  static const String key = "m.ignored_user_list";

  @override
  MatrixClient client;

  final StreamController<void> _changed = StreamController.broadcast();

  Set<String> _blocked = {};

  MatrixUserBlockingComponent(this.client) {
    _blocked = _read();
    client.matrixClient.onSync.stream.listen(_onSync);
  }

  @override
  Stream<void> get onChanged => _changed.stream;

  @override
  List<String> get blockedUsers => _blocked.toList()..sort();

  @override
  bool isBlocked(String userId) => _blocked.contains(userId);

  Map<String, dynamic> _content() => Map<String, dynamic>.from(
      client.matrixClient.accountData[key]?.content["ignored_users"] as Map? ??
          const {});

  Set<String> _read() => _content().keys.toSet();

  @override
  Future<void> block(String userId) async {
    if (!userId.isValidMatrixId) {
      throw ArgumentError("$userId is not a valid Matrix ID");
    }
    if (userId == client.matrixClient.userID) {
      throw ArgumentError("You can't block yourself");
    }
    final users = _content()..putIfAbsent(userId, () => <String, dynamic>{});
    await _write(users);
  }

  @override
  Future<void> unblock(String userId) async {
    final users = _content()..remove(userId);
    await _write(users);
  }

  Future<void> _write(Map<String, dynamic> users) async {
    final mx = client.matrixClient;
    await mx.setAccountData(mx.userID!, key, {"ignored_users": users});
    // Don't wait for the sync echo: hide (or show) their messages now.
    _apply(users.keys.toSet());
  }

  void _onSync(matrix.SyncUpdate update) {
    if (update.accountData?.any((e) => e.type == key) != true) return;
    _apply(_read());
  }

  void _apply(Set<String> blocked) {
    if (blocked.length == _blocked.length && blocked.containsAll(_blocked)) {
      return;
    }
    final changed = blocked.difference(_blocked)
      ..addAll(_blocked.difference(blocked));
    _blocked = blocked;
    _refreshTimelines(changed);
    _changed.add(null);
  }

  /// Re-converts loaded timeline events from [users], so their messages
  /// disappear (or come back) without reopening the room.
  void _refreshTimelines(Set<String> users) {
    for (final room in client.rooms) {
      final timeline = room.timeline;
      if (timeline is! MatrixTimeline) continue;
      for (var i = 0; i < timeline.events.length; i++) {
        if (users.contains(timeline.events[i].senderId)) {
          timeline.onEventChanged(i);
        }
      }
    }
  }
}
