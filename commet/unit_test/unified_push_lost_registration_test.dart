// Vommet issue 777: after some updates the UnifiedPush connector forgot its
// registration (no distributor saved, though an endpoint is), and the
// distributor kept the old registration next to the new one.

import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sunup = "org.unifiedpush.distributor.sunup";
  const endpoint = "https://push.example.org/wpush/v2/abc";

  test("no distributor saved but an endpoint is: the registration was lost",
      () {
    expect(UnifiedPushNotifier.lostRegistration(null, endpoint), isTrue);
    expect(UnifiedPushNotifier.lostRegistration("", endpoint), isTrue);
  });

  test("a saved distributor, or never registered: nothing lost", () {
    expect(UnifiedPushNotifier.lostRegistration(sunup, endpoint), isFalse);
    expect(UnifiedPushNotifier.lostRegistration(null, null), isFalse);
    expect(UnifiedPushNotifier.lostRegistration(null, ""), isFalse);
  });
}
