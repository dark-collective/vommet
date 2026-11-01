// Messages skipped by sliding sync while the app was away (Vommet,
// 2026-10-23).
//
// Tuwunel moves a room's position on a sliding sync connection as soon as a
// request collects the room, even one asking for no timeline
// (timeline_limit 0). The next response then sends only the newer events,
// with limited: false, and the ones in between never reach the app. The
// SDK now notices the gap (unread counts rising by more than the events
// that came, or a check when a suspect room is opened) and pages back
// across it.
//
// The app (user 1) syncs a room, stops, user 2 sends more messages than a
// sync sends per room, and a scripted request on the app's own connection
// collects the room with timeline_limit 0. Variants: nothing more is sent
// ("silent"), or user 2 sends two more ("post"). The app restarts from the
// same database and position and must show user 2's latest message and
// page back to all of them.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_4186_sliding_sync/msc_4186_sliding_sync.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("SYNCGAP $s");
}

/// More than a sync sends for a room in the list or subscribed (5 and 20).
const _skipped = 25;

void main() {
  for (final post in [false, true]) {
    final label = post ? "post" : "silent";
    testWidgets("sliding sync gap: $label", (tester) async {
      var app = await tester.setupApp();
      await preferences.experimentSlidingSync.set(true);
      await tester.pumpWidget(app);
      await tester.login(app);

      var appClient = app.clientManager.clients[0] as MatrixClient;
      var mx = appClient.getMatrixClient();
      final me = mx.userID!;

      final other = await tester.createTestClient(
        user: tester.userTwoName,
        password: tester.userTwoPassword,
      );
      addTearDown(other.dispose);
      await other.oneShotSync();

      final roomId = await other.createRoom(
        name: "Sync gap test $label",
        invite: [me],
        preset: matrix.CreateRoomPreset.privateChat,
      );
      await tester.waitFor(
        () => mx.getRoomById(roomId) != null,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true,
      );
      await mx.joinRoom(roomId);
      await tester.waitFor(
        () => mx.getRoomById(roomId)?.membership == matrix.Membership.join,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true,
      );
      await tester.waitFor(
        () => other.getRoomById(roomId) != null,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true,
      );
      final otherRoom = other.getRoomById(roomId)!;

      final sent = <String>[];
      for (var i = 1; i <= 3; i++) {
        sent.add((await otherRoom.sendTextEvent("before $i"))!);
      }
      await tester.waitFor(
        () =>
            mx.getRoomById(roomId)?.lastEvent?.eventId == sent.last &&
            mx.slidingSyncController.unreadCounts.serverCountsTrusted,
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true,
      );
      _log("[$label] app has the first messages");

      // Stop the sync loop after its current request (a long poll), so the
      // stored position is the newest one the server gave out.
      mx.backgroundSync = false;
      await tester.waitFor(
        () => !mx.syncPending,
        timeout: const Duration(seconds: 45),
        skipPumpAndSettle: true,
      );
      final token = SlidingSyncToken.tryParse(mx.prevBatch);
      expect(token?.pos, isNotNull, reason: "the app should use sliding sync");
      _log("[$label] app stopped at pos ${token!.pos} on ${token.conn}");

      for (var i = 1; i <= _skipped; i++) {
        sent.add((await otherRoom.sendTextEvent("away $i"))!);
      }

      // Another device of the same connection collects the room without a
      // timeline: the server moves the room's position past those messages.
      final response = await mx.postSlidingSync(
        SlidingSyncRequest(
          connId: token.conn ?? SlidingSyncController.connIds.first,
          pos: token.pos,
          timeout: 0,
          lists: {
            SlidingSyncController.listName: const SlidingSyncList(
              ranges: [(0, 49)],
              timelineLimit: 0,
              requiredState: [],
            ),
          },
          toDevice: false,
          e2ee: false,
          accountData: false,
          receipts: false,
          typing: false,
        ),
      );
      final pos = response["pos"] as String?;
      expect(pos, isNotNull);
      final stored = SlidingSyncToken(
        pos: pos,
        toDeviceSince: token.toDeviceSince,
        conn: token.conn,
      ).encode();
      await mx.database.storePrevBatch(stored);
      _log("[$label] scripted timeline_limit 0 request: pos $pos");

      if (post) {
        for (var i = 1; i <= 2; i++) {
          sent.add((await otherRoom.sendTextEvent("after $i"))!);
        }
      }
      final skipped = sent.skip(3).toList();

      app = await tester.restartApp();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      appClient = app.clientManager.clients[0] as MatrixClient;
      mx = appClient.getMatrixClient();

      // The first response after the restart.
      await tester.waitFor(
        () => mx.prevBatch != null && mx.prevBatch != stored,
        timeout: const Duration(seconds: 45),
        skipPumpAndSettle: true,
      );
      final gaps = mx.slidingSyncController.gaps;
      _log(
        "[$label] after restart: countGaps=${gaps.countGaps} "
        "suspect=${gaps.isSuspect(roomId)} "
        "preview=${mx.getRoomById(roomId)?.lastEvent?.body}",
      );

      final room = appClient.getRoom(roomId)!;
      final timeline = await room.getTimeline();
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      bool hasAll() =>
          skipped.every((id) => timeline.events.any((e) => e.eventId == id));
      while (!hasAll() && DateTime.now().isBefore(deadline)) {
        if (timeline.canLoadHistory && !timeline.isLoadingHistory) {
          await timeline.loadMoreHistory();
        }
        await tester.pump(const Duration(milliseconds: 300));
      }
      final missing = skipped
          .where((id) => !timeline.events.any((e) => e.eventId == id))
          .length;
      _log(
        "[$label] timeline: ${timeline.events.length} events, "
        "$missing of ${skipped.length} missing; checks=${gaps.checks} "
        "checkedGaps=${gaps.checkedGaps}",
      );

      expect(
        timeline.events.first.eventId,
        sent.last,
        reason: "the newest message should be user 2's latest",
      );
      expect(
        missing,
        0,
        reason: "scrolling back should reach every skipped message",
      );
      await tester.waitFor(
        () => mx.getRoomById(roomId)?.lastEvent?.eventId == sent.last,
        timeout: const Duration(seconds: 15),
        skipPumpAndSettle: true,
      );
      await timeline.close();
    });
  }
}
