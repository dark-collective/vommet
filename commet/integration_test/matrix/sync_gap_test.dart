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
//
// "own": the skipped messages are user 1's own, sent from another device
// (missed messages after a server outage, 2026-11-01). They don't raise
// the unread counts and the room isn't sent again, so only the check on
// the room's first open in the run finds them.
//
// "clear cache": Settings › Advanced › Clear cache, then a restart. The
// app must start without a position and download the room again.
//
// Follow-up (2026-11-02), in an encrypted DM:
// - "encrypted own": user 1's other device sends 5; they must decrypt (no
//   "unable to decrypt" tiles) and the room must read as read.
// - "encrypted below newer": 25 own skipped, then one of user 2's that
//   syncs; scrolling back reaches all of them, decrypted.
// - "failed echo": a message the app couldn't send (server unreachable)
//   stays through the skip, the restart and the fill, and Retry sends it
//   once. With "Send while offline" on, the app resends it by itself after
//   the restart, also once.
// - "encrypted clear cache": the messages come back and decrypt, because
//   Clear cache keeps the keys.

import 'dart:convert';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/clear_cache.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

/// One way the messages get skipped.
class _Variant {
  const _Variant(
    this.label, {
    this.post = 0,
    this.own = false,
    this.away = _skipped,
    this.encrypted = false,
    this.failedEcho = false,
    this.sendWhileOffline = false,
  });

  final String label;

  /// Messages user 2 sends after the skip; they reach the app normally.
  final int post;

  /// The skipped messages are user 1's own, from another device.
  final bool own;

  /// How many messages are skipped.
  final int away;

  /// An encrypted DM: every message shown must decrypt.
  final bool encrypted;

  /// The app fails to send a message before it stops.
  final bool failedEcho;

  /// The "Send while offline" experiment, which resends failed messages
  /// after a restart by itself.
  final bool sendWhileOffline;
}

const _variants = [
  _Variant("silent"),
  _Variant("post", post: 2),
  // Fewer than the check fetches, so they sit on top of a stored event. A
  // check sees fresh events (under a minute) as still on their way; while
  // the room stays open it checks once more when they're older than that.
  _Variant("own", own: true, away: 10),
  _Variant("encrypted own", own: true, away: 5, encrypted: true),
  _Variant("encrypted below newer", own: true, post: 1, encrypted: true),
  _Variant("failed echo", own: true, away: 10, failedEcho: true),
  _Variant(
    "failed echo, send while offline",
    own: true,
    away: 10,
    failedEcho: true,
    sendWhileOffline: true,
  ),
];

/// The failed echo's text.
const _offline = "sent while the server was unreachable";

/// Answers every message send with a server error, as a proxy in front of
/// a homeserver that is down does; everything else goes through.
class _SendsFail extends http.BaseClient {
  _SendsFail(this.inner);

  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == "PUT" && request.url.path.contains("/send/")) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('{"errcode":"M_UNKNOWN","error":"Bad gateway"}'),
        ),
        502,
        request: request,
      );
    }
    return inner.send(request);
  }
}

/// An encrypted DM with user 2, or a private room, joined by the app.
Future<String> _createRoom(
  WidgetTester tester,
  matrix.Client other,
  matrix.Client mx,
  String name, {
  required bool encrypted,
}) async {
  final roomId = await other.createRoom(
    name: name,
    invite: [mx.userID!],
    isDirect: encrypted,
    preset: encrypted
        ? matrix.CreateRoomPreset.trustedPrivateChat
        : matrix.CreateRoomPreset.privateChat,
    initialState: [
      if (encrypted)
        matrix.StateEvent(
          type: matrix.EventTypes.Encryption,
          content: {"algorithm": "m.megolm.v1.aes-sha2"},
        ),
    ],
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
  return roomId;
}

/// Whether every one of [ids] is in [timeline], decrypted. Logs what isn't.
bool _allDecrypted(Timeline timeline, List<String> ids, {String? log}) {
  var missing = 0, encrypted = 0;
  for (final id in ids) {
    final e = timeline.tryGetEvent(id);
    if (e == null) {
      missing++;
    } else if (e is! TimelineEventMessage || e.body == null) {
      encrypted++;
    }
  }
  if (log != null) {
    _log("$log: $missing missing, $encrypted not decrypted of ${ids.length}");
  }
  return missing == 0 && encrypted == 0;
}

/// Both of user 1's devices trust each other, and user 1's other device
/// and user 2 share room keys with every device. The account may have
/// cross-signing from an earlier test whose keys no device here has, and
/// the default (cross-verified devices only) would then withhold them.
Future<void> _trustEachOther(
  WidgetTester tester,
  matrix.Client mx,
  matrix.Client second,
  matrix.Client other,
) async {
  final me = mx.userID!;
  second.shareKeysWith = matrix.ShareKeysWith.all;
  other.shareKeysWith = matrix.ShareKeysWith.all;
  await second.updateUserDeviceKeys(additionalUsers: {me});
  await mx.updateUserDeviceKeys(additionalUsers: {me});
  await tester.waitFor(
    () =>
        second.userDeviceKeys[me]?.deviceKeys[mx.deviceID] != null &&
        mx.userDeviceKeys[me]?.deviceKeys[second.deviceID] != null,
    timeout: const Duration(seconds: 30),
    skipPumpAndSettle: true,
  );
  await second.userDeviceKeys[me]!.deviceKeys[mx.deviceID]!.setVerified(true);
  await mx.userDeviceKeys[me]!.deviceKeys[second.deviceID]!.setVerified(true);
}

void main() {
  for (final v in _variants) {
    final label = v.label;
    testWidgets("sliding sync gap: $label", (tester) async {
      var app = await tester.setupApp();
      await preferences.experimentSlidingSync.set(true);
      if (v.failedEcho) {
        await preferences.experimentOfflineSending.set(v.sendWhileOffline);
      }
      await tester.pumpWidget(app);
      await tester.login(app);

      var appClient = app.clientManager.clients[0] as MatrixClient;
      var mx = appClient.getMatrixClient();

      final other = await tester.createTestClient(
        user: tester.userTwoName,
        password: tester.userTwoPassword,
      );
      addTearDown(other.dispose);
      await other.oneShotSync();

      final roomId = await _createRoom(
        tester,
        other,
        mx,
        "Sync gap test $label",
        encrypted: v.encrypted,
      );
      final otherRoom = other.getRoomById(roomId)!;

      // "own": user 1's other device sends the skipped messages.
      var awayRoom = otherRoom;
      if (v.own) {
        final second = await tester.createTestClient(
          user: tester.username,
          password: tester.password,
        );
        addTearDown(second.dispose);
        await second.oneShotSync();
        awayRoom = second.getRoomById(roomId)!;
        if (v.encrypted) await _trustEachOther(tester, mx, second, other);
      }

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

      // "failed echo": the app sends while the server is unreachable.
      String? failedTxn;
      if (v.failedEcho) {
        final real = mx.httpClient;
        mx.httpClient = _SendsFail(real);
        final result = await mx.getRoomById(roomId)!.sendTextEvent(_offline);
        mx.httpClient = real;
        expect(result, isNull, reason: "the send fails");
        final echo = await mx.database.getEventList(mx.getRoomById(roomId)!);
        final failed = echo.firstWhere(
          (e) => e.body == _offline && e.status == matrix.EventStatus.error,
        );
        failedTxn = failed.eventId;
        _log("[$label] failed echo $failedTxn");
      }

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

      for (var i = 1; i <= v.away; i++) {
        sent.add((await awayRoom.sendTextEvent("away $i"))!);
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

      for (var i = 1; i <= v.post; i++) {
        sent.add((await otherRoom.sendTextEvent("after $i"))!);
      }
      final skipped = sent.skip(3).take(v.away).toList();

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

      final room = appClient.getRoom(roomId)! as MatrixRoom;
      final timeline = await room.getTimeline();
      // Up to a minute for the "own" re-check, then paging.
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      bool hasAll() =>
          skipped.every((id) => timeline.events.any((e) => e.eventId == id));
      // Own messages are found by the check on open: scroll back once the
      // newest one shows, as a user would. A history page asked for while
      // the fill runs reaches the room's start below the gap (an SDK race,
      // see REPORT-FOLLOWUP). The others are found by scrolling back.
      bool canPage() =>
          !v.own || timeline.events.any((e) => e.eventId == skipped.last);
      while (!hasAll() && DateTime.now().isBefore(deadline)) {
        if (canPage() &&
            timeline.canLoadHistory &&
            !timeline.isLoadingHistory) {
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

      for (final e in timeline.events.take(3)) {
        final mxe = (e as MatrixTimelineEvent).event;
        _log(
          "[$label] top: ${mxe.eventId} ${mxe.type} ${mxe.status.name} "
          "${mxe.senderId == mx.userID ? 'me' : 'other'} "
          "${mxe.content['body']}",
        );
      }
      // A failed message stays at the bottom, below the newest sent one (or
      // is resent after the others).
      expect(
        timeline.events
            .firstWhere((e) => e is TimelineEventMessage && e.body != _offline)
            .eventId,
        sent.last,
        reason: "the newest message should be the latest one sent",
      );
      expect(
        missing,
        0,
        reason: "scrolling back should reach every skipped message",
      );
      // "Send while offline" resends the failed message after the others.
      await tester.waitFor(
        () => switch (mx.getRoomById(roomId)?.lastEvent) {
          final last? => last.eventId == sent.last ||
              (v.sendWhileOffline && last.body == _offline),
          null => false,
        },
        timeout: const Duration(seconds: 15),
        skipPumpAndSettle: true,
      );

      if (v.encrypted) {
        // The room keys may come after the fill; the shown events decrypt
        // then.
        final decryptBy = DateTime.now().add(const Duration(seconds: 60));
        while (!_allDecrypted(timeline, sent) &&
            DateTime.now().isBefore(decryptBy)) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(
          _allDecrypted(timeline, sent, log: "[$label] decrypted"),
          isTrue,
          reason: "every filled message decrypts: no unable-to-decrypt tiles",
        );
        for (var i = 0; i < skipped.length; i++) {
          final e = timeline.tryGetEvent(skipped[i]) as TimelineEventMessage;
          expect(e.body, "away ${i + 1}");
        }

        // The white unread dot clears once the room is read.
        _log("[$label] unread before reading: ${roomHasUnreadActivity(room)}");
        timeline.markAsRead(timeline.events.first);
        await tester.waitFor(
          () => !roomHasUnreadActivity(room),
          timeout: const Duration(seconds: 30),
          skipPumpAndSettle: true,
        );
      }

      if (failedTxn != null) {
        bool isOffline(TimelineEvent e) =>
            e is TimelineEventMessage && e.body == _offline;
        if (!v.sendWhileOffline) {
          final failed = timeline.events.where(isOffline).toList();
          expect(failed, hasLength(1), reason: "the failed message stays");
          final mxFailed = (failed.single as MatrixTimelineEvent).event;
          expect(mxFailed.eventId, failedTxn);
          expect(
            mxFailed.status,
            matrix.EventStatus.error,
            reason: "it can still be retried",
          );
          await room.retrySend(failed.single);
        }
        // Retried, or resent after the restart by "Send while offline".
        await tester.waitFor(
          () => timeline.events.any(
            (e) =>
                isOffline(e) && (e as MatrixTimelineEvent).event.status.isSent,
          ),
          timeout: const Duration(seconds: 30),
          skipPumpAndSettle: true,
        );
        // Room for a duplicate to show up, if there were one.
        await tester.pump(const Duration(seconds: 3));
        final onServer = await other.getRoomEvents(
          roomId,
          matrix.Direction.b,
          limit: 100,
        );
        final copies =
            onServer.chunk.where((e) => e.content["body"] == _offline).length;
        _log(
          "[$label] after retry: server copies=$copies, "
          "app copies=${timeline.events.where(isOffline).length}",
        );
        expect(copies, 1, reason: "it is sent once");
        expect(timeline.events.where(isOffline), hasLength(1));
      }
      await timeline.close();
    });
  }

  testWidgets("clear cache: the room comes back from the server", (
    tester,
  ) async {
    var app = await tester.setupApp();
    await preferences.experimentSlidingSync.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);

    var appClient = app.clientManager.clients[0] as MatrixClient;
    var mx = appClient.getMatrixClient();
    final me = mx.userID!;
    final deviceId = mx.deviceID;
    final identityKey = mx.identityKey;

    final other = await tester.createTestClient(
      user: tester.userTwoName,
      password: tester.userTwoPassword,
    );
    addTearDown(other.dispose);
    await other.oneShotSync();
    final roomId = await other.createRoom(
      name: "Clear cache test",
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
      () => other.getRoomById(roomId) != null,
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true,
    );
    final last = (await other.getRoomById(roomId)!.sendTextEvent("hello"))!;
    await tester.waitFor(
      () => mx.getRoomById(roomId)?.lastEvent?.eventId == last,
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true,
    );

    await ClearCache.clearAll(app.clientManager);
    final stored = await mx.database.getClient(mx.clientName);
    expect(stored?["prev_batch"], isNull, reason: "the position is cleared");
    expect(await mx.database.getRoomList(mx), isEmpty);
    _log("[clear cache] cleared");

    app = await tester.restartApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    appClient = app.clientManager.clients[0] as MatrixClient;
    mx = appClient.getMatrixClient();
    expect(mx.deviceID, deviceId, reason: "the login stays");
    expect(mx.identityKey, identityKey, reason: "the Olm account stays");

    await tester.waitFor(
      () =>
          mx.getRoomById(roomId)?.lastEvent?.eventId == last &&
          appClient.getRoom(roomId) != null,
      timeout: const Duration(seconds: 45),
      skipPumpAndSettle: true,
    );
    final timeline = await appClient.getRoom(roomId)!.getTimeline();
    expect(timeline.events.any((e) => e.eventId == last), isTrue);
    _log("[clear cache] room is back: ${timeline.events.length} events");
    await timeline.close();
  });

  testWidgets("clear cache: an encrypted room comes back decrypted", (
    tester,
  ) async {
    var app = await tester.setupApp();
    await preferences.experimentSlidingSync.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);

    var appClient = app.clientManager.clients[0] as MatrixClient;
    var mx = appClient.getMatrixClient();

    final other = await tester.createTestClient(
      user: tester.userTwoName,
      password: tester.userTwoPassword,
    );
    addTearDown(other.dispose);
    await other.oneShotSync();
    // See [_trustEachOther].
    other.shareKeysWith = matrix.ShareKeysWith.all;
    final roomId = await _createRoom(
      tester,
      other,
      mx,
      "Clear cache encrypted",
      encrypted: true,
    );
    final otherRoom = other.getRoomById(roomId)!;
    final sent = <String>[];
    for (var i = 1; i <= 3; i++) {
      sent.add((await otherRoom.sendTextEvent("secret $i"))!);
    }
    await tester.waitFor(
      () => mx.getRoomById(roomId)?.lastEvent?.eventId == sent.last,
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true,
    );
    var timeline = await appClient.getRoom(roomId)!.getTimeline();
    await tester.waitFor(
      () => _allDecrypted(timeline, sent),
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true,
    );
    await timeline.close();
    _log("[clear cache encrypted] decrypted before the clear");

    await ClearCache.clearAll(app.clientManager);
    expect(await mx.database.getRoomList(mx), isEmpty);

    app = await tester.restartApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    appClient = app.clientManager.clients[0] as MatrixClient;
    mx = appClient.getMatrixClient();
    await tester.waitFor(
      () =>
          mx.getRoomById(roomId)?.lastEvent?.eventId == sent.last &&
          appClient.getRoom(roomId) != null,
      timeout: const Duration(seconds: 45),
      skipPumpAndSettle: true,
    );
    timeline = await appClient.getRoom(roomId)!.getTimeline();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (
        !_allDecrypted(timeline, sent) && DateTime.now().isBefore(deadline)) {
      if (sent.any((id) => timeline.tryGetEvent(id) == null) &&
          timeline.canLoadHistory &&
          !timeline.isLoadingHistory) {
        await timeline.loadMoreHistory();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      _allDecrypted(timeline, sent, log: "[clear cache encrypted]"),
      isTrue,
      reason: "the kept keys decrypt the downloaded messages",
    );
    await timeline.close();
  });
}
