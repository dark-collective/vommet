import 'package:commet/client/auth.dart';
import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:commet/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:commet/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The login card on a small phone: with the keyboard open (or a short
// screen) it must scroll, not overflow. The Android smoke emulator is
// 320x640 and hit "A RenderFlex overflowed by 14 pixels on the bottom" here.
// The 260 px keyboard is a typical phone keyboard; the smoke's 14 px comes
// from that emulator's own keyboard height.
void main() {
  setUp(() => GlobalConfig.data = {});

  // The flows as MatrixClient.getLoginFlows reports them: OIDC first when the
  // server has OAuth 2.0 metadata, then password, then one SSO flow per
  // identity provider of m.login.sso.
  final password = <LoginFlow>[MatrixPasswordLoginFlow()];
  final oidc = <LoginFlow>[
    MatrixOidcLoginFlow(),
    MatrixPasswordLoginFlow(),
    MatrixSSOLoginFlow(name: "homeserver", id: null),
  ];
  final sixProviders = <LoginFlow>[
    MatrixPasswordLoginFlow(),
    for (var i = 1; i <= 6; i++)
      MatrixSSOLoginFlow(id: "oidc-p$i", name: "Provider $i"),
  ];

  Widget page(List<LoginFlow> flows) => MaterialApp(
        home: LoginPageView(
          isLoggingIn: false,
          flows: flows,
          hasSsoSupport: flows.whereType<SsoLoginFlow>().isNotEmpty,
          hasOidcSupport: flows.whereType<OidcLoginFlow>().isNotEmpty,
          hasPasswordSupport: flows.whereType<PasswordLoginFlow>().isNotEmpty,
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

  // Scrolls [text] into view if it sits in a scroll view, then checks it is
  // above the keyboard.
  Future<void> expectReachable(WidgetTester tester, String text) async {
    final target = find.text(text);
    expect(target, findsOneWidget);
    final scrollable =
        find.ancestor(of: target, matching: find.byType(Scrollable));
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(target, 50, scrollable: scrollable.first);
      await tester.pump();
    }
    final visible = Offset.zero &
        Size(tester.view.physicalSize.width,
            tester.view.physicalSize.height - tester.view.viewInsets.bottom);
    expect(visible.contains(tester.getRect(target).center), isTrue,
        reason: "\"$text\" can be brought on screen above the keyboard");
  }

  final sizes = {
    "phone with the keyboard open": (const Size(320, 640), 260.0),
    "short screen": (const Size(320, 380), 0.0),
  };

  for (final MapEntry(key: name, value: (size, keyboard)) in sizes.entries) {
    testWidgets("$name: no overflow, Login reachable", (tester) async {
      await phone(tester, size, keyboard: keyboard);
      await tester.pumpWidget(page(password));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectReachable(tester, "Login");
      await expectReachable(tester, "Create an account");
      expect(tester.takeException(), isNull);
    });

    testWidgets("$name, OIDC: no overflow, Continue and sign-up reachable",
        (tester) async {
      await phone(tester, size, keyboard: keyboard);
      await tester.pumpWidget(page(oidc));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectReachable(tester, "Continue");
      await expectReachable(tester, "Create an account");
      expect(tester.takeException(), isNull);
    });

    testWidgets("$name, 6 SSO providers: no overflow, all reachable",
        (tester) async {
      await phone(tester, size, keyboard: keyboard);
      await tester.pumpWidget(page(sixProviders));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text("Login"), findsNothing);
      await expectReachable(tester, "Continue with Provider 6");
      await expectReachable(tester, "Create an account");
      expect(tester.takeException(), isNull);
    });

    testWidgets("$name, SSO with the password form open: Login reachable",
        (tester) async {
      await phone(tester, size, keyboard: keyboard);
      await tester.pumpWidget(page(sixProviders));
      await tester.pump();
      await expectReachable(tester, "Sign in with a password instead");
      await tester.tap(find.text("Sign in with a password instead"));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await expectReachable(tester, "Login");
      await expectReachable(tester, "Create an account");
      expect(tester.takeException(), isNull);
    });
  }

  // Where the card fits, it stays centered in the page and is not cut off.
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets("${size.width.toInt()}x${size.height.toInt()}: card centered",
        (tester) async {
      await phone(tester, size);
      await tester.pumpWidget(page(password));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final card = find.ancestor(
          of: find.text("Login"),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).boxShadow != null));
      expect(card, findsOneWidget);
      // The area loginField gets: the inner Scaffold's Material, padded 8.
      final area = tester
          .getRect(
              find.ancestor(of: card, matching: find.byType(Material)).first)
          .deflate(8);
      final rect = tester.getRect(card);
      expect((rect.center.dx - area.center.dx).abs(), lessThanOrEqualTo(2));
      expect((rect.center.dy - area.center.dy).abs(), lessThanOrEqualTo(2));
      expect(
          area.inflate(0.5).contains(rect.topLeft) &&
              area.inflate(0.5).contains(rect.bottomRight),
          isTrue,
          reason: "the card is not clipped");
    });
  }
}
