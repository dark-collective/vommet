import 'package:commet/client/attachment.dart';

/// Unsent message text and attachments, kept per room (and per thread) while the app runs,
/// so switching to another room and back does not lose what was typed.
///
/// Drafts are only held in memory: nothing typed in an encrypted room is
/// written to disk.
class MessageDraft<T> {
  const MessageDraft(this.text,
      {this.relatedEvent,
      this.relation,
      this.editBaseline,
      this.attachments = const []});

  final String text;

  /// Files added to the message box (pasted or picked) but not sent yet.
  final List<PendingFileAttachment> attachments;

  /// The event being replied to or edited, if any, and how.
  final T? relatedEvent;
  final Enum? relation;

  /// Original text for a history edit that still needs to be saved.
  final String? editBaseline;
}

class MessageDrafts<T> {
  final Map<String, MessageDraft<T>> _drafts = {};

  static String keyFor(String clientId, String roomId, {String? threadId}) =>
      "$clientId\u0000$roomId\u0000${threadId ?? ""}";

  MessageDraft<T>? get(String key) => _drafts[key];

  /// Stores [draft], or forgets an empty message draft with no attachments.
  /// An empty edit can represent a user deleting the original text.
  void set(String key, MessageDraft<T> draft) {
    if (draft.text.trim().isEmpty &&
        draft.attachments.isEmpty &&
        draft.editBaseline == null) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
  }

  void clear(String key) => _drafts.remove(key);
}
