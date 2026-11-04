import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';

/// Vommet: your friends list (Vommet issue 93). One-way and private: adding
/// someone only changes your own list, which syncs between your devices.
abstract class FriendsComponent<T extends Client> implements Component<T> {
  /// Matrix IDs of the people on the list.
  Set<String> get friends;

  /// Fires when the list changes, here or on another device.
  Stream<void> get onFriendsChanged;

  Future<void> addFriends(Iterable<String> userIds);

  Future<void> removeFriend(String userId);

  /// Removes several people at once, like all accounts of one person.
  Future<void> removeFriends(Iterable<String> userIds);

  /// People on the list with more than one Matrix account (Vommet issue
  /// 638), each as its Matrix IDs with the main account first.
  List<List<String>> get linkedPeople;

  /// Links [userId] (added to the list if it isn't on it) to [mainId], so
  /// they show as one person with [mainId] as the main account.
  Future<void> linkFriend(String mainId, String userId);

  /// Shows [userId] as its own contact again.
  Future<void> unlinkFriend(String userId);

  /// Makes [userId] the main account of the person it's linked into.
  Future<void> setMainFriend(String userId);

  /// The homeserver's user directory for the Add friend lookup, as
  /// (user ID, display name) pairs. Empty when the search fails.
  Future<List<(String, String)>> searchDirectory(String term);

  /// Whether [userId] is a real account: false when its homeserver says it
  /// doesn't exist, null when we can't tell (server down, profiles private).
  Future<bool?> accountExists(String userId);
}

/// The list's account data content: `{"friends": {"@a:x": {"added_ts": ms}}}`.
/// A map rather than a list, so each entry can grow fields later.
///
/// Linked accounts (Vommet issue 638): the entries of one person share a
/// `"person"` id, and one of them can carry `"main": true`. Older builds
/// ignore both fields and show the accounts as separate entries.
class FriendsListContent {
  static Set<String> parse(Map<String, dynamic>? content) {
    final friends = content?["friends"];
    if (friends is! Map) return {};
    return {
      for (final id in friends.keys)
        if (id is String && id.startsWith("@") && id.contains(":")) id
    };
  }

  static Map<String, dynamic> withFriends(
      Map<String, dynamic>? content, Iterable<String> userIds, int nowMs) {
    final friends = _friendsOf(content);
    for (final id in userIds) {
      friends.putIfAbsent(id, () => {"added_ts": nowMs});
    }
    return {...?content, "friends": friends};
  }

  static Map<String, dynamic> without(
      Map<String, dynamic>? content, String userId) {
    final friends = _friendsOf(content)..remove(userId);
    return {...?content, "friends": friends};
  }

  static Map<String, dynamic> withoutAll(
      Map<String, dynamic>? content, Iterable<String> userIds) {
    final friends = _friendsOf(content);
    for (final id in userIds) {
      friends.remove(id);
    }
    return {...?content, "friends": friends};
  }

  /// The people with two or more accounts on the list, each main account
  /// first: the one marked main, else the earliest added.
  static List<List<String>> people(Map<String, dynamic>? content) {
    final friends = _friendsOf(content);
    final groups = <String, List<String>>{};
    for (final id in parse(content)) {
      if (_entry(friends, id)["person"] case final String person) {
        groups.putIfAbsent(person, () => []).add(id);
      }
    }
    int addedTs(String id) => switch (_entry(friends, id)["added_ts"]) {
          final int ts => ts,
          _ => 1 << 52,
        };
    bool isMain(String id) => _entry(friends, id)["main"] == true;
    final result = [
      for (final group in groups.values)
        if (group.length > 1)
          group
            ..sort((a, b) {
              if (isMain(a) != isMain(b)) return isMain(a) ? -1 : 1;
              final ts = addedTs(a).compareTo(addedTs(b));
              return ts != 0 ? ts : a.compareTo(b);
            })
    ];
    result.sort((a, b) => a.first.compareTo(b.first));
    return result;
  }

  /// Links [userId], and anyone already linked with it, into [mainId]'s
  /// person, adding either to the list if needed. [mainId] becomes main.
  static Map<String, dynamic> linked(
      Map<String, dynamic>? content, String mainId, String userId, int nowMs) {
    if (mainId == userId) return withFriends(content, [mainId], nowMs);
    final added = withFriends(content, [mainId, userId], nowMs);
    final friends = _friendsOf(added);
    final person = switch (_entry(friends, mainId)["person"]) {
      final String p => p,
      _ => "$nowMs:$mainId",
    };
    final joining = _entry(friends, userId)["person"];
    for (final id in friends.keys.toList()) {
      final entry = _entry(friends, id);
      final p = entry["person"];
      if (id != mainId && id != userId && p != person && p != joining) {
        continue;
      }
      if (id != mainId && id != userId && p == null) continue;
      entry["person"] = person;
      if (id == mainId) {
        entry["main"] = true;
      } else {
        entry.remove("main");
      }
      friends[id] = entry;
    }
    return {...added, "friends": friends};
  }

  /// Takes [userId] out of its person. A person left with one account
  /// becomes a plain entry again.
  static Map<String, dynamic> unlinked(
      Map<String, dynamic>? content, String userId) {
    final friends = _friendsOf(content);
    final person = _entry(friends, userId)["person"];
    if (person == null) return {...?content, "friends": friends};
    friends[userId] = _entry(friends, userId)
      ..remove("person")
      ..remove("main");
    final rest = [
      for (final id in friends.keys)
        if (_entry(friends, id)["person"] == person) id
    ];
    if (rest.length == 1) {
      friends[rest.first] = _entry(friends, rest.first)
        ..remove("person")
        ..remove("main");
    }
    return {...?content, "friends": friends};
  }

  /// Makes [userId] the main account of its person.
  static Map<String, dynamic> withMain(
      Map<String, dynamic>? content, String userId) {
    final friends = _friendsOf(content);
    final person = _entry(friends, userId)["person"];
    if (person == null) return {...?content, "friends": friends};
    for (final id in friends.keys.toList()) {
      final entry = _entry(friends, id);
      if (entry["person"] != person) continue;
      if (id == userId) {
        entry["main"] = true;
      } else {
        entry.remove("main");
      }
      friends[id] = entry;
    }
    return {...?content, "friends": friends};
  }

  static Map<String, dynamic> _entry(Map<String, dynamic> friends, String id) {
    final entry = friends[id];
    return entry is Map ? Map<String, dynamic>.from(entry) : {};
  }

  static Map<String, dynamic> _friendsOf(Map<String, dynamic>? content) {
    final friends = content?["friends"];
    return friends is Map ? Map<String, dynamic>.from(friends) : {};
  }
}
