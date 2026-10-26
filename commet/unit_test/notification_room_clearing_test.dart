import 'package:commet/client/components/push_notification/android/android_notifier.dart';
import 'package:commet/client/components/push_notification/windows/windows_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 508: closing a room's notifications once it is read.
void main() {
  test('a room toast group is stable, short and per account and room', () {
    final a = WindowsNotifier.roomToastGroup("client-a", "!room:example.org");
    expect(a, WindowsNotifier.roomToastGroup("client-a", "!room:example.org"));
    expect(a.length, lessThanOrEqualTo(64));
    expect(a,
        isNot(WindowsNotifier.roomToastGroup("client-b", "!room:example.org")));
    expect(
        a,
        isNot(
            WindowsNotifier.roomToastGroup("client-a", "!other:example.org")));
    expect(
        WindowsNotifier.roomToastGroup(
                "client-a", "!${"x" * 300}:a.very.long.server.name.example.org")
            .length,
        lessThanOrEqualTo(64));
  });

  test('only message and mention channels count as a room\'s messages', () {
    expect(AndroidNotifier.isMessageChannel("messages"), isTrue);
    expect(AndroidNotifier.isMessageChannel("messages_1a2b"), isTrue);
    expect(AndroidNotifier.isMessageChannel("mentions_1a2b"), isTrue);
    expect(
        AndroidNotifier.isMessageChannel("incoming_calls_channel_1"), isFalse);
    expect(AndroidNotifier.isMessageChannel("chat_invites"), isFalse);
    expect(AndroidNotifier.isMessageChannel("errors"), isFalse);
    expect(AndroidNotifier.isMessageChannel(null), isFalse);
  });
}
