// Vommet issue 475: room event lines (e.g. "X pinned a message") rebuilt for
// redacted mode, the way membership lines are (Vommet issue 490).

/// A timeline line that names its sender.
abstract class TimelineEventRedactableBody {
  /// The line with the sender's name passed through [nameOf] (display name,
  /// user id) and anything the sender wrote through [textOf].
  String redactedBody(String Function(String name, String userId) nameOf,
      String Function(String text) textOf);
}
