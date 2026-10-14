import 'package:commet/ui/molecules/room_timeline_widget/message_hover_bar.dart';
import 'package:test/test.dart';

void main() {
  test("hover bar setting parses, defaulting to compact", () {
    expect(MessageHoverBar.parse("full"), MessageHoverBar.full);
    expect(MessageHoverBar.parse("off"), MessageHoverBar.off);
    expect(MessageHoverBar.parse("compact"), MessageHoverBar.compact);
    expect(MessageHoverBar.parse("something else"), MessageHoverBar.compact);
  });
}
