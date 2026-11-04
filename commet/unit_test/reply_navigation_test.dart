import 'package:commet/utils/reply_navigation.dart';
import 'package:test/test.dart';

// Newest first, like Timeline.events. "s" = state event, can't be replied to.
const events = ["m4", "s3", "m2", "m1", "s0"];

String? step(String? current, {required bool older}) =>
    ReplyNavigation.step<String>(events, current,
        older: older,
        canReply: (event) => event.startsWith("m"),
        id: (event) => event);

void main() {
  group("Ctrl+Up (older)", () {
    test("with no reply, picks the newest message", () {
      expect(step(null, older: true), "m4");
    });

    test("moves to the next older message, skipping others", () {
      expect(step("m4", older: true), "m2");
      expect(step("m2", older: true), "m1");
    });

    test("stays on the oldest loaded message", () {
      expect(step("m1", older: true), "m1");
    });

    test("a target that's no longer loaded starts from the newest", () {
      expect(step("gone", older: true), "m4");
    });
  });

  group("Ctrl+Down (newer)", () {
    test("moves to the next newer message", () {
      expect(step("m1", older: false), "m2");
      expect(step("m2", older: false), "m4");
    });

    test("past the newest message stops replying", () {
      expect(step("m4", older: false), isNull);
    });

    test("with no reply does nothing", () {
      expect(step(null, older: false), isNull);
    });
  });

  test("an empty timeline never picks anything", () {
    expect(
        ReplyNavigation.step<String>([], null,
            older: true, canReply: (_) => true, id: (e) => e),
        isNull);
  });

  test("matches by id, not identity", () {
    final list = [
      (id: "b", n: 1),
      (id: "a", n: 1),
    ];
    final next = ReplyNavigation.step(list, (id: "b", n: 2),
        older: true, canReply: (_) => true, id: (e) => e.id);
    expect(next?.id, "a");
  });
}
