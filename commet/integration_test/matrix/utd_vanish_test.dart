// Vommet: encrypted messages that vanished after "Retry Decrypt" (tester
// report 2026-10-07).
//
// B (bob) signs in to the app: a new, unverified device. B also has another
// device (the "Element stand-in", an SDK client here) which owns B's
// cross-signing identity. A (alice) creates an encrypted DM, invites B and
// sends messages while B is only invited. Because B has cross-signing and the
// app's device is not cross-signed, A's client (ShareKeysWith
// .crossVerifiedIfEnabled, the SDK default) does not share the room key with
// the app's device: the app shows the messages as "unable to decrypt". B then
// verifies the app's device from the stand-in and uses "Retry Decrypt" on the
// old messages (Event.requestKey); the stand-in answers the key request.
// The messages must decrypt and stay in the timeline, also after reopening
// the room and restarting the app.
//
// Every step logs the app's timeline, the SDK timeline under it and the
// room's events in the database ("UTDV" lines), so a failure explains itself.
//
// The assertions need fix/history-gap-after-join (#102),
// fix/decrypt-display-refresh (#16) and fix/restore-backup-download (#32),
// so this runs on testing, not on its own topic branch. This file doesn't
// import #102's classes: vommet_runner.dart (the per-push suite) runs only
// the "report" variant through [registerVariants]; utd_vanish_runner.dart,
// which runs every variant, plugs #102 in through [gapRepairHooks].
//
// Run: .vommet/it/run.sh integration_test/utd_vanish_runner.dart
//   UTD_ONLY="report;gap"  only the variants whose names start with these
//   UTD_REPEAT=3           each selected variant this many times (races)
//   IT_FEDERATION=1        needed by the "federated:" variants (A on a
//                          second homeserver)
//   IT_HS=synapse          Synapse instead of Tuwunel at https://localhost
//                          (the nightly integration-synapse workflow)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_page.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart' show TextField, Navigator;
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/encryption.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

// ignore: avoid_print
void _log(String line) => print("UTDV $line");

String _describeMx(matrix.Event e) {
  var parts = <String>[
    e.eventId,
    e.type,
    "sender=${e.senderId}",
    "status=${e.status.name}",
  ];
  if (e.type == matrix.EventTypes.Encrypted) {
    parts.add("msgtype=${e.messageType}");
    parts.add("session=${e.content['session_id']}");
    parts.add("can_request=${e.content['can_request_session']}");
  } else if (e.type == matrix.EventTypes.Message) {
    parts.add("body=${e.content['body']}");
  } else if (e.type == matrix.EventTypes.RoomMember) {
    parts.add("state_key=${e.stateKey} membership=${e.content['membership']}");
  }
  return parts.join(" ");
}

Future<void> _dump(String label, MatrixRoom room) async {
  var mxRoom = room.matrixRoom;
  var appTl = room.timeline as MatrixTimeline?;
  _log("---- $label: room ${mxRoom.id} membership=${mxRoom.membership.name} "
      "prev_batch=${mxRoom.prev_batch} encrypted=${mxRoom.encrypted}");
  if (appTl == null) {
    _log("$label app timeline: none");
  } else {
    _log("$label app timeline: ${appTl.events.length} events "
        "(index 0 = newest), canLoadHistory=${appTl.canLoadHistory}");
    for (var i = 0; i < appTl.events.length; i++) {
      var e = appTl.events[i];
      var mx =
          e is MatrixTimelineEvent ? (e as MatrixTimelineEvent).event : null;
      var body = e is TimelineEventMessage ? " body=${e.body}" : "";
      _log("$label app[$i] ${e.runtimeType} ${e.eventId}$body"
          "${mx == null ? "" : " | ${_describeMx(mx)}"}");
    }
    var sdkTl = appTl.matrixTimeline;
    if (sdkTl != null) {
      _log("$label sdk timeline: ${sdkTl.events.length} events, "
          "canRequestHistory=${sdkTl.canRequestHistory} "
          "chunk.prevBatch=${sdkTl.chunk.prevBatch} "
          "chunk.nextBatch=${sdkTl.chunk.nextBatch}");
      for (var i = 0; i < sdkTl.events.length; i++) {
        _log("$label sdk[$i] ${_describeMx(sdkTl.events[i])}");
      }
    }
  }
  try {
    var db = await mxRoom.client.database.getEventList(mxRoom);
    _log("$label database: ${db.length} events");
    for (var i = 0; i < db.length; i++) {
      _log("$label db[$i] ${_describeMx(db[i])}");
    }
  } catch (e) {
    _log("$label database read failed: $e");
  }
}

/// What the app's homeserver answers to back-pagination (/messages), page
/// by page, from the room's prev_batch (where the SDK's own paging starts),
/// in the SDK's page size: the raw JSON keys, so a missing `end` shows as
/// MISSING (the SDK's model can't tell it from null).
Future<void> _rawHistory(String label, matrix.Client client, String roomId,
    {int limit = 30, String? from}) async {
  from ??= client.getRoomById(roomId)?.prev_batch ?? client.prevBatch;
  var http = HttpClient();
  var filter = Uri.encodeComponent(jsonEncode({"lazy_load_members": true}));
  for (var page = 0; page < 20; page++) {
    var url = client.homeserver!.resolve(
        "/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/messages"
        "?dir=b&limit=$limit&filter=$filter"
        "${from == null ? "" : "&from=${Uri.encodeComponent(from)}"}");
    try {
      var req = await http.getUrl(url);
      req.headers.add("Authorization", "Bearer ${client.accessToken}");
      var resp = await req.close();
      var text = await resp.transform(utf8.decoder).join();
      var json = jsonDecode(text) as Map<String, dynamic>;
      var chunk = (json["chunk"] as List?) ?? const [];
      String types = chunk.map((e) {
        var m = e as Map<String, dynamic>;
        var mem = m["type"] == "m.room.member"
            ? "(${(m["content"] as Map?)?["membership"]})"
            : "";
        return "${m["type"]}$mem";
      }).join(", ");
      _log("$label raw /messages page $page (HTTP ${resp.statusCode}) "
          "from=$from limit=$limit: chunk=${chunk.length} "
          "start=${json.containsKey("start") ? json["start"] : "MISSING"} "
          "end=${json.containsKey("end") ? json["end"] : "MISSING"} "
          "state=${(json["state"] as List?)?.length}: $types");
      if (!json.containsKey("end") || chunk.isEmpty) break;
      from = json["end"] as String?;
    } catch (e) {
      _log("$label raw /messages page $page failed: $e");
      break;
    }
  }
  http.close();
}

void _logSession(
    String label, matrix.Client client, String roomId, String? sessionId) {
  if (sessionId == null) return;
  var sess =
      client.encryption?.keyManager.getInboundGroupSession(roomId, sessionId);
  int? first;
  try {
    first = sess?.inboundGroupSession?.firstKnownIndex;
  } catch (_) {}
  _log("$label ${client.deviceID} session $sessionId: "
      "${sess == null ? "absent" : "present firstKnownIndex=$first"}");
}

/// Pumps frames for [d] so the UI and the clients' syncs make progress.
Future<void> _run(WidgetTester tester, Duration d) async {
  var end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

/// Pages back (as scrolling up does) until all of [ids] are in the app's
/// timeline or there is no more history.
bool _hasOwnInvite(MatrixRoom room, String me) =>
    room.timeline!.events.any((e) {
      if (e is! MatrixTimelineEvent) return false;
      var mx = (e as MatrixTimelineEvent).event;
      return mx.type == matrix.EventTypes.RoomMember &&
          mx.stateKey == me &&
          mx.content['membership'] == 'invite';
    });

/// Settings › Security › Message backup › Restore, as a user does it: the
/// restore dialog, the recovery key, Confirm.
Future<void> _restoreBackupViaUi(
    WidgetTester tester, MatrixClient client, String recoveryKey) async {
  var context = tester.element(find.byType(RoomTimelineWidgetView).first);
  unawaited(AdaptiveDialog.show(context,
      builder: (_) => MatrixCrossSigningPage(
            client: client,
            mode: MatrixCrossSigningMode.restoreBackup,
          ),
      dismissible: true,
      title: "Restore backup"));
  var keyField = find.descendant(
      of: find.byType(MatrixCrossSigningPage),
      matching: find.byType(TextField));
  try {
    await tester.waitFor(() => keyField.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
  } catch (_) {
    await _screen(tester, "restore dialog stuck");
    rethrow;
  }
  await tester.enterText(keyField.first, recoveryKey);
  await tester.pump();
  await tester.tap(find
      .descendant(
          of: find.byType(MatrixCrossSigningPage),
          matching: find.text(CommonStrings.promptConfirm))
      .first);
  // Wait until the dialog moved on from the key prompt.
  await tester.waitFor(() => keyField.evaluate().isEmpty,
      timeout: const Duration(seconds: 60));
  await _screen(tester, "restore dialog after confirm");
  await _run(tester, const Duration(seconds: 2));
  // Close it (the backup download keeps running in the background).
  if (find.byType(MatrixCrossSigningPage).evaluate().isNotEmpty) {
    Navigator.of(tester.element(find.byType(MatrixCrossSigningPage))).pop();
    await _run(tester, const Duration(seconds: 1));
  }
}

final _watched = Expando<bool>();

/// Logs every insert/change/remove the app's timeline announces.
void _watch(MatrixRoom room) {
  var tl = room.timeline!;
  if (_watched[tl] == true) return;
  _watched[tl] = true;
  String at(int i) => i < tl.events.length
      ? "${tl.events[i].eventId} ${tl.events[i].runtimeType}"
      : "out of range (${tl.events.length})";
  tl.onEventAdded.stream.listen((i) => _log("event added [$i] ${at(i)}"));
  tl.onChange.stream.listen((i) => _log("event changed [$i] ${at(i)}"));
  tl.onRemove.stream.listen((i) => _log("event removed [$i] ${at(i)}"));
}

Future<void> _loadAll(WidgetTester tester, MatrixRoom room, List<String> ids,
    String label) async {
  await tester.waitFor(() => room.timeline?.events.isNotEmpty == true,
      timeout: const Duration(seconds: 30));
  _watch(room);
  var tl = room.timeline!;
  bool all() => ids.every((id) => tl.events.any((e) => e.eventId == id));
  for (var i = 0; i < 15 && !all(); i++) {
    var can = tl.canLoadHistory;
    _log("$label paging back ($i): ${tl.events.length} events, "
        "canLoadHistory=$can");
    if (!can) break;
    await tl.loadMoreHistory();
    await _run(tester, const Duration(milliseconds: 500));
  }
  await _run(tester, const Duration(seconds: 2));
  _log("$label loaded: all=${all()} events=${tl.events.length}");
}

bool _shown(String text) =>
    find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

final _out = Platform.environment["OUT"] ?? Directory.systemTemp.path;

/// Logs what the timeline shows (the test's messages and decryption
/// failures) and grabs the X display (the app window) to OUT/utdv-<n>.png.
Future<void> _screen(WidgetTester tester, String label) async {
  await _run(tester, const Duration(milliseconds: 1500));
  var texts = <String>[];
  for (var e
      in find.byWidgetPredicate((w) => w is RichText || w is Text).evaluate()) {
    var w = e.widget;
    var t = w is RichText
        ? w.text.toPlainText()
        : (w as Text).data ?? w.textSpan?.toPlainText() ?? "";
    if (t.contains("utdv") || t.contains("decrypt") || t.contains("invit")) {
      texts.add(t.replaceAll("\n", " "));
    }
  }
  _log("$label screen: ${texts.toSet().toList()}");
  for (var e in find.byType(TimelineViewEntry).evaluate()) {
    var st = (e as StatefulElement).state as TimelineViewEntryState;
    var w = st.widget;
    var tl = w.timeline;
    var at = st.index < tl.events.length ? tl.events[st.index].eventId : "-";
    _log("$label entry index=${st.index} eventId=${st.eventId} "
        "eventAtIndex=${at == st.eventId ? "same" : at} "
        "collapse=${st.collapse?.name} canCollapse=${w.canCollapse} "
        "initialIndex=${w.initialIndex}");
  }
  for (var e in find.byType(RoomTimelineWidgetView).evaluate()) {
    var st = (e as StatefulElement).state as RoomTimelineWidgetViewState;
    var keys = st.eventKeys;
    var tl = st.timeline;
    var bad = <String>[];
    for (var i = 0; i < keys.length || i < tl.events.length; i++) {
      var k = i < keys.length ? keys[i].$2 : "-";
      var ev = i < tl.events.length ? tl.events[i].eventId : "-";
      if (k != ev) bad.add("[$i] key=$k event=$ev");
    }
    _log("$label view: ${keys.length} keys, ${tl.events.length} events, "
        "recentItemsCount=${st.recentItemsCount}, mismatches=$bad");
  }
  _shotN++;
  var name = "utdv-${_shotN.toString().padLeft(2, "0")}-"
      "${label.replaceAll(RegExp(r"[^a-z0-9]+"), "-")}.png";
  var r = await Process.run("ffmpeg", [
    "-y", "-loglevel", "error", "-f", "x11grab", "-video_size", "1280x720", //
    "-i", Platform.environment["DISPLAY"] ?? ":99", "-frames:v", "1",
    "$_out/$name",
  ]);
  _log("$label shot $name exit=${r.exitCode}");
}

int _shotN = 0;

/// #102's automatic history-gap repair, for the "reload history" variants.
/// Set by utd_vanish_runner.dart; this file stays free of #102's classes so
/// that the per-push suite compiles without them.
class GapRepairHooks {
  const GapRepairHooks(
      {required this.setAutoRepair, required this.isReloading});

  /// Switches the automatic repair on or off (MatrixHistoryGapComponent
  /// .autoCheck).
  final void Function(bool on) setAutoRepair;

  /// Whether a "Reload History" of [room] is still running.
  final bool Function(MatrixRoom room) isReloading;
}

GapRepairHooks? gapRepairHooks;

class _Variant {
  const _Variant(this.name,
      {this.preJoin = 3,
      this.postJoinBeforeVerify = 0,
      this.openBeforeVerify = true,
      this.fillerBeforeJoin = 0,
      this.slidingSync = false,
      this.restoreWithRecoveryKey = false,
      this.federated = false,
      this.acceptElsewhere = false,
      this.restartBeforeVerify = false,
      this.appPagesFirst = false,
      this.manualReload = false,
      this.restoreViaUi = false});
  final String name;

  /// The automatic gap repair (#102) is off; after the join the room's
  /// history is reloaded through the room menu's "Reload History".
  final bool manualReload;

  /// The app restores the key backup through Settings › Security ›
  /// Restore (MatrixCrossSigningPage, restoreBackup mode) with the recovery
  /// key, and the old messages must decrypt without "Retry Decrypt" (#32).
  final bool restoreViaUi;

  /// The app's own back-pagination is the first /messages request after the
  /// join (the raw probe runs after it).
  final bool appPagesFirst;

  /// B accepts the invitation on the other device; the app only sees the
  /// join come in through sync.
  final bool acceptElsewhere;

  /// The app is relaunched after showing the undecryptable messages and
  /// before B verifies it.
  final bool restartBeforeVerify;

  /// A is on a second homeserver (.vommet/it/homeserver.sh with
  /// IT_FEDERATION=1), like the report: B's server only learns the room's
  /// history when B joins.
  final bool federated;

  /// Instead of the other device cross-signing the app's device, the app
  /// unlocks secret storage with the recovery key (what the security
  /// settings' restore does, and what a SAS verification hands over: the
  /// cross-signing and key backup secrets). The app then self-signs, and
  /// "Retry Decrypt" fetches the key from the online key backup first.
  final bool restoreWithRecoveryKey;

  /// The sliding sync experiment (MSC4186) on for the app.
  final bool slidingSync;

  /// State events (topic changes) alice sends after the encrypted messages
  /// and before B joins, so the join sync is limited and the messages only
  /// come back through history pagination, as on a federated join.
  final int fillerBeforeJoin;
  final int preJoin;
  final int postJoinBeforeVerify;
  final bool openBeforeVerify;
}

Future<void> _scenario(WidgetTester tester, _Variant v) async {
  _log("==== variant ${v.name}");
  var app = await tester.setupApp();
  await preferences.experimentSlidingSync.set(v.slidingSync);
  addTearDown(() => preferences.experimentSlidingSync.set(false));
  await tester.pumpWidget(app);
  await tester.loginUser2(app);
  await tester.pumpAndSettle();

  var client = app.clientManager.clients.first as MatrixClient;
  var mx = client.getMatrixClient();
  await tester.waitFor(() => mx.prevBatch != null,
      timeout: const Duration(seconds: 60), skipPumpAndSettle: true);
  matrix.Logs().level = matrix.Level.info;
  var bobId = mx.userID!;
  var appDevice = mx.deviceID!;
  _log("app logged in as $bobId device $appDevice "
      "slidingSync=${mx.slidingSync}");

  // B's other device: owns B's cross-signing identity (and key backup).
  var standIn = await tester.createTestClient(
      user: tester.userTwoName,
      password: tester.userTwoPassword,
      deviceName: "Element stand-in");
  addTearDown(() => standIn.dispose(closeDatabase: true));
  await standIn.oneShotSync();
  var recoveryKey = await standIn.initCryptoIdentity();
  await tester.waitFor(() => standIn.encryption!.crossSigning.enabled == true,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  _log("stand-in ${standIn.deviceID} bootstrapped cross-signing "
      "(master ${standIn.userDeviceKeys[bobId]?.masterKey?.publicKey})");

  // A.
  var alice = await tester.createTestClient(
      deviceName: "Alice sender",
      server: v.federated
          ? Platform.environment["IT_HS2"] ?? "127.0.0.1:8449"
          : null);
  addTearDown(() => alice.dispose(closeDatabase: true));
  await alice.oneShotSync();
  var roomId = await alice.startDirectChat(bobId,
      enableEncryption: true, skipExistingChat: true);
  var aliceRoom = alice.getRoomById(roomId)!;
  await tester.waitFor(() => aliceRoom.encrypted,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  _log("alice ${alice.deviceID} created DM $roomId "
      "history_visibility=${aliceRoom.historyVisibility?.name}");
  await alice.updateUserDeviceKeys(additionalUsers: {bobId});
  for (var d in alice.userDeviceKeys[bobId]?.deviceKeys.values.toList() ??
      <matrix.DeviceKeys>[]) {
    _log(
        "alice sees bob device ${d.deviceId}: crossVerified=${d.crossVerified} "
        "signed=${d.signed} encryptToDevice=${d.encryptToDevice}");
  }

  // Share the megolm session before the first message, so B's other device
  // has it from index 0 (sharing it with the first send sometimes reached
  // that device only from index 1, which Element would not decrypt either).
  await alice.encryption!.keyManager.prepareOutboundGroupSession(roomId);
  var sent = <String>[];
  for (var n = 1; n <= v.preJoin; n++) {
    sent.add((await aliceRoom.sendTextEvent("utdv pre-join $n"))!);
  }
  _log("alice sent while bob invited: $sent");
  for (var n = 1; n <= v.fillerBeforeJoin; n++) {
    await aliceRoom.setDescription("utdv filler $n");
  }

  // B accepts in the app, the way the invitation UI does.
  var invitations = client.getComponent<InvitationComponent>()!;
  await tester.waitFor(
      () => invitations.invitations.any((i) => i.roomId == roomId),
      timeout: const Duration(seconds: 30));
  if (v.acceptElsewhere) {
    await tester.waitFor(() => standIn.getRoomById(roomId) != null,
        timeout: const Duration(seconds: 30));
    await standIn.getRoomById(roomId)!.join();
  } else {
    await invitations.acceptInvitation(
        invitations.invitations.firstWhere((i) => i.roomId == roomId));
  }
  await tester.waitFor(
      () =>
          client.hasRoom(roomId) &&
          mx.getRoomById(roomId)?.membership == matrix.Membership.join,
      timeout: const Duration(seconds: 30));
  var room = client.getRoom(roomId) as MatrixRoom;
  _log("app joined $roomId");

  for (var n = 1; n <= v.postJoinBeforeVerify; n++) {
    sent.add((await aliceRoom.sendTextEvent("utdv post-join $n"))!);
  }

  Future<void> openRoom(String label) async {
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => room.timeline != null,
        timeout: const Duration(seconds: 30));
    await _loadAll(tester, room, sent, label);
    await _dump(label, room);
    await _screen(tester, label);
  }

  var missingAfterJoin = <String>[];
  var failures = <String>[];
  var hooks = gapRepairHooks;
  if (v.manualReload) {
    if (hooks == null) {
      fail("${v.name} needs utd_vanish_runner.dart (gapRepairHooks)");
    }
    hooks.setAutoRepair(false);
    addTearDown(() => hooks.setAutoRepair(true));
  }
  var joinPrevBatch = mx.getRoomById(roomId)?.prev_batch;
  _log("prev_batch right after the join: $joinPrevBatch");
  if (!v.appPagesFirst) await _rawHistory("joined", mx, roomId);
  if (v.openBeforeVerify) {
    await openRoom("joined+opened");
    if (v.appPagesFirst) {
      // The same pagination again, from the join's prev_batch, now that the
      // server has had time to backfill: what the app would get if it asked
      // again.
      await _run(tester, const Duration(seconds: 3));
      await _rawHistory("joined, after the app paged", mx, roomId,
          from: joinPrevBatch);
    }
    for (var id in sent) {
      if (!room.timeline!.events.any((e) => e.eventId == id)) {
        _log("GAP $id is missing from the app's timeline after the join");
        missingAfterJoin.add(id);
      }
    }
    var inviteSeen = _hasOwnInvite(room, bobId);
    _log("GAP check after the join: ${missingAfterJoin.length} messages "
        "missing, own invite ${inviteSeen ? "present" : "MISSING"}");
    if (v.manualReload) {
      // Give the server time to finish backfilling, then reload the
      // history the way the room menu does.
      await _run(tester, const Duration(seconds: 5));
      var items = RoomTextButton.createRoomContextMenuItems(
          tester.element(find.byType(RoomTimelineWidgetView).first), room);
      var item = items.where((i) => i.text == "Reload History").firstOrNull;
      if (item == null) {
        failures.add("no \"Reload History\" in the room menu");
      } else {
        var before = room.timeline!.events.length;
        item.onPressed?.call();
        await tester.waitFor(() => !hooks!.isReloading(room),
            timeout: const Duration(seconds: 60));
        await _loadAll(tester, room, sent, "reloaded");
        _log("reloaded: $before events before, "
            "${room.timeline!.events.length} after");
        await _dump("reloaded", room);
        await _screen(tester, "reloaded");
      }
    }
    // The automatic repair (or the reload) must bring back the messages
    // and the invite.
    bool complete() =>
        sent.every((id) => room.timeline!.events.any((e) => e.eventId == id)) &&
        _hasOwnInvite(room, bobId);
    var clock = Stopwatch()..start();
    var repairBy = DateTime.now().add(const Duration(seconds: 90));
    while (!complete() && DateTime.now().isBefore(repairBy)) {
      // Scroll up, as a reader would: a reloaded timeline pages back again.
      if (room.timeline!.canLoadHistory) {
        await room.timeline!.loadMoreHistory();
      }
      await _run(tester, const Duration(seconds: 1));
    }
    if (complete()) {
      if (missingAfterJoin.isNotEmpty || !inviteSeen) {
        _log("GAP REPAIRED after ${clock.elapsed.inSeconds} s");
        await _loadAll(tester, room, sent, "repaired");
        await _dump("repaired", room);
        await _screen(tester, "repaired");
      }
    } else {
      failures.add("history still incomplete 90 s after the join "
          "(missing ${sent.where((id) => !room.timeline!.events.any((e) => e.eventId == id)).toList()}, "
          "invite ${_hasOwnInvite(room, bobId)})");
      _log("FAIL ${failures.last}");
    }
    for (var id in sent) {
      var e = room.timeline!.events.where((e) => e.eventId == id).firstOrNull;
      if (e == null) continue;
      expect(e, isA<TimelineEventEncrypted>(),
          reason: "$id should be undecryptable before verification "
              "(alice must not have shared the key with the app's device)");
    }
  }
  if (v.restartBeforeVerify) {
    await tester.pumpWidget(const SizedBox());
    await _run(tester, const Duration(seconds: 1));
    app = await tester.restartApp();
    await tester.pumpWidget(app);
    await _run(tester, const Duration(seconds: 2));
    client = app.clientManager.clients.first as MatrixClient;
    mx = client.getMatrixClient();
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 60));
    room = client.getRoom(roomId) as MatrixRoom;
    for (var attempt = 0; room.timeline == null; attempt++) {
      if (attempt == 20) throw Exception("the room never opened after restart");
      EventBus.doOpenRoom(roomId, clientId: client.identifier);
      await _run(tester, const Duration(seconds: 2));
    }
    await _loadAll(tester, room, sent, "restarted before verify");
    await _dump("restarted before verify", room);
    await _screen(tester, "restarted before verify");
  }
  var sessionId = (await mx.getRoomById(roomId)!.getEventById(sent.first))
      ?.content['session_id'] as String?;
  _logSession("before verify", mx, roomId, sessionId);
  _logSession("before verify", standIn, roomId, sessionId);

  // B verifies the app's device from the stand-in: it cross-signs it.
  await standIn.updateUserDeviceKeys(additionalUsers: {bobId});
  await tester.waitFor(
      () => standIn.userDeviceKeys[bobId]?.deviceKeys[appDevice] != null,
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true);
  if (v.restoreViaUi) {
    await standIn.encryption!.keyManager.uploadInboundGroupSessions();
    await _restoreBackupViaUi(tester, client, recoveryKey);
    _log("app restored through the UI: "
        "${await mx.getCryptoIdentityState()} "
        "backupCached=${await mx.encryption!.keyManager.isCached()}");
  } else if (v.restoreWithRecoveryKey) {
    // Make sure the stand-in has put the room key in the online backup.
    await standIn.encryption!.keyManager.uploadInboundGroupSessions();
    await mx.restoreCryptoIdentity(recoveryKey);
    _log("app restored crypto identity: "
        "${await mx.getCryptoIdentityState()} "
        "backupCached=${await mx.encryption!.keyManager.isCached()}");
  } else {
    var appKeys = standIn.userDeviceKeys[bobId]!.deviceKeys[appDevice]!;
    await appKeys.setVerified(true);
  }
  var verifiedBy = DateTime.now().add(const Duration(seconds: 60));
  while (alice.userDeviceKeys[bobId]?.deviceKeys[appDevice]?.encryptToDevice !=
      true) {
    if (DateTime.now().isAfter(verifiedBy)) {
      throw Exception("alice never saw the app's device as cross-signed");
    }
    await alice.updateUserDeviceKeys(additionalUsers: {bobId});
    await _run(tester, const Duration(seconds: 1));
  }
  _log("app device $appDevice is cross-signed (alice now encrypts to it)");

  // As in the report: after verifying, new messages decrypt.
  var after = (await aliceRoom.sendTextEvent("utdv after-verify"))!;
  if (!v.openBeforeVerify) await openRoom("opened after verify");
  await tester.waitFor(
      () => room.timeline!.events
          .any((e) => e.eventId == after && e is TimelineEventMessage),
      timeout: const Duration(seconds: 30));
  await _dump("after verify, new message decrypted", room);
  await _screen(tester, "after verify");
  _logSession("after verify", mx, roomId, sessionId);

  bool allDecrypted() => sent.every((id) => room.timeline!.events
      .any((e) => e.eventId == id && e is TimelineEventMessage));
  if (v.restoreViaUi) {
    // #32: restoring downloads the backup, so the old messages decrypt by
    // themselves, without "Retry Decrypt".
    try {
      await tester.waitFor(allDecrypted, timeout: const Duration(seconds: 30));
      _log("BACKUP old messages decrypted without Retry Decrypt");
    } catch (_) {
      failures.add("old messages not decrypted 30 s after restoring the "
          "backup through the UI (no Retry Decrypt)");
      _log("FAIL ${failures.last}");
    }
    await _dump("after the UI restore", room);
    await _screen(tester, "after the UI restore");
  }

  // "Retry Decrypt" on each undecryptable message, as the menu does.
  for (var e in room.timeline!.events.toList()) {
    if (e is TimelineEventEncrypted) {
      var ev = (e as MatrixTimelineEvent).event;
      try {
        await ev.requestKey();
        _log("requestKey ${ev.eventId}: sent");
      } catch (err) {
        _log("requestKey ${ev.eventId}: $err");
      }
    }
  }

  try {
    await tester.waitFor(allDecrypted, timeout: const Duration(seconds: 30));
  } catch (_) {
    _log("not all messages decrypted in place within 30 s");
  }
  await _run(tester, const Duration(seconds: 3));
  await _dump("after retry decrypt", room);
  _logSession("after retry decrypt", mx, roomId, sessionId);

  Future<void> check(String label) async {
    await _loadAll(tester, room, sent, label);
    await _screen(tester, label);
    var tl = room.timeline!;
    for (var n = 0; n < sent.length; n++) {
      var i = tl.events.indexWhere((e) => e.eventId == sent[n]);
      if (i == -1) {
        failures.add("$label: ${sent[n]} vanished from the app's timeline");
        _log("FAIL ${failures.last}");
      } else if (tl.events[i] is! TimelineEventMessage) {
        failures.add("$label: ${sent[n]} is still undecryptable "
            "(${tl.events[i].runtimeType})");
        _log("FAIL ${failures.last}");
      }
    }
    // The newest three fit on screen in every variant.
    for (var n = max(1, v.preJoin - 2); n <= v.preJoin; n++) {
      if (!_shown("utdv pre-join $n")) {
        failures.add("$label: 'utdv pre-join $n' is not on screen");
        _log("FAIL ${failures.last}");
      }
    }
  }

  await check("after retry decrypt");

  // Reopen: another room, then back.
  var other = client.rooms.firstWhere((r) => r.identifier != roomId);
  EventBus.doOpenRoom(other.identifier, clientId: client.identifier);
  await _run(tester, const Duration(seconds: 2));
  EventBus.doOpenRoom(roomId, clientId: client.identifier);
  await _run(tester, const Duration(seconds: 3));
  await _dump("after reopening", room);
  await check("after reopening");

  // Restart the app on the same data.
  // Unmount the old UI first, or pumpWidget would keep its state (and the
  // closed clients) under the new App.
  await tester.pumpWidget(const SizedBox());
  await _run(tester, const Duration(seconds: 1));
  app = await tester.restartApp();
  await tester.pumpWidget(app);
  await _run(tester, const Duration(seconds: 2));
  client = app.clientManager.clients.first as MatrixClient;
  await tester.waitFor(() => client.hasRoom(roomId),
      timeout: const Duration(seconds: 60));
  room = client.getRoom(roomId) as MatrixRoom;
  // The relaunched UI may not listen for open requests yet: ask again until
  // the room's timeline is open.
  for (var attempt = 0; room.timeline == null; attempt++) {
    if (attempt == 20) throw Exception("the room never opened after restart");
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await _run(tester, const Duration(seconds: 2));
  }
  await _run(tester, const Duration(seconds: 5));
  await _dump("after restart", room);
  await check("after restart");
  expect(failures, isEmpty);
}

const _variants = [
  _Variant("report: 3 before join, open, verify, retry"),
  _Variant("gap: join sync limited, messages from history",
      fillerBeforeJoin: 40),
  _Variant("not opened before verify", openBeforeVerify: false),
  _Variant("messages before and after join", postJoinBeforeVerify: 2),
  _Variant("backup: restore with recovery key, key from backup",
      restoreWithRecoveryKey: true),
  _Variant("accepted on the other device", acceptElsewhere: true),
  _Variant("restart before verify", restartBeforeVerify: true),
  _Variant("twelve messages", preJoin: 12),
  _Variant("federated: report", federated: true),
  _Variant("federated: gap", federated: true, fillerBeforeJoin: 40),
  _Variant("federated: app pages first, gap",
      federated: true, fillerBeforeJoin: 40, appPagesFirst: true),
  _Variant("federated: app pages first, report",
      federated: true, appPagesFirst: true),
  _Variant("federated: reload history, gap",
      federated: true,
      fillerBeforeJoin: 40,
      appPagesFirst: true,
      manualReload: true),
  _Variant("federated: restore backup in the UI",
      federated: true, restoreViaUi: true),
  _Variant("backup: restore in the UI", restoreViaUi: true),
  _Variant("federated: backup", federated: true, restoreWithRecoveryKey: true),
  _Variant("federated: sliding sync", federated: true, slidingSync: true),
  _Variant("sliding sync: report", slidingSync: true),
  _Variant("sliding sync: gap", slidingSync: true, fillerBeforeJoin: 40),
];

/// Registers the variants whose names start with one of [prefixes] (all of
/// them if it is empty), each [repeat] times.
void registerVariants(List<String> prefixes, {int repeat = 1}) {
  for (var v in _variants) {
    if (prefixes.isNotEmpty && !prefixes.any((p) => v.name.startsWith(p))) {
      continue;
    }
    for (var r = 1; r <= repeat; r++) {
      testWidgets('UTD vanish: ${v.name}${repeat > 1 ? " #$r" : ""}',
          (tester) => _scenario(tester, v));
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // UTD_ONLY: ";"-separated name prefixes of the variants to run (names
  // contain commas). UTD_REPEAT: run each selected variant this many times.
  registerVariants(
      (Platform.environment["UTD_ONLY"] ?? "")
          .split(";")
          .where((p) => p.isNotEmpty)
          .toList(),
      repeat: int.tryParse(Platform.environment["UTD_REPEAT"] ?? "") ?? 1);
}
