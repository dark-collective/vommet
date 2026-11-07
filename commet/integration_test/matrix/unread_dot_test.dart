// Tester report (10-08): the room list's "unread messages" dot is gone.
//
// The app (user 1) is in a room it has not opened; user 2, on its own client,
// sends messages there. The room's unread count (data) and the dot on its
// room-list row (screen) are checked and logged separately, so a failure
// says which side is wrong. Plain room and encrypted DM, and a plain room
// set to "Mentions only" (operator report 2026-11-03: Discord's rule keeps
// its dot; only the count is limited to mentions), and a muted plain room
// (no dot for a plain message, the red badge for a mention, which the server
// never counts as a highlight there).

import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("UNREAD $s");
}

/// Variant names are "<layout>: <room>", e.g. "phone: plain room". The
/// per-push suite runs the plain-room desktop and phone ones on Tuwunel; the
/// nightly Synapse workflow runs them all (sliding sync on Synapse needs
/// client-side unread counts, Vommet issue 112).
const variants = [
  (false, "desktop"),
  (true, "desktop"),
  (false, "phone"),
  (true, "phone"),
  (false, "phone+banners"),
  (false, "sliding sync"),
  (true, "sliding sync"),
];

void main() {
  // UNREAD_ONLY: ";"-separated name prefixes of the variants to run.
  registerVariants((Platform.environment["UNREAD_ONLY"] ?? "")
      .split(";")
      .where((p) => p.isNotEmpty)
      .toList());
}

void registerVariants(List<String> prefixes) {
  for (final (encrypted, layout, rule) in [
    for (final (encrypted, layout) in variants)
      (encrypted, layout, PushRule.notify),
    (false, "desktop", PushRule.mentionsOnly),
    (false, "desktop", PushRule.dontNotify),
  ]) {
    final mentionsOnly = rule == PushRule.mentionsOnly;
    final muted = rule == PushRule.dontNotify;
    final kind = mentionsOnly
        ? "mentions-only room"
        : muted
            ? "muted room mention"
            : (encrypted ? "encrypted DM" : "plain room");
    final name = "$layout: $kind";
    if (prefixes.isNotEmpty && !prefixes.any(name.startsWith)) continue;
    final label = name;
    testWidgets("unread dot: $label", (tester) async {
      final app = await tester.setupApp();
      if (layout == "sliding sync") {
        await preferences.experimentSlidingSync.set(true);
      }
      if (layout.startsWith("phone")) {
        await preferences.experimentBannerLayout.set(layout == "phone+banners");
        await preferences.layoutOverride.set("mobile");
        // Resize the real window: overriding tester.view only draws offscreen.
        final desktopSize = await windowManager.getSize();
        await windowManager.setSize(const Size(400, 700));
        addTearDown(() => windowManager.setSize(desktopSize));
      }
      await tester.pumpWidget(app);
      await tester.login(app);

      final appClient = app.clientManager.clients[0] as MatrixClient;
      final me = appClient.getMatrixClient().userID!;

      final other = await tester.createTestClient(
          user: tester.userTwoName, password: tester.userTwoPassword);
      await other.oneShotSync();

      final roomId = await other.createRoom(
        name: encrypted ? null : "Unread dot test",
        invite: [me],
        isDirect: encrypted,
        preset: encrypted
            ? matrix.CreateRoomPreset.trustedPrivateChat
            : matrix.CreateRoomPreset.privateChat,
        initialState: [
          if (encrypted)
            matrix.StateEvent(
                type: matrix.EventTypes.Encryption,
                content: {"algorithm": "m.megolm.v1.aes-sha2"}),
        ],
      );
      _log("[$label] created $roomId");

      await tester.waitFor(
          () => appClient.getMatrixClient().getRoomById(roomId) != null,
          timeout: const Duration(seconds: 30),
          skipPumpAndSettle: true);
      _log("[$label] invite reached the app");
      await appClient.getMatrixClient().joinRoom(roomId);
      await tester.waitFor(() => appClient.getRoom(roomId) != null,
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
      final room = appClient.getRoom(roomId)!;
      if (rule != PushRule.notify) {
        await room.setPushRule(rule);
        await tester.waitFor(() => room.pushRule == rule,
            timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
        _log("[$label] room set to $rule");
      }
      await tester.pumpAndSettle();

      await tester.waitFor(() => other.getRoomById(roomId) != null,
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
      final otherRoom = other.getRoomById(roomId)!;
      // Local notifications (Client.onNotification) need a non-zero count
      // too, so check they fire for the new messages.
      final notified = <String>[];
      final notificationSub = appClient
          .getMatrixClient()
          .onNotification
          .stream
          .where((e) => e.roomId == roomId)
          .listen((e) => notified.add(e.eventId));
      addTearDown(notificationSub.cancel);
      _log("[$label] app joined; sending");
      if (muted) {
        await _mutedMention(tester, label, room as MatrixRoom, otherRoom, me);
        await other.dispose();
        return;
      }
      for (var i = 1; i <= 2; i++) {
        await otherRoom.sendTextEvent("unread dot $i");
      }
      _log("[$label] sent 2 messages");

      // A mentions-only room gets no count and no notification here.
      if (!mentionsOnly) {
        try {
          await tester.waitFor(() => room.notificationCount > 0,
              timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
        } catch (_) {
          _log("[$label] notificationCount stayed 0 for 30 s");
        }
        try {
          await tester.waitFor(() => notified.isNotEmpty,
              timeout: const Duration(seconds: 15), skipPumpAndSettle: true);
        } catch (_) {
          _log("[$label] no onNotification for 15 s");
        }
      }
      await tester.pumpAndSettle();

      // The Home page stays built under any first-run screens, so look
      // offstage too.
      Finder rowFor(Room r) => find.byWidgetPredicate(
          (w) =>
              (w is RoomTextButton && w.room.identifier == r.identifier) ||
              (w is RoomPanel && w.room.identifier == r.identifier),
          skipOffstage: false);

      final rows = rowFor(room);
      final dots = find.descendant(
          of: rows,
          matching: find.byType(DotIndicator, skipOffstage: false),
          skipOffstage: false);
      final badges = find.descendant(
          of: rows,
          matching: find.byType(NotificationBadge, skipOffstage: false),
          skipOffstage: false);

      _log("[$label] data: notificationCount=${room.notificationCount} "
          "highlighted=${room.highlightedNotificationCount} "
          "pushRule=${room.pushRule} display=${room.displayNotificationCount} "
          "displayHighlighted=${room.displayHighlightedNotificationCount}");
      _log(
          "[$label] onstage rows=${find.byWidgetPredicate((w) => (w is RoomTextButton || w is RoomPanel) && (w as dynamic).room.identifier == room.identifier).evaluate().length}");
      _log("[$label] screen: rows=${rows.evaluate().length} "
          "dots=${dots.evaluate().length} badges=${badges.evaluate().length}");

      _log("[$label] onNotification: ${notified.length} event(s)");
      if (!mentionsOnly) {
        expect(notified, isNotEmpty,
            reason: "new messages should raise a local notification");
        expect(room.displayNotificationCount, greaterThan(0),
            reason: "the room should count as unread");
      }
      // Home refreshes Recent activity a second after a sync, and the full
      // rooms list only builds the rows on screen: with many rooms (the
      // full suite's account) the new room's row can take that second to
      // appear. Sliding sync's long-poll timing made the single check miss it.
      try {
        await tester.waitFor(() => rows.evaluate().isNotEmpty,
            timeout: const Duration(seconds: 10));
      } catch (_) {
        _log("[$label] no room-list row after 10 s");
      }
      expect(rows.evaluate(), isNotEmpty,
          reason: "the room should have a room-list row");
      if (mentionsOnly) {
        // Plain messages give no count here, so the dot must show.
        try {
          await tester.waitFor(() => dots.evaluate().isNotEmpty,
              timeout: const Duration(seconds: 15));
        } catch (_) {
          _log("[$label] no dot after 15 s");
        }
        expect(dots.evaluate(), isNotEmpty,
            reason: "a mentions-only room's row shows the unread dot");
      }
      expect(dots.evaluate().length + badges.evaluate().length, greaterThan(0),
          reason: "an unread room's row shows a dot or a count");

      await other.dispose();
    });
  }
}

/// A muted room: a plain message shows nothing, a mention the red badge.
Future<void> _mutedMention(WidgetTester tester, String label, MatrixRoom room,
    matrix.Room otherRoom, String me) async {
  final rows = find.byWidgetPredicate(
      (w) =>
          (w is RoomTextButton && w.room.identifier == room.identifier) ||
          (w is RoomPanel && w.room.identifier == room.identifier),
      skipOffstage: false);
  final dots = find.descendant(
      of: rows,
      matching: find.byType(DotIndicator, skipOffstage: false),
      skipOffstage: false);
  final badges = find.descendant(
      of: rows,
      matching: find.byType(NotificationBadge, skipOffstage: false),
      skipOffstage: false);
  void logState(String step) {
    _log("[$label] $step: server highlight_count="
        "${room.matrixRoom.highlightCount} "
        "notification_count=${room.matrixRoom.notificationCount} "
        "highlighted=${room.highlightedNotificationCount} "
        "rows=${rows.evaluate().length} dots=${dots.evaluate().length} "
        "badges=${badges.evaluate().length}");
  }

  final plainId = await otherRoom.sendTextEvent("muted plain");
  await tester.waitFor(() => room.matrixRoom.lastEvent?.eventId == plainId,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  await tester.pumpAndSettle();
  try {
    await tester.waitFor(() => rows.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
  } catch (_) {
    _log("[$label] no room-list row after 10 s");
  }
  logState("plain");
  expect(rows.evaluate(), isNotEmpty,
      reason: "the room should have a room-list row");
  expect((dots.evaluate().length, badges.evaluate().length), (0, 0),
      reason: "a muted room's plain message shows no dot and no badge");

  final mentionId = await otherRoom.sendEvent({
    "msgtype": "m.text",
    "body": "$me look",
    "m.mentions": {
      "user_ids": [me]
    },
  });
  await tester.waitFor(() => room.matrixRoom.lastEvent?.eventId == mentionId,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  try {
    await tester.waitFor(() => badges.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15));
  } catch (_) {
    _log("[$label] no badge after 15 s");
  }
  logState("mention");
  expect(room.highlightedNotificationCount, 1,
      reason: "the mention counts in the muted room");
  expect(badges.evaluate(), isNotEmpty,
      reason: "a muted room's row shows the mention badge");
  expect(dots.evaluate(), isEmpty, reason: "and no unread dot");
}
