import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("an edit previews its new text, not the '* ' fallback", () {
    final content = {
      "msgtype": "m.text",
      "body": "* What, are you chicken?",
      "m.new_content": {"msgtype": "m.text", "body": "What, are you chicken?"},
      "m.relates_to": {"rel_type": "m.replace", "event_id": "\$original"},
    };
    expect(MatrixTimelineEventEdit.newContentBody(content),
        "What, are you chicken?");
  });

  test("no usable m.new_content falls back to the event's own body", () {
    expect(MatrixTimelineEventEdit.newContentBody({"body": "* hi"}), isNull);
    expect(
        MatrixTimelineEventEdit.newContentBody(
            {"body": "* hi", "m.new_content": "not a map"}),
        isNull);
    expect(
        MatrixTimelineEventEdit.newContentBody({
          "body": "* hi",
          "m.new_content": {"msgtype": "m.text"}
        }),
        isNull);
  });
}
