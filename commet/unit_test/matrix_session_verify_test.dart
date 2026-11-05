import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

// Vommet issue 316: Verify on a session whose encryption keys aren't known
// threw a null check. Such sessions now show "Can't verify" instead, and
// nothing while the device list is still loading.

class _FakeClient extends Fake implements Client {}

Map<String, DeviceKeysList> ownList({required bool outdated}) => {
      "@me:example.org": DeviceKeysList("@me:example.org", _FakeClient())
        ..outdated = outdated
    };

MatrixSessionView session(
        {required bool verified,
        SessionKeysState keysState = SessionKeysState.known,
        Function? onVerify}) =>
    MatrixSessionView(
      deviceId: "ABCDEFGHIJ",
      displayName: "Some bot",
      verified: verified,
      keysState: keysState,
      beginVerification: onVerify,
    );

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group("knownSessionKeys", () {
    test("no keys before the device list is loaded", () {
      expect(knownSessionKeys({}, "@me:example.org", "ABCDEFGHIJ"), isNull);
    });

    test("no keys without a user id", () {
      expect(knownSessionKeys({}, null, "ABCDEFGHIJ"), isNull);
    });
  });

  group("sessionKeysState", () {
    test("loading before the device list is downloaded", () {
      expect(sessionKeysState({}, "@me:example.org", "ABCDEFGHIJ"),
          SessionKeysState.loading);
    });

    test("loading while the device list is being refreshed", () {
      expect(
          sessionKeysState(
              ownList(outdated: true), "@me:example.org", "ABCDEFGHIJ"),
          SessionKeysState.loading);
    });

    test("missing once a fresh device list doesn't have the session", () {
      expect(
          sessionKeysState(
              ownList(outdated: false), "@me:example.org", "ABCDEFGHIJ"),
          SessionKeysState.missing);
    });

    test("missing without a user id", () {
      expect(
          sessionKeysState({}, null, "ABCDEFGHIJ"), SessionKeysState.missing);
    });
  });

  // The whole row is laid out in the test host's default (desktop) layout;
  // the mobile layout puts the same verifyButton() row under the details,
  // so that is checked on its own too.
  final layouts = <String, Widget Function(MatrixSessionView)>{
    "session row": (view) => view,
    "verify button row": (view) => view.verifyButton(),
  };

  layouts.forEach((name, build) {
    group(name, () {
      testWidgets("unverified session with keys shows Verify", (tester) async {
        var tapped = 0;
        await pump(
            tester, build(session(verified: false, onVerify: () => tapped++)));

        expect(find.text("Verify"), findsOneWidget);
        expect(find.text("Can't verify"), findsNothing);
        await tester.tap(find.text("Verify"));
        expect(tapped, 1);
      });

      testWidgets("session without keys shows Can't verify and why",
          (tester) async {
        var tapped = 0;
        await pump(
            tester,
            build(session(
                verified: false,
                keysState: SessionKeysState.missing,
                onVerify: () => tapped++)));

        expect(find.text("Verify"), findsNothing);
        expect(find.text("Can't verify"), findsOneWidget);
        final tooltip = tester.widget<Tooltip>(find.ancestor(
            of: find.text("Can't verify"), matching: find.byType(Tooltip)));
        expect(tooltip.message, contains("hasn't shared its encryption keys"));
        expect(tooltip.triggerMode, TooltipTriggerMode.tap);

        await tester.tap(find.text("Can't verify"));
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining("hasn't shared its encryption keys"),
            findsOneWidget);
        expect(tapped, 0);
        await tester.pumpAndSettle(const Duration(seconds: 10));
      });

      testWidgets("session shows neither while its keys are loading",
          (tester) async {
        await pump(
            tester,
            build(
                session(verified: false, keysState: SessionKeysState.loading)));

        expect(find.text("Verify"), findsNothing);
        expect(find.text("Can't verify"), findsNothing);
      });

      testWidgets("verified session shows neither", (tester) async {
        await pump(tester, build(session(verified: true)));

        expect(find.text("Verify"), findsNothing);
        expect(find.text("Can't verify"), findsNothing);
      });
    });
  });
}
