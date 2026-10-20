import 'package:commet/client/client.dart';
import 'package:commet/client/components/activities/activities_component.dart';

/// Vommet: a call in a room you share with at least one friend, for the
/// Friends tab's Active Now (Vommet issue 93).
class ActiveCall {
  ActiveCall(this.room, this.participants, this.friendsIn);
  final Room room;

  /// Everyone in the call except you, friends first.
  final List<String> participants;
  final List<String> friendsIn;
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

  /// Whether [text] looks like a full Matrix user ID.
  static bool isUserId(String text) {
    final t = text.trim();
    final colon = t.indexOf(":");
    return t.startsWith("@") &&
        colon > 1 &&
        colon < t.length - 1 &&
        !t.contains(" ");
  }
}
