import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: Settings › Sessions shows when a session was last used in words,
// hides the dehydrated device, and renames sessions in place.

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group("sessionLastSeenLabel", () {
    final now = DateTime(2026, 10, 20, 15, 0);
    String label(DateTime seen) =>
        sessionLastSeenLabel(seen.millisecondsSinceEpoch, now);

    test("this device is always active now", () {
      expect(sessionLastSeenLabel(null, now, isThisDevice: true), "Active now");
    });
    test("never used", () {
      expect(sessionLastSeenLabel(null, now), "Never used");
    });
    test("minutes and hours today", () {
      expect(label(DateTime(2026, 10, 20, 14, 55)), "Active now");
      expect(label(DateTime(2026, 10, 20, 14, 30)), "Active 30 minutes ago");
      expect(label(DateTime(2026, 10, 20, 13, 50)), "Active an hour ago");
      expect(label(DateTime(2026, 10, 20, 9, 0)), "Active 6 hours ago");
    });
    test("yesterday, then weekday, then the date", () {
      expect(label(DateTime(2026, 10, 19, 23, 0)), "Yesterday");
      expect(label(DateTime(2026, 10, 16, 12, 0)), "Friday");
      expect(label(DateTime(2026, 3, 2, 12, 0)), "Mar 2, 2026");
    });
  });

  group("isDehydratedSession", () {
    test("by the dehydrated flag in its device keys", () {
      expect(
          isDehydratedSession(
              displayName: "Something", deviceKeys: {"dehydrated": true}),
          true);
    });
    test("by the name the SDKs give it", () {
      expect(isDehydratedSession(displayName: "Dehydrated device"), true);
      expect(isDehydratedSession(displayName: "Dehydrated Device"), true);
      expect(
          isDehydratedSession(
              displayName: "Offline box", sdkDisplayName: "Offline box"),
          true);
    });
    test("ordinary sessions are shown", () {
      expect(isDehydratedSession(displayName: "Laptop · Vommet"), false);
      expect(isDehydratedSession(displayName: null), false);
    });
  });

  group("session row", () {
    testWidgets("unnamed sessions say so", (tester) async {
      await pump(tester, const MatrixSessionView(deviceId: "ABCDEFGHIJ"));
      expect(find.text("Unnamed session"), findsOneWidget);
      expect(find.textContaining("ABCDEFGHIJ"), findsOneWidget);
    });

    testWidgets("verified state is written out", (tester) async {
      await pump(
          tester,
          const MatrixSessionView(
              deviceId: "ABCDEFGHIJ", displayName: "Phone", verified: true));
      expect(find.text("Verified"), findsOneWidget);

      await pump(
          tester,
          const MatrixSessionView(
              deviceId: "ABCDEFGHIJ", displayName: "Phone"));
      expect(find.text("Not verified"), findsOneWidget);
    });

    testWidgets("the menu offers rename, copy and sign out", (tester) async {
      var renaming = 0;
      await pump(
          tester,
          MatrixSessionView(
            deviceId: "ABCDEFGHIJ",
            displayName: "Phone",
            startRename: () => renaming++,
            rename: (_) async {},
            removeSession: () {},
          ));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text("Copy session ID"), findsOneWidget);
      expect(find.text("Sign out"), findsOneWidget);
      await tester.tap(find.text("Rename"));
      await tester.pumpAndSettle();
      expect(renaming, 1);
    });

    testWidgets("this device has no menu, only the rename pencil",
        (tester) async {
      await pump(
          tester,
          MatrixSessionView(
            deviceId: "ABCDEFGHIJ",
            displayName: "Laptop",
            isThisDevice: true,
            rename: (_) async {},
          ));
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.textContaining("Active now"), findsOneWidget);
    });

    testWidgets("Enter saves the new name", (tester) async {
      final saved = <String>[];
      await pump(
          tester,
          MatrixSessionView(
            deviceId: "ABCDEFGHIJ",
            displayName: "Phone",
            editing: true,
            rename: (name) async => saved.add(name),
          ));
      expect(find.text("Session names are visible to people you chat with."),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), "  Work PC  ");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saved, ["Work PC"]);
    });

    testWidgets("an unchanged or empty name cancels", (tester) async {
      final saved = <String>[];
      var cancelled = 0;
      await pump(
          tester,
          MatrixSessionView(
            deviceId: "ABCDEFGHIJ",
            displayName: "Phone",
            editing: true,
            rename: (name) async => saved.add(name),
            cancelRename: () => cancelled++,
          ));
      await tester.tap(find.text("Save"));
      await tester.pump();
      await tester.enterText(find.byType(TextField), "   ");
      await tester.tap(find.text("Save"));
      await tester.pump();
      expect(saved, isEmpty);
      expect(cancelled, 2);
    });

    testWidgets("Escape cancels", (tester) async {
      var cancelled = 0;
      await pump(
          tester,
          MatrixSessionView(
            deviceId: "ABCDEFGHIJ",
            displayName: "Phone",
            editing: true,
            rename: (_) async {},
            cancelRename: () => cancelled++,
          ));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, 1);
    });
  });
}
