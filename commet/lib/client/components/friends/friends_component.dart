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

  /// The homeserver's user directory for the Add friend lookup, as
  /// (user ID, display name) pairs. Empty when the search fails.
  Future<List<(String, String)>> searchDirectory(String term);

  /// Whether [userId] is a real account: false when its homeserver says it
  /// doesn't exist, null when we can't tell (server down, profiles private).
  Future<bool?> accountExists(String userId);
}

/// The list's account data content: `{"friends": {"@a:x": {"added_ts": ms}}}`.
/// A map rather than a list, so each entry can grow fields later.
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

  static Map<String, dynamic> _friendsOf(Map<String, dynamic>? content) {
    final friends = content?["friends"];
    return friends is Map ? Map<String, dynamic>.from(friends) : {};
  }
}
