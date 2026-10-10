/// Grouping of consecutive media posts into one mosaic (Telegram-style).
///
/// Works on a timeline ordered like Commet's: index 0 is the NEWEST event and
/// index + 1 is the one before it. A run of joinable posts is split into
/// groups of at most [MediaGroups.maxSize]; the OLDEST event of each group is
/// its root (it renders the whole group, at the top where the sender header
/// is) and the others are children (they render nothing).
class MediaGroupMember {
  final String sender;
  final DateTime time;

  /// A single image or video, with no caption, not a reply, no reactions.
  final bool groupable;

  const MediaGroupMember(this.sender, this.time, {required this.groupable});
}

enum MediaGroupRole { none, root, child }

class MediaGroupPosition {
  final MediaGroupRole role;

  /// Index of the group's root (oldest member), or null when ungrouped.
  final int? rootIndex;

  /// For a root: member indices from oldest to newest, root first.
  final List<int> members;

  const MediaGroupPosition(this.role,
      {this.rootIndex, this.members = const []});

  static const none = MediaGroupPosition(MediaGroupRole.none);
}

class MediaGroups {
  static const Duration maxGap = Duration(seconds: 60);
  static const int maxSize = 10;

  static bool canJoin(MediaGroupMember older, MediaGroupMember newer) {
    if (!older.groupable || !newer.groupable) return false;
    if (older.sender != newer.sender) return false;
    return newer.time.difference(older.time).abs() <= maxGap;
  }

  /// Indices (newest, oldest) of the run of joinable posts around [index],
  /// before it is split into groups; just (index, index) when the event
  /// can't join its neighbours.
  static (int, int) runExtent(
      int index, MediaGroupMember Function(int index) at, int length) {
    var oldest = index;
    while (oldest + 1 < length && canJoin(at(oldest + 1), at(oldest))) {
      oldest++;
    }
    var newest = index;
    while (newest - 1 >= 0 && canJoin(at(newest), at(newest - 1))) {
      newest--;
    }
    return (newest, oldest);
  }

  /// Where the event at [index] sits. [at] returns the member for an index;
  /// [length] is the number of events in the timeline.
  static MediaGroupPosition position(
      int index, MediaGroupMember Function(int index) at, int length) {
    if (index < 0 || index >= length || !at(index).groupable) {
      return MediaGroupPosition.none;
    }

    // Oldest event of the run this event belongs to.
    var runStart = index;
    while (runStart + 1 < length && canJoin(at(runStart + 1), at(runStart))) {
      runStart++;
    }

    final offset = runStart - index;
    final rootIndex = runStart - (offset ~/ maxSize) * maxSize;

    // Members of this group, oldest first.
    final members = <int>[rootIndex];
    var i = rootIndex;
    while (
        members.length < maxSize && i - 1 >= 0 && canJoin(at(i), at(i - 1))) {
      i--;
      members.add(i);
    }

    if (members.length < 2) return MediaGroupPosition.none;

    if (index == rootIndex) {
      return MediaGroupPosition(MediaGroupRole.root,
          rootIndex: rootIndex, members: members);
    }
    return MediaGroupPosition(MediaGroupRole.child, rootIndex: rootIndex);
  }
}
