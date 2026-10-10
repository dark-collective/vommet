// UnifiedPush at startup: which distributor to register with again. A setup
// from an older build stayed broken until UnifiedPush was toggled off and on.

import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ntfy = "io.heckel.ntfy";
  const gcompat = "org.unifiedpush.distributor.gcompat";

  test("keeps the saved distributor while it's installed", () {
    expect(UnifiedPushNotifier.startupDistributor([ntfy, gcompat], gcompat),
        gcompat);
  });

  test("nothing saved, one installed: uses it", () {
    expect(UnifiedPushNotifier.startupDistributor([ntfy], null), ntfy);
    expect(UnifiedPushNotifier.startupDistributor([ntfy], ""), ntfy);
  });

  test("saved one uninstalled, one other installed: uses that", () {
    expect(UnifiedPushNotifier.startupDistributor([ntfy], gcompat), ntfy);
  });

  test("several installed and none saved: leaves the choice to the user", () {
    expect(
        UnifiedPushNotifier.startupDistributor([ntfy, gcompat], null), isNull);
  });

  test("none installed: nothing to register with", () {
    expect(UnifiedPushNotifier.startupDistributor([], ntfy), isNull);
  });

  test("unread-count pushes are recognised, message pushes are not", () {
    expect(
        UnifiedPushNotifier.isCountOnlyPush({
          "counts": {"unread": 0},
          "devices": [
            {"app_id": "im.nether.chat", "pushkey": "k"}
          ],
        }),
        isTrue);
    expect(
        UnifiedPushNotifier.isCountOnlyPush({
          "event_id": r"$e",
          "room_id": "!r:example.org",
          "counts": {"unread": 1},
        }),
        isFalse);
    expect(UnifiedPushNotifier.isCountOnlyPush({"prio": "high"}), isFalse);
  });
}
