/// Unsent message text, kept per room (and per thread) while the app runs,
/// so switching to another room and back does not lose what was typed.
///
/// Drafts are only held in memory: nothing typed in an encrypted room is
/// written to disk.
class MessageDraft<T> {
  const MessageDraft(this.text, {this.relatedEvent, this.relation});

  final String text;

  /// The event being replied to or edited, if any, and how.
  final T? relatedEvent;
  final Enum? relation;
}

class MessageDrafts<T> {
  final Map<String, MessageDraft<T>> _drafts = {};

  static String keyFor(String clientId, String roomId, {String? threadId}) =>
      "$clientId\u0000$roomId\u0000${threadId ?? ""}";

  MessageDraft<T>? get(String key) => _drafts[key];

  /// Stores [draft], or forgets the room's draft when its text is blank.
  void set(String key, MessageDraft<T> draft) {
    if (draft.text.trim().isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
  }

  void clear(String key) => _drafts.remove(key);
}
