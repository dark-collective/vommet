// Vommet (chat navigation): the @ and ♥ buttons above "Jump to latest" lead
// to unread mentions and to my messages with new reactions, oldest first.
import 'package:commet/ui/molecules/room_timeline_widget/unread_jump_targets.dart';
import 'package:flutter_test/flutter_test.dart';

const me = "@me:example.org";
const them = "@them:example.org";

JumpScanEvent msg(String id, {String sender = them, bool mention = false}) =>
    JumpScanEvent(eventId: id, senderId: sender, mentionsMe: mention);

JumpScanEvent react(String id, String on, {String sender = them}) =>
    JumpScanEvent(eventId: id, senderId: sender, reactsTo: on);

UnreadJumpTargets scan(List<JumpScanEvent> newestFirst,
    {String? readUpTo = "read", Set<String> seen = const {}, int? limit}) {
  final senders = {for (final e in newestFirst) e.eventId: e.senderId};
  return UnreadJumpTargets.scan(newestFirst,
      me: me,
      readUpTo: readUpTo,
      senderOf: (id) => senders[id],
      seen: seen,
      limit: limit ?? UnreadJumpTargets.scanLimit);
}

void main() {
  test("mentions after the read marker, oldest first", () {
    final targets = scan([
      msg("m3", mention: true),
      msg("plain"),
      msg("m2", mention: true),
      msg("read"),
      msg("m1", mention: true),
    ]);
    expect(targets.mentions.map((t) => t.eventId), ["m2", "m3"]);
    expect(targets.reactions, isEmpty);
  });

  test("new reactions from others on my messages, one per message", () {
    final targets = scan([
      react("r4", "mine2", sender: me),
      react("r3", "mine1"),
      react("r2", "theirs"),
      react("r1", "mine2"),
      msg("mine2", sender: me),
      msg("theirs"),
      msg("read"),
      msg("mine1", sender: me),
    ]);
    expect(targets.reactions, const [
      JumpTarget("mine2", {"r1"}),
      JumpTarget("mine1", {"r3"}),
    ]);
  });

  test("seen events stay out, and a newer reaction brings a message back", () {
    final events = [
      react("r2", "mine"),
      msg("m1", mention: true),
      react("r1", "mine"),
      msg("mine", sender: me),
      msg("read"),
    ];
    expect(scan(events, seen: {"m1", "mine", "r1", "r2"}).isEmpty, isTrue);
    expect(scan(events, seen: {"m1", "mine", "r1"}).reactions, const [
      JumpTarget("mine", {"r2"})
    ]);
  });

  test("my own mentions don't count", () {
    expect(scan([msg("m", sender: me, mention: true), msg("read")]).isEmpty,
        isTrue);
  });

  test("no read marker means nothing to jump to", () {
    expect(scan([msg("m", mention: true)], readUpTo: null).isEmpty, isTrue);
  });

  test("an unloaded read marker scans up to the limit", () {
    final targets = scan([
      msg("m3", mention: true),
      msg("m2", mention: true),
      msg("m1", mention: true),
    ], readUpTo: "not-loaded", limit: 2);
    expect(targets.mentions.map((t) => t.eventId), ["m2", "m3"]);
  });
}
