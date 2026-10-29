import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';

/// Vommet issue 473: while redacted mode is on, system notifications go
/// through the same [RedactionPolicy] as the screen: names, room names and
/// text per the current switches, and no avatar or picture.
///
/// Runs after the in-app banner (which redacts itself on screen) and before
/// the Linux formatting modifier, so formatting only sees redacted text.
class NotificationModifierRedacted implements NotificationModifier {
  NotificationModifierRedacted({Future<RedactionPolicy> Function()? policy})
      : policy = policy ?? _currentPolicy;

  final Future<RedactionPolicy> Function() policy;

  static Future<RedactionPolicy> _currentPolicy() async {
    // A headless isolate (Android push, background service) keeps its own
    // copy of the preferences: re-read them so a switch made in the app
    // applies to the next notification.
    if (isHeadless) await Preference.preferences?.reload();
    return RedactionPolicy(preferences.effectiveRedaction);
  }

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    final redaction = await policy();
    if (redaction.isActive) apply(content, redaction);
    return content;
  }

  static void apply(NotificationContent content, RedactionPolicy redaction) {
    content.redacted = true;

    // The signed-in account's own Matrix ID, shown with several accounts.
    final account = content.accountLabel;
    if (account != null)
      content.accountLabel = redaction.name(account, account);

    switch (content) {
      case MessageNotificationContent c:
        c.roomName = redaction.roomName(c.roomName, c.roomId,
            dmPartnerId: c.isDirectMessage ? c.senderId : null);
        c.title = redaction.name(c.senderName, c.senderId);
        c.content = redaction.text(c.content);
        // The formatted body repeats the text, and its mention pills carry
        // names: notifications fall back to the redacted plain text.
        c.formattedContent = null;
        c.formatType = null;
        c.contentIsMarkup = false;
        c.senderImage = null;
        c.senderImageId = null;
        c.roomImage = null;
        c.roomImageId = null;
        c.attachedImage = null;
      case CallNotificationContent c:
        c.roomName = redaction.roomName(c.roomName, c.roomId,
            dmPartnerId: c.isDirectMessage ? c.senderId : null);
        c.senderName = redaction.name(c.senderName, c.senderId);
        c.title = CallManager.notificationTitleIncomingCall(c.roomName);
        c.content = CallManager.notificationContentUserIsCalling(c.senderName);
        c.senderImage = null;
        c.senderImageId = null;
        c.roomImage = null;
        c.roomImageId = null;
      default:
        // Invites and errors carry no names, only fixed text.
        break;
    }
  }
}
