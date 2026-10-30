import 'package:commet/client/components/push_notification/modifiers/redacted_mode.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 473: system notifications follow redacted mode.

const _image = AssetImage("avatar.png");

MessageNotificationContent message({bool dm = false}) =>
    MessageNotificationContent(
      senderName: "Alice Liddell",
      senderId: "@alice:example.org",
      roomName: dm ? "Alice Liddell" : "Wonderland",
      content: "meet me at the tea party",
      formattedContent: "meet me at the <b>tea party</b>",
      formatType: "org.matrix.custom.html",
      eventId: "\$e",
      roomId: "!r:example.org",
      clientId: "c",
      isDirectMessage: dm,
      senderImage: _image,
      senderImageId: "mxc://example.org/a",
      roomImage: _image,
      roomImageId: "mxc://example.org/r",
      attachedImage: _image,
      accountLabel: "@me:example.org",
    );

CallNotificationContent call() => CallNotificationContent(
      roomId: "!r:example.org",
      senderId: "@alice:example.org",
      senderName: "Alice Liddell",
      roomName: "Wonderland",
      clientId: "c",
      callId: "call",
      isDirectMessage: false,
      title: "Incoming Call! (Wonderland)",
      content: "Alice Liddell is calling!",
      senderImage: _image,
      roomImage: _image,
    );

NotificationModifierRedacted modifier(RedactionSettings settings) =>
    NotificationModifierRedacted(
        policy: () async => RedactionPolicy(settings, salt: [1, 2, 3]));

void main() {
  test('redaction off: the notification is untouched', () async {
    final out = await modifier(RedactionSettings.off).process(message())
        as MessageNotificationContent;
    expect(out.redacted, isFalse);
    expect(out.senderName, "Alice Liddell");
    expect(out.roomName, "Wonderland");
    expect(out.content, "meet me at the tea party");
    expect(out.formattedContent, isNotNull);
    expect(out.senderImage, isNotNull);
    expect(out.accountLabel, "@me:example.org");
  });

  test('names, room name and text follow the switches; no pictures', () async {
    const settings = RedactionSettings(
        names: NameRedaction.hide,
        avatars: true,
        text: TextRedaction.hide,
        roomNames: true);
    final out = await modifier(settings).process(message())
        as MessageNotificationContent;
    final text =
        [out.title, out.roomName, out.content, out.accountLabel].join(" ");

    expect(out.redacted, isTrue);
    for (final secret in ["Alice", "Wonderland", "tea", "party", "@me"]) {
      expect(text, isNot(contains(secret)));
    }
    expect(out.senderName, startsWith("User "));
    expect(out.roomName, startsWith("Room "));
    expect(out.content, isNot(contains(RegExp(r"[a-z]"))));
    expect(out.formattedContent, isNull);
    expect(out.formatType, isNull);
    expect(out.contentIsMarkup, isFalse);
    expect(out.senderImage, isNull);
    expect(out.senderImageId, isNull);
    expect(out.roomImage, isNull);
    expect(out.roomImageId, isNull);
    expect(out.attachedImage, isNull);
  });

  test('text kept, room names kept: only the names change', () async {
    const settings = RedactionSettings(names: NameRedaction.hide);
    final out = await modifier(settings).process(message())
        as MessageNotificationContent;
    expect(out.senderName, isNot(contains("Alice")));
    expect(out.roomName, "Wonderland");
    expect(out.content, "meet me at the tea party");
    // Still no picture while redacted mode is on.
    expect(out.attachedImage, isNull);
    expect(out.senderImage, isNull);
  });

  test('a direct message is named after the person', () async {
    const settings = RedactionSettings(names: NameRedaction.hide);
    final out = await modifier(settings).process(message(dm: true))
        as MessageNotificationContent;
    expect(out.roomName, out.senderName);
    expect(out.roomName, isNot(contains("Alice")));
  });

  test('incoming call: caller and room redacted in title and body', () async {
    const settings =
        RedactionSettings(names: NameRedaction.scramble, roomNames: true);
    final out =
        await modifier(settings).process(call()) as CallNotificationContent;
    for (final s in [out.title, out.content, out.senderName, out.roomName]) {
      expect(s, isNot(contains("Alice")));
      expect(s, isNot(contains("Wonderland")));
    }
    expect(out.title, contains(out.roomName));
    expect(out.content, contains(out.senderName));
    expect(out.senderImage, isNull);
    expect(out.roomImage, isNull);
    expect(out.redacted, isTrue);
  });
}
