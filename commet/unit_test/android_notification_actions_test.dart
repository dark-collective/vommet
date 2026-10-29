import 'package:commet/client/components/push_notification/android/android_notification_actions.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 603: Reply / Mark as read action ids carry the chat.
void main() {
  test('action ids round-trip', () {
    for (final name in [
      AndroidNotificationActions.reply,
      AndroidNotificationActions.markRead
    ]) {
      final id = AndroidNotificationActions.actionId(name,
          clientId: "account-1",
          roomId: "!room:example.org",
          eventId: "\$event:example.org");
      final action = AndroidNotificationActions.parse(id)!;
      expect(action.action, name);
      expect(action.clientId, "account-1");
      expect(action.roomId, "!room:example.org");
      expect(action.eventId, "\$event:example.org");
    }
  });

  test('a notification from the background client names the account', () {
    final id = AndroidNotificationActions.actionId(
        AndroidNotificationActions.markRead,
        clientId: "background_matrix_client:account-1",
        roomId: "!room:example.org",
        eventId: "\$event:example.org");
    expect(AndroidNotificationActions.parse(id)!.clientId, "account-1");
  });

  test('other action ids are not ours', () {
    expect(AndroidNotificationActions.parse(null), isNull);
    expect(AndroidNotificationActions.parse("accept_call"), isNull);
    expect(
        AndroidNotificationActions.parse(
            "vommet-notification-action://reply?room_id=x"),
        isNull);
  });
}
