// Gate-only proof renders of the real LoginPageView (not committed).
import 'package:commet/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'render_png.dart';

void main() {
  setUp(() => GlobalConfig.data = {});

  Future<void> shot(
      WidgetTester tester, Size size, double keyboard, String name) async {
    await loadRenderFonts(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        theme: ThemeDark.theme,
        home: LoginPageView(
          isLoggingIn: false,
          flows: [MatrixPasswordLoginFlow()],
          hasPasswordSupport: true,
          onCreateAccount: () async => null,
        ),
      ),
    ));
    await tester.pump();
    tester.takeException();
    await emitRender(tester, find.byType(MaterialApp), name, pixelRatio: 1);
    final login = find.text("Login");
    final scroll = find.ancestor(of: login, matching: find.byType(Scrollable));
    if (scroll.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(login, 50, scrollable: scroll.first);
      await tester.pump();
      tester.takeException();
      await emitRender(tester, find.byType(MaterialApp), "$name-scrolled",
          pixelRatio: 1);
    }
  }

  testWidgets("render login", (tester) async {
    const tag = "login";
    await shot(tester, const Size(320, 640), 260, "$tag-320x640-kb260");
    await shot(tester, const Size(390, 844), 0, "$tag-390x844");
    await shot(tester, const Size(1280, 800), 0, "$tag-1280x800");
  });
}
