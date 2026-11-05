// Vommet issue 168: with UnifiedPush on and several distributor apps
// installed but none chosen, no notifications arrived and nothing said so.
// The startup check now asks the user exactly when it can't choose alone.

import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ntfy = "io.heckel.ntfy";
  const sunup = "org.unifiedpush.distributor.sunup";
  const gcompat = "org.unifiedpush.distributor.gcompat";

  test("several installed and none chosen: asks", () {
    expect(UnifiedPushNotifier.needsChoice([ntfy, sunup], null), isTrue);
    expect(UnifiedPushNotifier.needsChoice([ntfy, sunup], ""), isTrue);
  });

  test("chosen one uninstalled, several others installed: asks", () {
    expect(UnifiedPushNotifier.needsChoice([ntfy, sunup], gcompat), isTrue);
  });

  test("chosen one still installed: doesn't ask", () {
    expect(UnifiedPushNotifier.needsChoice([ntfy, sunup], sunup), isFalse);
  });

  test("only one installed: the startup check uses it, doesn't ask", () {
    expect(UnifiedPushNotifier.needsChoice([ntfy], null), isFalse);
    expect(UnifiedPushNotifier.needsChoice([ntfy], gcompat), isFalse);
  });

  test("none installed: doesn't ask (Settings › Notifications says so)", () {
    expect(UnifiedPushNotifier.needsChoice([], null), isFalse);
    expect(UnifiedPushNotifier.needsChoice([], ntfy), isFalse);
  });
}
