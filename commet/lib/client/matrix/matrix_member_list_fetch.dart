import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 583: the member panel's full member list fetch for one room.
///
/// The Members tab fetched the room's whole member list every time it was
/// built while the room's list counted as incomplete. Only joined members
/// were kept, so a room with a pending invite never became complete and
/// every room open (or tab switch) downloaded the list again: megabytes per
/// open in big public rooms. The request also asked for every membership,
/// including everyone who ever left, which the client then threw away.
///
/// Now the fetch runs at most once per [maxAge] (concurrent callers share
/// it), the panel treats the list as complete for that long
/// ([recentlyFetched]; sync keeps the members held in memory current), and
/// the server is asked to leave out departed members
/// (`not_membership=leave`).
class MatrixMemberListFetch {
  MatrixMemberListFetch(
    this.room, {
    this.maxAge = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final matrix.Room room;

  /// How long a finished fetch stands in for the full list.
  final Duration maxAge;

  final DateTime Function() _now;

  DateTime? _fetchedAt;
  Future<List<matrix.User>>? _running;

  /// Whether a full fetch finished less than [maxAge] ago.
  bool get recentlyFetched {
    final at = _fetchedAt;
    return at != null && _now().difference(at) < maxAge;
  }

  /// The room's joined members: from memory when the local list is complete
  /// or was fetched recently, otherwise from one server request.
  Future<List<matrix.User>> joinedMembers() async {
    if (recentlyFetched) return _heldJoined();
    final running = _running ??= _fetch();
    try {
      return await running;
    } finally {
      if (identical(_running, running)) _running = null;
    }
  }

  List<matrix.User> _heldJoined() =>
      room.getParticipants([matrix.Membership.join]);

  Future<List<matrix.User>> _fetch() async {
    // As requestParticipants: the stored members may already complete the
    // list (a partial room's state lives in the database only).
    if (!room.participantListComplete || room.partial) {
      // Vommet: timed for the perf summary (GetUsersStats).
      final stored = await matrix.GetUsersStats.time(
          () => room.client.database.getUsers(room));
      for (final user in stored) {
        room.setState(user);
      }
    }
    if (room.participantListComplete) {
      _fetchedAt = _now();
      return _heldJoined();
    }

    final events = await room.client.getMembersByRoom(room.id,
            notMembership: matrix.Membership.leave) ??
        const <matrix.MatrixEvent>[];
    final held = room.states[matrix.EventTypes.RoomMember];
    for (final event in events) {
      final user = matrix.Event.fromMatrixEvent(event, room).asUser;
      // Keep the fetched members in memory (without storing them), as
      // before. Only joined ones (the panel lists those) and only gaps: a
      // member event already held may be newer than this snapshot.
      if (user.membership == matrix.Membership.join && held?[user.id] == null) {
        room.setState(user);
      }
    }
    _fetchedAt = _now();
    return _heldJoined();
  }
}
