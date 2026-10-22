import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';

/// Vommet: a call in a room you share with at least one friend, for the
/// Friends tab's Active Now (Vommet issue 93).
class ActiveCall {
  ActiveCall(this.room, this.participants, this.friendsIn);
  final Room room;

  /// Everyone in the call except you, friends first.
  final List<String> participants;
  final List<String> friendsIn;
}

/// Vommet: one person the Add friend lookup offers (Vommet issue 93
/// follow-up): someone you have a DM with, or a homeserver directory hit.
class FriendCandidate {
  FriendCandidate(this.userId, this.name,
      {required this.fromDm, required this.alreadyFriend});
  final String userId;
  final String name;
  final bool fromDm;
  final bool alreadyFriend;
}

class FriendsModel {
  /// Calls (not third-party widgets) in [rooms] with a friend in them,
  /// biggest first. Expired memberships are already left out by the
  /// activities component.
  static List<ActiveCall> activeNow(
      Iterable<Room> rooms, Set<String> friends, String? selfId) {
    final calls = <ActiveCall>[];
    for (final room in rooms) {
      final sessions =
          room.getComponent<ActivitiesComponent>()?.getSessions() ?? const [];
      for (final session in sessions) {
        if (session.thirdparty) continue;
        final people = session.participants.where((p) => p != selfId);
        final friendsIn = people.where(friends.contains).toList()..sort();
        if (friendsIn.isEmpty) continue;
        final others = people.where((p) => !friends.contains(p)).toList()
          ..sort();
        calls.add(ActiveCall(room, [...friendsIn, ...others], friendsIn));
      }
    }
    calls
        .sort((a, b) => b.participants.length.compareTo(a.participants.length));
    return calls;
  }

  /// DM partners who aren't on the list yet, in a stable order.
  static List<String> suggestions(
      Iterable<String> dmPartners, Set<String> friends, String? selfId) {
    return {
      for (final p in dmPartners)
        if (!friends.contains(p) && p != selfId) p
    }.toList()
      ..sort();
  }

  /// Sort group for the friends list (Vommet issue 540): online and away
  /// first, then presence unknown (many homeservers, matrix.org among them,
  /// don't share presence), then offline.
  static int presenceRank(UserPresenceStatus status) => switch (status) {
        UserPresenceStatus.online || UserPresenceStatus.unavailable => 0,
        UserPresenceStatus.unknown => 1,
        UserPresenceStatus.offline => 2,
      };

  /// Orders friends by [presenceRank], then by name (case-insensitive).
  static int compareFriends(
      UserPresenceStatus a, String aName, UserPresenceStatus b, String bName) {
    final rank = presenceRank(a).compareTo(presenceRank(b));
    if (rank != 0) return rank;
    return aName.toLowerCase().compareTo(bName.toLowerCase());
  }

  /// Whether [text] looks like a full Matrix user ID.
  static bool isUserId(String text) {
    final t = text.trim();
    final colon = t.indexOf(":");
    return t.startsWith("@") &&
        colon > 1 &&
        colon < t.length - 1 &&
        !t.contains(" ");
  }

  /// How well [query] matches a person, lower is better, null for no
  /// match: exact ID, then ID or name prefix, then a word in the name, then
  /// anywhere. [query] is already lower case without a leading "@".
  static int? _matchScore(String query, String userId, String name) {
    final id = userId.toLowerCase().replaceFirst("@", "");
    final n = name.toLowerCase();
    if (id == query) return 0;
    if (id.startsWith(query) || n.startsWith(query)) return 1;
    if (n.split(RegExp(r"\s+")).any((w) => w.startsWith(query))) return 2;
    if (id.contains(query) || n.contains(query)) return 3;
    return null;
  }

  /// The text to send to the homeserver's user directory for [query]: no
  /// leading "@", and a bare "@name:" searches just "name".
  static String directoryTerm(String query) {
    var t = query.trim();
    if (t.startsWith("@")) t = t.substring(1);
    if (t.endsWith(":")) t = t.substring(0, t.length - 1);
    return t;
  }

  /// The Add friend lookup's rows for [query]: people you have a DM with
  /// first, then [directory] results, each group best match first. People
  /// already on the list stay in (marked) so you can see they're there. An
  /// empty [query] lists your DM partners who aren't friends yet.
  static List<FriendCandidate> lookup(
    String query, {
    required Map<String, String> dmPartners,
    required Iterable<(String, String)> directory,
    required Set<String> friends,
    String? selfId,
    int limit = 8,
  }) {
    final q = directoryTerm(query).toLowerCase();
    final dms = <(int, FriendCandidate)>[];
    for (final MapEntry(key: id, value: name) in dmPartners.entries) {
      if (id == selfId) continue;
      if (q.isEmpty) {
        if (!friends.contains(id)) {
          dms.add((
            0,
            FriendCandidate(id, name, fromDm: true, alreadyFriend: false)
          ));
        }
        continue;
      }
      final score = _matchScore(q, id, name);
      if (score == null) continue;
      dms.add((
        score,
        FriendCandidate(id, name,
            fromDm: true, alreadyFriend: friends.contains(id))
      ));
    }
    final others = <(int, FriendCandidate)>[];
    if (q.isNotEmpty) {
      final seen = {for (final (_, c) in dms) c.userId};
      for (final (id, name) in directory) {
        if (id == selfId || !seen.add(id)) continue;
        // The directory matches on more than we can see (display names we
        // don't have, other tokenising), so keep its hits regardless.
        final dmName = dmPartners[id];
        final score = _matchScore(q, id, dmName ?? name) ?? 4;
        final c = FriendCandidate(id, dmName ?? name,
            fromDm: dmName != null, alreadyFriend: friends.contains(id));
        (dmName != null ? dms : others).add((score, c));
      }
    }
    int byScoreThenName((int, FriendCandidate) a, (int, FriendCandidate) b) {
      final s = a.$1.compareTo(b.$1);
      return s != 0
          ? s
          : a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
    }

    dms.sort(byScoreThenName);
    // Stable, so the directory's own order breaks ties.
    mergeSort(others, compare: (a, b) => a.$1.compareTo(b.$1));

    return [
      for (final (_, c) in [...dms, ...others]) c
    ].take(limit).toList();
  }
}
