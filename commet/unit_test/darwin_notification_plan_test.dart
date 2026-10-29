import 'package:commet/client/components/push_notification/darwin/darwin_notifier.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:test/test.dart';

MessageNotificationContent message({bool isDirectMessage = false}) =>
    MessageNotificationContent(
        senderName: "Alex",
        senderId: "@alex:example.org",
        roomName: "Garden club",
        content: "See you at noon",
        eventId: r"$event1",
        roomId: "!room:example.org",
        clientId: "client-a",
        isDirectMessage: isDirectMessage);

void main() {
  test("room messages show the room as the subtitle", () {
    final plan = DarwinNotificationPlan.of(message())!;
    expect(plan.title, "Alex");
    expect(plan.subtitle, "Garden club");
    expect(plan.body, "See you at noon");
    expect(plan.threadId,
        DarwinNotificationPlan.roomKey("client-a", "!room:example.org"));
  });

  test("direct messages have no subtitle", () {
    final plan = DarwinNotificationPlan.of(message(isDirectMessage: true))!;
    expect(plan.subtitle, isNull);
  });

  test("tapping a message opens its room", () {
    final plan = DarwinNotificationPlan.of(message())!;
    final target = DarwinNotificationPlan.openTarget(plan.payload)!;
    expect(target.roomId, "!room:example.org");
    expect(target.clientId, "client-a");
  });

  test("ids are stable and fit in 32 bits", () {
    final a = DarwinNotificationPlan.of(message())!;
    final b = DarwinNotificationPlan.of(message())!;
    expect(a.id, b.id);
    expect(a.id, inInclusiveRange(0, 0x7fffffff));
  });

  test("calls open their room", () {
    final plan = DarwinNotificationPlan.of(CallNotificationContent(
        roomId: "!room:example.org",
        senderId: "@alex:example.org",
        senderName: "Alex",
        roomName: "Garden club",
        clientId: "client-a",
        callId: "call1",
        isDirectMessage: false,
        title: "Incoming call",
        content: "Alex is calling"))!;
    expect(plan.title, "Garden club");
    expect(DarwinNotificationPlan.openTarget(plan.payload)?.roomId,
        "!room:example.org");
  });

  test("bad payloads open nothing", () {
    expect(DarwinNotificationPlan.openTarget(null), isNull);
    expect(DarwinNotificationPlan.openTarget(""), isNull);
    expect(DarwinNotificationPlan.openTarget("not json"), isNull);
    expect(DarwinNotificationPlan.openTarget('{"room_id": 3}'), isNull);
  });
}
