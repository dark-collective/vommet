// Vommet issue 1047, step 1: what the homeserver actually pushes, through
// the app's background push handler.
//
// The app (user 1) registers two pushers at a fake push gateway running in
// this test: one `event_id_only` (the format the app registers), one in the
// full format. User 2, on its own client, sends a DM, a group message, a
// mention, a keyword hit, a message in a muted room, a thread reply, a
// reaction and a redaction (plus a DM and a mention in an encrypted room).
// Each push is saved under $OUT/push-payloads/<server>/ and handed to
// BackgroundNotificationsManager2.handleMessage the way the UnifiedPush
// receiver does; NotificationManager.debugOnNotify catches the result
// instead of showing it. Synapse sends `event_id_only` pushes with no
// tweaks (Vommet issue 719): their outcome has to match the full format's.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:commet/service/background_service_notifications/background_service_task_notification2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("PUSHIT $s");
}

const _formats = ["event_id_only", "full"];

/// A Matrix push gateway on 127.0.0.1 that records what it is sent.
class _FakeGateway {
  _FakeGateway(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<Map<String, dynamic>> bodies = [];

  static Future<_FakeGateway> start() async =>
      _FakeGateway(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri get url =>
      Uri.parse("http://127.0.0.1:${_server.port}/_matrix/push/v1/notify");

  Future<void> _handle(HttpRequest request) async {
    try {
      final text = await utf8.decoder.bind(request).join();
      if (request.method == "POST" &&
          request.uri.path == "/_matrix/push/v1/notify") {
        bodies.add(jsonDecode(text) as Map<String, dynamic>);
      } else {
        _log("gateway: unexpected ${request.method} ${request.uri.path}");
      }
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"rejected": []}));
    } catch (e) {
      _log("gateway: $e");
      request.response.statusCode = 400;
    }
    await request.response.close();
  }

  /// The push for [eventId] to the pusher with [pushkey], if any yet.
  Map<String, dynamic>? find(String eventId, String pushkey) {
    for (final body in bodies) {
      final n = body["notification"];
      if (n is! Map || n["event_id"] != eventId) continue;
      final devices = n["devices"];
      if (devices is List &&
          devices.isNotEmpty &&
          devices.first is Map &&
          devices.first["pushkey"] == pushkey) {
        return body;
      }
    }
    return null;
  }

  Future<void> close() => _server.close(force: true);
}

/// What the app made of one push.
class _Outcome {
  const _Outcome(this.shown, this.sound, this.highlight, this.detail);

  final bool shown;
  final bool sound;
  final bool highlight;
  final String detail;

  String get label => !shown
      ? "not shown"
      : "shown${sound ? "+sound" : " silent"}${highlight ? "+highlight" : ""}";

  @override
  bool operator ==(Object other) =>
      other is _Outcome &&
      other.shown == shown &&
      other.sound == sound &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(shown, sound, highlight);
}

class _Case {
  _Case(this.name, this.eventId, {this.expectPush = true});

  final String name;
  final String eventId;

  /// False for the cases the default rules don't push (muted, reaction,
  /// redaction): a push is recorded, but none is required.
  final bool expectPush;
  final Map<String, Map<String, dynamic>?> pushes = {};
  final Map<String, _Outcome?> outcomes = {};
}

void main() {
  testWidgets("push pipeline: server pushes through the background handler",
      (tester) async {
    final server =
        Platform.environment["IT_HS"] == "synapse" ? "synapse" : "tuwunel";
    final out = Platform.environment["OUT"] ?? "it-out";
    final payloadDir = Directory("$out/push-payloads/$server");
    await payloadDir.create(recursive: true);

    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);

    final client = app.clientManager.clients[0] as MatrixClient;
    final mx = client.getMatrixClient();
    final me = mx.userID!;
    await tester.waitFor(() => client.firstSyncComplete,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);

    final gateway = await _FakeGateway.start();
    addTearDown(gateway.close);
    final run = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

    // Two pushers, told apart by pushkey. The pusher data carries
    // local_client_id like the app's own (PushClientRouting reads it).
    final pushkeys = <String, String>{};
    for (final format in _formats) {
      final pushkey = "pushit-$format-$run";
      pushkeys[format] = pushkey;
      final pusher = matrix.Pusher(
          appId: "it.vommet.push.${format.replaceAll("_", "")}",
          pushkey: pushkey,
          appDisplayName: "Vommet push pipeline IT",
          deviceDisplayName: "push-pipeline-it",
          kind: "http",
          lang: "en",
          data: matrix.PusherData(
              url: gateway.url,
              format: format == "full" ? null : format,
              additionalProperties: {"local_client_id": client.identifier}));
      await mx.postPusher(pusher, append: true);
      addTearDown(() async {
        try {
          await mx.deletePusher(
              matrix.PusherId(appId: pusher.appId, pushkey: pushkey));
        } catch (_) {}
      });
    }
    _log("[$server] pushers at ${gateway.url}");

    // A keyword rule, added the way Settings > Notifications adds one.
    final keyword = "pushkw$run";
    final stored = PushRuleRows.keywords.store(PushRuleLevel.noisy);
    await mx.setPushRule(matrix.PushRuleKind.content, keyword, stored.actions,
        pattern: keyword);
    addTearDown(() async {
      try {
        await mx.deletePushRule(matrix.PushRuleKind.content, keyword);
      } catch (_) {}
    });

    final other = await tester.createTestClient(
        user: tester.userTwoName, password: tester.userTwoPassword);
    addTearDown(() => other.dispose(closeDatabase: true));
    await other.oneShotSync();

    // A third account, so one room is a real group (3 members:
    // .m.rule.message, no sound) rather than .m.rule.room_one_to_one.
    final hs = Uri.https(tester.homeserver);
    Future<Map<String, dynamic>> api(String path, Map<String, Object?> body,
        {String? token}) async {
      final http = HttpClient();
      try {
        final request = await http.postUrl(hs.resolve(path));
        request.headers.contentType = ContentType.json;
        if (token != null) {
          request.headers.set("Authorization", "Bearer $token");
        }
        request.write(jsonEncode(body));
        final response = await request.close();
        final text = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          throw StateError("$path: ${response.statusCode} $text");
        }
        return jsonDecode(text) as Map<String, dynamic>;
      } finally {
        http.close();
      }
    }

    final third = await api("/_matrix/client/v3/register", {
      "username": "pushthird$run".toLowerCase(),
      "password": "pw-pushthird$run",
      "auth": {"type": "m.login.dummy"},
    });
    final thirdId = third["user_id"] as String;
    final thirdToken = third["access_token"] as String;

    Future<String> newRoom(String name,
        {bool direct = false,
        bool encrypted = false,
        bool threeMembers = false}) async {
      final roomId = await other.createRoom(
        name: direct ? null : "$name $run",
        invite: [me, if (threeMembers) thirdId],
        isDirect: direct,
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
      await tester.waitFor(() => mx.getRoomById(roomId) != null,
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
      await mx.joinRoom(roomId);
      await tester.waitFor(() => client.getRoom(roomId) != null,
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
      // The server has the join (an encrypted room needs it to share keys).
      if (threeMembers) {
        await api("/_matrix/client/v3/join/${Uri.encodeComponent(roomId)}", {},
            token: thirdToken);
      }
      for (var i = 0;; i++) {
        final joined = await other.getJoinedMembersByRoom(roomId);
        if (joined?.containsKey(me) == true &&
            (!threeMembers || joined?.containsKey(thirdId) == true)) {
          break;
        }
        if (i >= 60) throw StateError("$me never joined $name");
        await Future.delayed(const Duration(milliseconds: 500));
      }
      _log("joined $name");
      return roomId;
    }

    final dm = await newRoom("dm", direct: true);
    final group = await newRoom("Push group");
    final group3 = await newRoom("Push group3", threeMembers: true);
    final muted = await newRoom("Push muted");
    final e2ee = await newRoom("e2ee", direct: true, encrypted: true);
    _log("[$server] rooms: dm=$dm group=$group muted=$muted e2ee=$e2ee");

    // Muted the way the room's notification menu mutes it.
    await client.getRoom(muted)!.setPushRule(PushRule.dontNotify);

    Future<String> send(String roomId, Map<String, dynamic> content,
        {String type = matrix.EventTypes.Message}) async {
      final id =
          await other.getRoomById(roomId)!.sendEvent(content, type: type);
      if (id == null) throw StateError("sending to $roomId failed");
      return id;
    }

    Map<String, dynamic> text(String body) =>
        {"msgtype": "m.text", "body": body};

    Map<String, dynamic> mention(String body) => {
          "msgtype": "m.text",
          "body": "${mx.userID} $body",
          "format": "org.matrix.custom.html",
          "formatted_body": "<a href=\"https://matrix.to/#/$me\">$me</a> $body",
          "m.mentions": {
            "user_ids": [me]
          },
        };

    final cases = <_Case>[];
    Future<void> waitPushes(String eventId, Duration timeout) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        if (pushkeys.values.every((k) => gateway.find(eventId, k) != null)) {
          return;
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    // The app's own message, for user 2 to react to.
    final ownMessage =
        await mx.getRoomById(group)!.sendTextEvent("react to this");

    cases.add(_Case("dm", await send(dm, text("a DM"))));
    cases.add(_Case("group", await send(group, text("a group message"))));
    cases.add(
        _Case("group3", await send(group3, text("a three-member message"))));
    cases.add(_Case("mention", await send(group, mention("a mention"))));
    cases.add(_Case("keyword", await send(group, text("about $keyword now"))));
    final root = cases[1].eventId;
    cases.add(_Case(
        "thread",
        await send(group, {
          ...text("a thread reply"),
          "m.relates_to": {
            "rel_type": "m.thread",
            "event_id": root,
            "is_falling_back": true,
            "m.in_reply_to": {"event_id": root},
          },
        })));
    cases.add(_Case("e2ee-dm", await send(e2ee, text("an encrypted DM"))));
    cases.add(_Case(
        "e2ee-mention", await send(e2ee, mention("an encrypted mention"))));
    cases.add(_Case("muted", await send(muted, text("a muted message")),
        expectPush: false));
    cases.add(_Case(
        "reaction",
        await send(
            group,
            {
              "m.relates_to": {
                "rel_type": "m.annotation",
                "event_id": ownMessage,
                "key": "👍",
              }
            },
            type: matrix.EventTypes.Reaction),
        expectPush: false));
    final doomed = await send(group, text("to be redacted"));
    await waitPushes(doomed, const Duration(seconds: 20));
    final redaction = await other.getRoomById(group)!.redactEvent(doomed);
    cases.add(_Case("redaction", redaction!, expectPush: false));
    // Pushes come in order: once the sentinel's are in, give the ones not
    // expected a short window more.
    final sentinel = await send(group, text("sentinel"));
    _log("[$server] sent ${cases.length} cases + sentinel");

    for (final c in cases.where((c) => c.expectPush)) {
      await waitPushes(c.eventId, const Duration(seconds: 20));
    }
    await waitPushes(sentinel, const Duration(seconds: 20));
    await Future.delayed(const Duration(seconds: 5));

    for (final c in cases) {
      for (final format in _formats) {
        final body = gateway.find(c.eventId, pushkeys[format]!);
        c.pushes[format] = body;
        if (body != null) {
          await File("${payloadDir.path}/${c.name}-$format.json")
              .writeAsString(const JsonEncoder.withIndent("  ").convert(body));
        }
      }
    }
    _log("[$server] gateway got ${gateway.bodies.length} pushes");

    // Feed them as UnifiedPushNotifier.onMessage does: notePush, then the
    // background handler. All event_id_only pushes first, so the full
    // format's tweaks (remembered by event id) can't help them.
    final captured = <NotificationContent>[];
    NotificationManager.debugOnNotify = captured.add;
    addTearDown(() => NotificationManager.debugOnNotify = null);
    for (final format in _formats) {
      for (final c in cases) {
        final body = c.pushes[format];
        if (body == null) continue;
        final data = Map<String, dynamic>.from(body["notification"] as Map);
        captured.clear();
        MessageNotificationContent.notePush(data);
        await BackgroundNotificationsManager2(null).handleMessage(data);
        final shown = captured.whereType<MessageNotificationContent>();
        final others = captured.where((n) => n is! MessageNotificationContent);
        final detail = [
          for (final n in others) "${n.runtimeType}: ${n.title} ${n.content}",
          for (final n in shown)
            "dm=${n.isDirectMessage} ruleSound=${n.ruleSound} "
                "body=${n.content}",
        ].join("; ");
        c.outcomes[format] = _Outcome(
            shown.isNotEmpty,
            shown.any((n) => n.playsSound),
            shown.any((n) => n.playsMentionSound),
            detail);
      }
    }

    // The matrix: what the server sent and what the app made of it.
    final matrixRows = <Map<String, Object?>>[];
    for (final c in cases) {
      for (final format in _formats) {
        final body = c.pushes[format];
        final n = body?["notification"] as Map?;
        final device = (n?["devices"] as List?)?.first as Map?;
        final o = c.outcomes[format];
        final row = {
          "case": c.name,
          "format": format,
          "pushed": body != null,
          "type": n?["type"],
          "tweaks": device?["tweaks"],
          "prio": n?["prio"],
          "counts": n?["counts"],
          "outcome": o?.label ?? "-",
          "detail": o?.detail,
        };
        matrixRows.add(row);
        _log("[$server] ${jsonEncode(row)}");
      }
    }
    await File("${payloadDir.path}/matrix.json")
        .writeAsString(const JsonEncoder.withIndent("  ").convert(matrixRows));

    final failures = <String>[];
    void check(bool ok, String what) {
      if (!ok) failures.add(what);
    }

    _Case byName(String name) => cases.firstWhere((c) => c.name == name);
    for (final format in _formats) {
      _Outcome? o(String name) => byName(name).outcomes[format];
      String at(String name) =>
          "$name ($format): ${o(name)?.label ?? "no push"}";

      for (final name in [
        "dm",
        "group",
        "group3",
        "mention",
        "keyword",
        "thread",
        "e2ee-dm",
        "e2ee-mention"
      ]) {
        check(o(name)?.shown == true, "${at(name)}, expected shown");
      }
      check(o("dm")?.sound == true, "${at("dm")}, expected a sound");
      // Two members: .m.rule.room_one_to_one (sound) on both servers.
      check(o("group")?.sound == true, "${at("group")}, expected a sound");
      // Three members: .m.rule.message, notify without a sound.
      check(o("group3")?.sound == false && o("group3")?.highlight == false,
          "${at("group3")}, expected no sound, no highlight");
      check(o("mention")?.sound == true && o("mention")?.highlight == true,
          "${at("mention")}, expected sound + highlight");
      check(o("keyword")?.sound == true && o("keyword")?.highlight == true,
          "${at("keyword")}, expected sound + highlight");
      check(o("e2ee-dm")?.sound == true, "${at("e2ee-dm")}, expected a sound");
      // The server can't read it; the app's own rule check highlights it once
      // decrypted (Tuwunel too, since unknown condition kinds stopped
      // leaving the check undecided).
      check(
          o("e2ee-mention")?.sound == true &&
              o("e2ee-mention")?.highlight == true,
          "${at("e2ee-mention")}, expected sound + highlight");
      for (final name in ["muted", "reaction", "redaction"]) {
        final outcome = o(name);
        check(outcome == null || !outcome.shown || !outcome.sound,
            "${at(name)}, expected no push, not shown or silent");
      }
    }
    // Vommet issue 719: no tweaks must not mean a different outcome.
    for (final c in cases) {
      final a = c.outcomes["event_id_only"];
      final b = c.outcomes["full"];
      if (a != null && b != null) {
        check(a == b, "${c.name}: event_id_only ${a.label} != full ${b.label}");
      }
    }
    for (final f in failures) {
      _log("[$server] FAIL $f");
    }
    expect(failures, isEmpty);

    await app.clientManager.close();
  });
}
