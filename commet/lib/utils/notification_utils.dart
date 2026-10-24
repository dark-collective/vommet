import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/main.dart';

class NotificationUtils {
  /// Vommet: timed as a span (opt-in diagnostics); it folds over every
  /// space's rooms and runs on each badge update.
  static (int, int) getNotificationCounts() =>
      MainSpans.time("Notification_counts", _getNotificationCounts);

  static (int, int) _getNotificationCounts() {
    var highlightedNotificationCount = 0;
    var notificationCount = 0;

    var topLevelSpaces =
        clientManager!.spaces.where((e) => e.isTopLevel).toList();

    for (var i in topLevelSpaces) {
      highlightedNotificationCount += i.displayHighlightedNotificationCount;
      notificationCount += i.displayNotificationCount;
    }

    for (var dm in clientManager!.directMessages.highlightedRoomsList) {
      highlightedNotificationCount += dm.displayNotificationCount;
      notificationCount += dm.displayNotificationCount;
    }

    return (highlightedNotificationCount, notificationCount);
  }
}
