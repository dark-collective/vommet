import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:test/test.dart';

void main() {
  test("short text reactions stay as they are", () {
    expect(EmojiWidget.shortenText("lol"), "lol");
    expect(EmojiWidget.shortenText("0123456789"), "0123456789");
  });

  test("long text reactions are cut short with an ellipsis", () {
    expect(
        EmojiWidget.shortenText("this is a very long reaction"), "this is a…");
  });

  test("shortening keeps whole characters", () {
    expect(EmojiWidget.shortenText("👍🏽" * 12), "${"👍🏽" * 9}…");
  });
}
