/// Vommet: Ctrl+↑ / Ctrl+↓ in the message box pick the message to reply to,
/// like Telegram Desktop (Vommet issue 37).
class ReplyNavigation {
  /// One step through [events] (newest first) from the current reply target
  /// [current]: [older] (Ctrl+↑) moves to the next older message you can reply
  /// to, otherwise (Ctrl+↓) to the next newer one.
  ///
  /// Returns the new target, `null` to stop replying (stepping down past the
  /// newest message, or Ctrl+↓ with no reply), or [current] itself when
  /// there's nothing further back in the loaded events.
  static T? step<T>(
    List<T> events,
    T? current, {
    required bool older,
    required bool Function(T event) canReply,
    required String Function(T event) id,
  }) {
    final index = current == null
        ? -1
        : events.indexWhere((event) => id(event) == id(current));

    if (older) {
      for (var i = index + 1; i < events.length; i++) {
        if (canReply(events[i])) return events[i];
      }
      return current;
    }

    if (index < 0) return null;
    for (var i = index - 1; i >= 0; i--) {
      if (canReply(events[i])) return events[i];
    }
    return null;
  }
}
