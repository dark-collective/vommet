import 'package:commet/client/components/message_filters/message_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MessageFilterRule rule(String input) => MessageFilterRule.fromInput(input)!;

  test("input picks the kind", () {
    expect(rule("spoiler").kind, MessageFilterKind.word);
    expect(rule("season finale").kind, MessageFilterKind.phrase);
    expect(rule("/foo\\d+/").kind, MessageFilterKind.regex);
    expect(MessageFilterRule.fromInput("   "), isNull);
  });

  test("a word matches whole words only, any case", () {
    final r = rule("cat");
    expect(r.matches("My CAT sleeps"), isTrue);
    expect(r.matches("concatenate"), isFalse);
    expect(r.matches("cat."), isTrue);
  });

  test("a phrase matches anywhere", () {
    expect(rule("season finale").matches("the Season Finale!"), isTrue);
    expect(rule("season finale").matches("season one"), isFalse);
  });

  test("regex matches and an invalid regex never does", () {
    expect(rule("/ep\\s?\\d+/").matches("watching EP 12"), isTrue);
    final bad = rule("/(unclosed/");
    expect(bad.pattern, isNull);
    expect(bad.matches("(unclosed"), isFalse);
  });

  test("rooms scope", () {
    final r = rule("cat").withRooms(["!a:x"]);
    final settings = MessageFilterSettings(rules: [r]);
    MessageFilterRule? match(String room) => settings.match(
        roomId: room, text: "cat", senderName: null, isOwn: false, isDm: false);
    expect(match("!a:x"), isNotNull);
    expect(match("!b:x"), isNull);
  });

  test("own messages, DMs and sender names", () {
    final settings = MessageFilterSettings(rules: [rule("bob")]);
    MessageFilterRule? match(MessageFilterSettings s,
            {bool own = false, bool dm = false, String text = "bob"}) =>
        s.match(
            roomId: "!a:x",
            text: text,
            senderName: "Bob",
            isOwn: own,
            isDm: dm);
    expect(match(settings, own: true), isNull);
    expect(match(settings, dm: true), isNull);
    expect(match(settings.copyWith(skipOwnAndDms: false), dm: true), isNotNull);
    expect(match(settings, text: "hello"), isNotNull);
    expect(match(settings.copyWith(matchSenderNames: false), text: "hello"),
        isNull);
  });

  test("settings round-trip through account data", () {
    final settings = MessageFilterSettings(rules: [
      rule("cat"),
      rule("/x+/").withRooms(["!a:x"])
    ], display: FilteredMessageDisplay.nothing, noNotifications: false);
    final back = MessageFilterSettings.parse(settings.toJson());
    expect(back.rules.map((r) => r.label), ["cat", "/x+/i"]);
    expect(back.rules[1].rooms, ["!a:x"]);
    expect(back.display, FilteredMessageDisplay.nothing);
    expect(back.noNotifications, isFalse);
    expect(back.skipOwnAndDms, isTrue);
  });
}
