import 'package:commet/client/components/quick_replies/quick_replies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("parse keeps order, skips bad entries and repeated names", () {
    final items = QuickReplies.parse({
      "version": 1,
      "items": [
        {"name": "greet", "body": "Hi!"},
        {"name": "Greet", "body": "Again"},
        {"name": "bad name", "body": "x"},
        {"name": "empty", "body": "  "},
        {"name": "bye-2", "body": "See you"},
        "junk",
      ],
    });
    expect(items.map((q) => q.name), ["greet", "bye-2"]);
    expect(QuickReplies.parse(null), isEmpty);
    expect(QuickReplies.parse({"items": 3}), isEmpty);
  });

  test("serialize round-trips and caps the list", () {
    final many = [
      for (var i = 0; i < QuickReplies.maxItems + 3; i++)
        QuickReply(name: "q$i", body: "text $i"),
    ];
    final content = QuickReplies.serialize(many);
    expect(content["version"], 1);
    expect((content["items"] as List).length, QuickReplies.maxItems);
    expect(QuickReplies.parse(content).first.body, "text 0");
  });

  test("names: letters, digits and dashes, not a command, not taken", () {
    const existing = [QuickReply(name: "greet", body: "Hi")];
    const commands = {"status", "me"};
    QuickReplyNameProblem? check(String n, {String? editing}) =>
        QuickReplies.checkName(n,
            commands: commands, existing: existing, editing: editing);
    expect(check("thanks-2"), isNull);
    expect(check(""), QuickReplyNameProblem.empty);
    expect(check("two words"), QuickReplyNameProblem.invalid);
    expect(check("/x"), QuickReplyNameProblem.invalid);
    expect(check("Status"), QuickReplyNameProblem.command);
    expect(check("GREET"), QuickReplyNameProblem.taken);
    expect(check("Greet", editing: "greet"), isNull);
    expect(check("a" * 33), QuickReplyNameProblem.invalid);
  });

  test("preview is one shortened line", () {
    expect(QuickReplies.preview("Hello\n  there"), "Hello there");
    expect(QuickReplies.preview("x" * 50).length, 41);
  });
}
