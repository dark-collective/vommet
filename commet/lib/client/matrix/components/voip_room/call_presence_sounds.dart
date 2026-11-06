import 'dart:async';

/// Vommet: one LiveKit connection in a call, as the join/leave sounds see
/// it. [isMember]: it belongs to a live call membership.
typedef CallConnection = ({String userId, String? deviceId, bool isMember});

/// Vommet: join and leave sounds per person, not per LiveKit connection.
///
/// Testers heard the join sound for a second device, for a bridged screen
/// share's stream entry and for LiveKit-only participants, and a leave and
/// join pair when someone reconnected. Now:
/// - the join sound plays only for a real call member who had no other
///   connection in the call;
/// - the leave sound plays for a person's last connection, 3 s later, and a
///   rejoin in those 3 s cancels it (nothing plays);
/// - bridge stream entries (device id starting with "S") never make a sound.
class CallPresenceSounds {
  CallPresenceSounds({
    required this.playJoin,
    required this.playLeave,
    Timer Function(Duration, void Function())? timer,
    this.leaveDelay = const Duration(seconds: 3),
    this.memberGrace = const Duration(seconds: 2),
  }) : _timer = timer ?? Timer.new;

  final void Function() playJoin;
  final void Function() playLeave;
  final Timer Function(Duration, void Function()) _timer;
  final Duration leaveDelay;

  /// A connection may reach LiveKit before its membership syncs; it's
  /// checked once more after this.
  final Duration memberGrace;

  final Map<String, CallConnection> _connections = {};
  final Map<String, Timer> _pendingLeave = {};
  final Map<String, Timer> _memberChecks = {};

  /// People whose arrival counted (a sound, or present as a member when the
  /// call opened): only they get a leave sound.
  final Set<String> _announced = {};

  /// A bridge stream entry: its device id starts with "S".
  static bool isStreamEntry(String? deviceId) =>
      deviceId != null && deviceId.startsWith("S");

  /// Whether [joined] arriving plays the join sound, given the [others]
  /// already connected and whether its person's leave sound is pending.
  static bool shouldPlayJoin(
      CallConnection joined, Iterable<CallConnection> others,
      {bool leavePending = false}) {
    if (isStreamEntry(joined.deviceId) || !joined.isMember) return false;
    if (leavePending) return false;
    return !others
        .any((o) => o.userId == joined.userId && !isStreamEntry(o.deviceId));
  }

  /// Whether [left] was its person's last connection, given the
  /// [remaining] ones.
  static bool isLastConnection(
      CallConnection left, Iterable<CallConnection> remaining) {
    if (isStreamEntry(left.deviceId)) return false;
    return !remaining
        .any((o) => o.userId == left.userId && !isStreamEntry(o.deviceId));
  }

  /// Someone already in the call when we joined (or ourselves): no sound.
  void seed(String identity, CallConnection connection) {
    if (isStreamEntry(connection.deviceId)) return;
    _connections[identity] = connection;
    if (connection.isMember) _announced.add(connection.userId);
  }

  /// [identity] connected. [recheck] gives its connection again later, for
  /// a membership that hadn't synced yet.
  void connected(String identity, CallConnection connection,
      {CallConnection Function()? recheck}) {
    if (isStreamEntry(connection.deviceId)) return;
    final others = _connections.values.toList();
    _connections[identity] = connection;
    final pending = _pendingLeave.remove(connection.userId);
    if (pending != null) {
      pending.cancel();
      return;
    }
    if (shouldPlayJoin(connection, others)) {
      _announced.add(connection.userId);
      playJoin();
      return;
    }
    if (connection.isMember || recheck == null) return;
    _memberChecks.remove(identity)?.cancel();
    _memberChecks[identity] = _timer(memberGrace, () {
      _memberChecks.remove(identity);
      if (!_connections.containsKey(identity)) return;
      final now = recheck();
      _connections[identity] = now;
      if (_announced.contains(now.userId)) return;
      final rest = Map.of(_connections)..remove(identity);
      if (shouldPlayJoin(now, rest.values,
          leavePending: _pendingLeave.containsKey(now.userId))) {
        _announced.add(now.userId);
        playJoin();
      }
    });
  }

  /// [identity] disconnected.
  void disconnected(String identity) {
    _memberChecks.remove(identity)?.cancel();
    final left = _connections.remove(identity);
    if (left == null) return;
    if (!isLastConnection(left, _connections.values)) return;
    final user = left.userId;
    if (!_announced.contains(user)) return;
    _pendingLeave.remove(user)?.cancel();
    _pendingLeave[user] = _timer(leaveDelay, () {
      _pendingLeave.remove(user);
      _announced.remove(user);
      playLeave();
    });
  }

  void dispose() {
    for (final t in [..._pendingLeave.values, ..._memberChecks.values]) {
      t.cancel();
    }
    _pendingLeave.clear();
    _memberChecks.clear();
  }
}
