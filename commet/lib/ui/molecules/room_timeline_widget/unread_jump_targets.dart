/// Vommet: what the @ and ♥ buttons above "Jump to latest" lead to — the
/// unread messages that mention me, and my messages that got new reactions.
///
/// Kept apart from the timeline so it can be tested on plain values.
class JumpScanEvent {
  const JumpScanEvent(
      {required this.eventId,
      required this.senderId,
      this.reactsTo,
      this.mentionsMe = false});

  final String eventId;
  final String senderId;

  /// For a reaction, the message it is on.
  final String? reactsTo;

  /// Matches a highlight push rule (my name, @room, a keyword).
  final bool mentionsMe;
}

/// A place to jump to, and the events that put it there: seeing it marks
/// all of them seen, and a newer one brings it back.
class JumpTarget {
  const JumpTarget(this.eventId, this.sources);

  final String eventId;
  final Set<String> sources;

  @override
  bool operator ==(Object other) =>
      other is JumpTarget &&
      other.eventId == eventId &&
      other.sources.length == sources.length &&
      other.sources.containsAll(sources);

  @override
  int get hashCode => Object.hash(eventId, Object.hashAllUnordered(sources));

  @override
  String toString() => "JumpTarget($eventId, $sources)";
}

class UnreadJumpTargets {
  const UnreadJumpTargets(
      {this.mentions = const [], this.reactions = const []});

  static const empty = UnreadJumpTargets();

  /// How far back the scan looks, so a long-unread room stays cheap.
  static const int scanLimit = 500;

  /// Oldest first, the order the buttons walk them.
  final List<JumpTarget> mentions;
  final List<JumpTarget> reactions;

  bool get isEmpty => mentions.isEmpty && reactions.isEmpty;

  /// [events] are newest first and stop at [readUpTo] (the read marker,
  /// not included). Events in [seen] (targets or their sources) are left
  /// out. [senderOf] finds who sent a loaded message.
  static UnreadJumpTargets scan(
    Iterable<JumpScanEvent> events, {
    required String? me,
    required String? readUpTo,
    required String? Function(String eventId) senderOf,
    Set<String> seen = const {},
    int limit = scanLimit,
  }) {
    if (me == null || readUpTo == null) return empty;

    final mentions = <JumpTarget>[];
    final reacted = <String, Set<String>>{};
    var count = 0;
    for (final event in events) {
      if (event.eventId == readUpTo || count++ >= limit) break;
      if (event.senderId == me || seen.contains(event.eventId)) continue;

      final target = event.reactsTo;
      if (target != null) {
        if (senderOf(target) == me) {
          reacted.putIfAbsent(target, () => {}).add(event.eventId);
        }
      } else if (event.mentionsMe) {
        mentions.add(JumpTarget(event.eventId, {event.eventId}));
      }
    }

    // Insertion order is newest reaction first.
    final reactions = [
      for (final MapEntry(:key, :value) in reacted.entries)
        JumpTarget(key, value)
    ];
    return UnreadJumpTargets(
        mentions: mentions.reversed.toList(),
        reactions: reactions.reversed.toList());
  }
}
