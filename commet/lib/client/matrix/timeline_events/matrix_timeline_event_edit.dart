import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_edit.dart';

class MatrixTimelineEventEdit extends MatrixTimelineEvent
    implements TimelineEventEdit {
  MatrixTimelineEventEdit(super.event, {required super.client});

  /// Vommet: a room's last message can be an edit, whose own body is the
  /// "* old text" fallback, so room previews and the quick switcher showed
  /// that. Show the edited text instead.
  @override
  String get plainTextBody =>
      newContentBody(event.content) ?? super.plainTextBody;

  /// The edited message's plain text from `m.new_content`, or null when the
  /// event carries none.
  static String? newContentBody(Map<String, Object?> content) {
    final newContent = content["m.new_content"];
    if (newContent is! Map) return null;
    final body = newContent["body"];
    return body is String ? body : null;
  }
}
