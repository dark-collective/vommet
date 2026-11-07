import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 693: which lines of a room's notification are "New message"
// placeholders that the decrypted message may replace.
void main() {
  const roomId = "!room:example.org";
  final time = DateTime(2026, 10, 24);

  test("a placeholder is sent as the room itself", () {
    final message = Message(AndroidNotifier.pushFallbackNewMessage, time,
        const Person(name: "Room", key: roomId));
    expect(AndroidNotifier.isFallbackMessage(message, roomId), isTrue);
  });

  test("a real message is not a placeholder, whatever it says", () {
    final message = Message(AndroidNotifier.pushFallbackNewMessage, time,
        const Person(name: "Alice", key: "@alice:example.org"));
    expect(AndroidNotifier.isFallbackMessage(message, roomId), isFalse);
  });

  test("another room's placeholder doesn't count", () {
    final message = Message(AndroidNotifier.pushFallbackNewMessage, time,
        const Person(name: "Other", key: "!other:example.org"));
    expect(AndroidNotifier.isFallbackMessage(message, roomId), isFalse);
  });

  test("without a person key, the placeholder text decides", () {
    expect(
        AndroidNotifier.isFallbackMessage(
            Message(AndroidNotifier.pushFallbackNewMessage, time,
                const Person(name: "Room")),
            roomId),
        isTrue);
    expect(
        AndroidNotifier.isFallbackMessage(
            Message("hello", time, const Person(name: "Room")), roomId),
        isFalse);
  });
}
