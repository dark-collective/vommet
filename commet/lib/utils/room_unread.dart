import 'package:commet/utils/badge_rules.dart';

/// Room-wide counts. Thread counts are not supplied by the SDK.
/// This model and its aggregations deliberately have no SDK or UI dependencies.
class RoomUnread {
  const RoomUnread(
      {this.notifications = 0,
      this.highlights = 0,
      this.noisy = false,
      this.muted = false,
      this.markedUnread = false,
      this.activity = false});

  factory RoomUnread.compute(
      {required bool muted,
      required bool notify,
      required int notifications,
      required int highlights,
      required bool messagesAreNoisy,
      bool markedUnread = false,
      bool unreadEvent = false}) {
    if (muted) return const RoomUnread(muted: true);
    final messages = notify ? notifications : 0;
    final badge =
        BadgeRules.count(notifications: messages, highlights: highlights);
    return RoomUnread(
        notifications: messages,
        highlights: highlights,
        noisy: BadgeRules.noisy(
            notifications: messages,
            highlights: highlights,
            messagesAreNoisy: messagesAreNoisy),
        markedUnread: markedUnread,
        // Mentions-only intentionally ignores plain-message activity.
        activity: badge == 0 && (markedUnread || (notify && unreadEvent)));
  }

  final bool muted;
  final int notifications;
  final int highlights;
  int get badge =>
      BadgeRules.count(notifications: notifications, highlights: highlights);
  final bool noisy;
  final bool markedUnread;
  final bool activity;
  bool get unread => badge > 0 || activity;

  @override
  bool operator ==(Object other) =>
      other is RoomUnread &&
      notifications == other.notifications &&
      highlights == other.highlights &&
      noisy == other.noisy &&
      muted == other.muted &&
      markedUnread == other.markedUnread &&
      activity == other.activity;

  @override
  int get hashCode => Object.hash(
      notifications, highlights, noisy, muted, markedUnread, activity);
}

/// A sum of rooms, never max(sum(notifications), sum(highlights)).
class PersonUnread {
  const PersonUnread(
      {this.badge = 0,
      this.notifications = 0,
      this.highlights = 0,
      this.noisy = false,
      this.activity = false,
      this.muted = false});
  factory PersonUnread.of(Iterable<RoomUnread> rooms) {
    var badge = 0, notifications = 0, highlights = 0;
    var noisy = false, activity = false, muted = true;
    for (final room in rooms) {
      muted &= room.muted;
      badge += room.badge;
      notifications += room.notifications;
      highlights += room.highlights;
      noisy |= room.noisy;
      activity |= room.activity;
    }
    return PersonUnread(
        badge: badge,
        notifications: notifications,
        highlights: highlights,
        noisy: noisy,
        activity: activity,
        muted: muted);
  }
  factory PersonUnread.sum(Iterable<PersonUnread> rows) {
    var badge = 0, notifications = 0, highlights = 0;
    var noisy = false, activity = false, muted = true;
    for (final row in rows) {
      badge += row.badge;
      notifications += row.notifications;
      highlights += row.highlights;
      noisy |= row.noisy;
      activity |= row.activity;
      muted &= row.muted;
    }
    return PersonUnread(
        badge: badge,
        notifications: notifications,
        highlights: highlights,
        noisy: noisy,
        activity: activity,
        muted: muted);
  }
  final int badge, notifications, highlights;
  final bool noisy, activity, muted;
  bool get unread => badge > 0 || activity;
}

class UnreadTotals {
  /// Used by space folders, spaces, and room sections: IDs include account.
  static PersonUnread rooms(Iterable<(String, RoomUnread)> rooms) {
    final unique = <String, RoomUnread>{};
    for (final (id, unread) in rooms) {
      unique[id] = unread;
    }
    return PersonUnread.of(unique.values);
  }

  /// The same aggregation powers Home and People, including account filtering.
  static int home(
          {required int invites,
          required Iterable<(String account, PersonUnread)> people,
          String? account,
          bool countDms = true}) =>
      invites +
      (countDms
          ? people
              .where((p) => account == null || p.$1 == account)
              .fold(0, (sum, p) => sum + p.$2.badge)
          : 0);

  static int section(Iterable<PersonUnread> rows) =>
      PersonUnread.sum(rows).badge;

  static (int highlights, int chats) tray(
      Iterable<(String key, PersonUnread unread, bool direct)> entries) {
    final seen = <String>{};
    var highlights = 0, chats = 0;
    for (final (key, unread, direct) in entries) {
      if (!seen.add(key)) continue;
      highlights += direct ? unread.badge : unread.highlights;
      if (unread.badge > 0) chats++;
    }
    return (highlights, chats);
  }
}

/// Known timeline order, newest first. Unknown positions are never inferred
/// from timestamps; exact receipt IDs still work outside the loaded window.
bool receiptCovers(
        String event, Iterable<String> receipts, List<String> newestFirst) =>
    receiptCoverage(event, receipts, newestFirst) == true;

/// True when covered, false when every receipt is known and behind the event,
/// and null when missing positions or receipts prevent that comparison.
bool? receiptCoverage(
    String event, Iterable<String> receipts, List<String> newestFirst) {
  final ids = receipts.toList();
  if (ids.contains(event)) return true;
  final at = orderPosition(newestFirst, event);
  if (at < 0 || ids.isEmpty) return null;
  var unknown = false;
  for (final receipt in ids) {
    final readAt = orderPosition(newestFirst, receipt);
    if (readAt < 0) {
      unknown = true;
    } else if (readAt <= at) {
      return true;
    }
  }
  return unknown ? null : false;
}

final _orderPositions = Expando<Map<String, int>>();

/// Looks positions up in a map instead of scanning, for an unmodifiable
/// order that is queried once per event and receipt on every recompute.
void indexOrder(List<String> newestFirst) => _orderPositions[newestFirst] = {
      for (var i = newestFirst.length - 1; i >= 0; i--) newestFirst[i]: i
    };

/// The position of [id] in [newestFirst], or -1 when it is not there.
int orderPosition(List<String> newestFirst, String id) =>
    _orderPositions[newestFirst]?[id] ?? newestFirst.indexOf(id);
