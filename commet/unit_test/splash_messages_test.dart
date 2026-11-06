import 'dart:math';

import 'package:commet/config/splash_messages.dart';
import 'package:commet/ui/pages/splash/splash_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("splash messages are unique and free of broken characters", () {
    expect(splashMessages, isNotEmpty);
    expect(splashMessages.toSet().length, splashMessages.length);
    for (final message in splashMessages) {
      expect(message.trim(), isNotEmpty);
      expect(message.contains("�"), isFalse, reason: message);
    }
  });

  test("randomSplashMessage picks from the collection", () {
    final random = Random(1);
    for (var i = 0; i < 100; i++) {
      expect(splashMessages, contains(randomSplashMessage(random)));
    }
  });

  testWidgets("splash page shows the message", (tester) async {
    await tester.pumpWidget(const SplashPage(message: "Wait for it..."));
    expect(find.text("Wait for it..."), findsOneWidget);
  });
}
