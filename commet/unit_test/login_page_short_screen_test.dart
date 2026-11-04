import 'package:commet/config/global_config.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The login card on a small phone: with the keyboard open (or a short
// screen) it must scroll, not overflow. The Android smoke emulator is
// 320x640 and hit "A RenderFlex overflowed by 14 pixels on the bottom" here.
void main() {
  setUp(() => GlobalConfig.data = {});

  Widget page() => MaterialApp(
        home: LoginPageView(
          isLoggingIn: false,
          hasPasswordSupport: true,
          onCreateAccount: () async => null,
        ),
      );

  Future<void> phone(WidgetTester tester, Size size,
      {double keyboard = 0}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
  }

  Future<void> expectLoginReachable(WidgetTester tester) async {
    final button = find.text("Login");
    await tester.scrollUntilVisible(button, 50,
        scrollable:
            find.ancestor(of: button, matching: find.byType(Scrollable)).first);
    await tester.pump();
    final rect = tester.getRect(button);
    final screen = Offset.zero & tester.view.physicalSize;
    expect(screen.contains(rect.center), isTrue,
        reason: "the Login button can be brought on screen");
  }

  testWidgets("phone with the keyboard open: no overflow, Login reachable",
      (tester) async {
    await phone(tester, const Size(320, 640), keyboard: 260);
    await tester.pumpWidget(page());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLoginReachable(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets("short screen: no overflow, Login reachable", (tester) async {
    await phone(tester, const Size(320, 380));
    await tester.pumpWidget(page());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLoginReachable(tester);
  });
}
