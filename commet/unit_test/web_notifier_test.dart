import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/web/web_notifier.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/web_notification_permission.dart';
import 'package:flutter_test/flutter_test.dart';

MessageNotificationContent message({bool direct = false}) =>
    MessageNotificationContent(
      senderName: "Alice",
      senderId: "@alice:example.org",
      roomName: "General",
      content: "hi",
      eventId: "\$e",
      roomId: "!r:example.org",
      clientId: "c",
      isDirectMessage: direct,
    );

void main() {
  // Vommet issue 767: browser notifications in the web app.
  group('WebNotificationPlan', () {
    test('room message: sender and room, opens the room, message sound', () {
      final plan = WebNotificationPlan.of(message())!;
      expect(plan.title, "Alice (General)");
      expect(plan.body, "hi");
      expect(plan.roomId, "!r:example.org");
      expect(plan.clientId, "c");
      expect(plan.eventId, "\$e");
      expect(plan.sound, SoundEvent.message);
      expect(
          plan.tag.startsWith(
              WebNotificationPlan.roomTagPrefix("c", "!r:example.org")),
          isTrue);
    });

    test('direct message: sender only', () {
      expect(WebNotificationPlan.of(message(direct: true))!.title, "Alice");
    });

    test('mention plays the mention sound; a silent rule plays none', () {
      final mention = message()..isMention = true;
      expect(WebNotificationPlan.of(mention)!.sound, SoundEvent.mention);
      final silent = message()..ruleSound = false;
      expect(WebNotificationPlan.of(silent)!.sound, isNull);
    });

    test('account label when several accounts are signed in', () {
      final m = message()..accountLabel = "@me:example.org";
      expect(WebNotificationPlan.of(m)!.title,
          "Alice (General) · @me:example.org");
    });

    test('each message has its own tag; rooms do not share a prefix', () {
      final a = WebNotificationPlan.of(message())!;
      final b = WebNotificationPlan.of(message()..eventId = "\$f")!;
      expect(a.tag, isNot(b.tag));
      expect(
          a.tag.startsWith(
              WebNotificationPlan.roomTagPrefix("c", "!r2:example.org")),
          isFalse);
    });

    test('invite opens Home', () {
      final plan = WebNotificationPlan.of(RoomInviteNotificationContent(
          title: "Room Invite",
          content: "Bob invited you to Lounge",
          clientId: "c",
          roomId: "!l:example.org",
          inviterName: "Bob",
          roomName: "Lounge"))!;
      expect(plan.roomId, isNull);
      expect(plan.body, "Bob invited you to Lounge");
    });

    test('call opens the room, without the message sound', () {
      final plan = WebNotificationPlan.of(CallNotificationContent(
          roomId: "!r:example.org",
          senderId: "@alice:example.org",
          senderName: "Alice",
          roomName: "General",
          clientId: "c",
          callId: "call1",
          isDirectMessage: false,
          title: "Incoming call",
          content: "Alice is calling"))!;
      expect(plan.roomId, "!r:example.org");
      expect(plan.title, "General");
      expect(plan.sound, isNull);
    });

    test('error notices are not shown', () {
      expect(
          WebNotificationPlan.of(
              ErrorNotificationContent(title: "x", content: "y")),
          isNull);
    });
  });

  group('WebNotificationPermission.shouldAsk', () {
    bool ask(
            {bool isWeb = true,
            String permission = "default",
            bool alreadyAsked = false,
            bool enabled = true}) =>
        WebNotificationPermission.shouldAsk(
            isWeb: isWeb,
            permission: permission,
            alreadyAsked: alreadyAsked,
            notificationsEnabled: enabled);

    test('asks once on the web while the browser has not been asked', () {
      expect(ask(), isTrue);
      expect(ask(alreadyAsked: true), isFalse);
    });

    test('not when already granted, blocked or unsupported', () {
      expect(ask(permission: "granted"), isFalse);
      expect(ask(permission: "denied"), isFalse);
      expect(ask(permission: "unsupported"), isFalse);
    });

    test('not off the web or with notifications turned off', () {
      expect(ask(isWeb: false), isFalse);
      expect(ask(enabled: false), isFalse);
    });
  });
}
