import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> entry(
    String id, {
    String type = "m.room.message",
    int since = 1000,
    int delay = 0,
  }) =>
      {
        "delay_id": id,
        "room_id": "!a:x",
        "type": type,
        "delay": delay,
        "running_since": since,
        "content": {"msgtype": "m.text", "body": id},
      };

  test("parse keeps messages only, soonest first", () {
    final items = ScheduledMessages.parse({
      "delayed_events": [
        entry("late", delay: 5000),
        entry("soon", delay: 100),
        entry("enc", type: "m.room.encrypted", delay: 2000),
        {...entry("state"), "state_key": "@me:x"},
        entry("member", type: "org.matrix.msc3401.call.member"),
        {...entry("bad"), "delay": "soon"},
        {...entry("nocontent"), "content": null},
        "junk",
      ],
      "next_batch": "b",
    });
    expect(items.map((m) => m.delayId), ["soon", "enc", "late"]);
    expect(items[1].encrypted, isTrue);
    expect(items.first.encrypted, isFalse);
    expect(items.last.sendAt, DateTime.fromMillisecondsSinceEpoch(6000));
    expect(items.first.content["body"], "soon");
  });

  test("parse tolerates missing or wrong answers", () {
    expect(ScheduledMessages.parse(null), isEmpty);
    expect(ScheduledMessages.parse({"delayed_events": "nope"}), isEmpty);
    expect(ScheduledMessages.parse([]), isEmpty);
  });

  test("contentFor adds the reply relation without touching the original", () {
    final content = {"msgtype": "m.text", "body": "hi"};
    final reply = ScheduledMessages.contentFor(
      content,
      inReplyToEventId: "\$e",
    );
    expect(reply["m.relates_to"], {
      "m.in_reply_to": {"event_id": "\$e"},
    });
    expect(content.containsKey("m.relates_to"), isFalse);
    expect(ScheduledMessages.contentFor(content), content);
  });

  test("describeError maps the homeserver's errors", () {
    final far = ScheduledMessages.describeError({
      "errcode": "M_MAX_DELAY_EXCEEDED",
      "max_delay": 86400000,
    });
    expect(far.message, ScheduledMessages.scheduleErrorTooFar);
    expect(far.maxDelay, const Duration(days: 1));
    expect(
      ScheduledMessages.describeError({"errcode": "M_UNRECOGNIZED"}).message,
      ScheduledMessages.scheduleErrorUnsupported,
    );
    expect(
      ScheduledMessages.describeError({
        "errcode": "M_FORBIDDEN",
        "error": "No",
      }).message,
      "No",
    );
    expect(ScheduledMessages.describeError({"errcode": "M_X"}).message, "M_X");
  });

  group("presets", () {
    test("weekday morning", () {
      final now = DateTime(2026, 10, 26, 10); // Monday
      expect(ScheduledMessages.presets(now), [
        DateTime(2026, 10, 26, 11),
        DateTime(2026, 10, 26, 18),
        DateTime(2026, 10, 27, 9),
        DateTime(2026, 11, 2, 9),
      ]);
    });

    test("Sunday evening: tomorrow and Monday are the same, evening moves", () {
      final now = DateTime(2026, 11, 1, 20); // Sunday
      expect(ScheduledMessages.presets(now), [
        DateTime(2026, 11, 1, 21),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 2, 18),
      ]);
    });

    test("18:00 today is skipped less than half an hour ahead", () {
      final now = DateTime(2026, 10, 28, 17, 40); // Wednesday
      expect(ScheduledMessages.presets(now), [
        DateTime(2026, 10, 28, 18, 40),
        DateTime(2026, 10, 29, 9),
        DateTime(2026, 10, 29, 18),
        DateTime(2026, 11, 2, 9),
      ]);
    });
  });
}
