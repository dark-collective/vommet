// Vommet: cross-platform smoke suite (#78).
//
// The same few checks on every platform (Linux, Android, Windows, ...). They
// exercise the native surface where platform-only bugs live (secure storage,
// the HTTP stack, the vodozemac crypto library, image processing), not app
// logic: that is covered once, by the Linux integration suite.
//
// User 1 is the app under test; user 2 is a plain HTTP client ("bob") that
// sends to the app and reads back what the app sent.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

/// Minimal client-server API client for the second actor.
class SmokeApi {
  SmokeApi(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;

  Future<Map<String, dynamic>> call(String method, String path,
      [Object? body]) async {
    var request = await _http.openUrl(method, base.resolve(path));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.add("Authorization", "Bearer $token");
    if (body != null) request.write(jsonEncode(body));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("$method $path -> ${response.statusCode} $text");
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> login(String user, String password) async {
    var result = await call("POST", "/_matrix/client/v3/login", {
      "type": "m.login.password",
      "identifier": {"type": "m.id.user", "user": user},
      "password": password,
    });
    token = result["access_token"] as String;
  }

  Future<String> userId() async =>
      (await call("GET", "/_matrix/client/v3/account/whoami"))["user_id"]
          as String;

  Future<void> sendText(String room, String body) => call(
      "PUT",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
          "m.room.message/smoke-${DateTime.now().microsecondsSinceEpoch}",
      {"msgtype": "m.text", "body": body});

  Future<void> join(String room) =>
      call("POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});

  /// The newest [limit] events of [room], newest first.
  Future<List<Map<String, dynamic>>> recent(String room,
      {int limit = 30}) async {
    var result = await call(
        "GET",
        "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/messages"
            "?dir=b&limit=$limit");
    return (result["chunk"] as List).cast<Map<String, dynamic>>();
  }

  /// Polls [room] until an event matches [test], or throws after [timeout].
  Future<Map<String, dynamic>> waitForEvent(
      String room, bool Function(Map<String, dynamic>) test,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      for (var e in await recent(room)) {
        if (test(e)) return e;
      }
      if (DateTime.now().isAfter(end)) {
        throw Exception("timed out waiting for an event in $room");
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}

/// A photo-sized PNG (1600x1200 gradient), so the send path does real
/// decode/thumbnail/blurhash work, like a picture from a phone would.
Future<Uint8List> _photoPng() async {
  const w = 1600.0, h = 1200.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..shader = ui.Gradient.linear(const ui.Offset(0, 0), const ui.Offset(w, h),
        [const ui.Color(0xFF3366CC), const ui.Color(0xFFCC6633)]);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, w, h), paint);
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void _log(String line) {
  // ignore: avoid_print
  print("SMOKE $line");
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke: log in, receive, send text, send image, send encrypted',
      (WidgetTester tester) async {
    final nonce = DateTime.now().millisecondsSinceEpoch.toString();
    final api = SmokeApi(Uri.https(tester.homeserver));
    await api.login(tester.userTwoName, tester.userTwoPassword);

    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    final Client client = app.clientManager.clients.first;
    _log("logged in as ${client.self?.identifier}");

    // Receive: bob creates a room, invites the app's user and says something
    // before the join ("early") and after it ("ping").
    final roomId = (await api.call("POST", "/_matrix/client/v3/createRoom", {
      "name": "smoke $nonce",
      "preset": "private_chat",
      "invite": [client.self!.identifier],
    }))["room_id"] as String;
    await api.sendText(roomId, "early $nonce");

    final Room room = await client.joinRoom(roomId);
    final timeline = await room.getTimeline();
    bool has(String body) =>
        timeline.events.any((e) => e is TimelineEventMessage && e.body == body);
    String summary() => timeline.events
        .take(8)
        .map((e) => e is TimelineEventMessage
            ? "${e.runtimeType}(${e.body})"
            : e.runtimeType.toString())
        .join(", ");

    // Live receive (hard requirement): a message arriving through sync.
    await api.sendText(roomId, "ping $nonce");
    try {
      await tester.waitFor(() => has("ping $nonce"),
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    } catch (_) {
      _log("live receive timed out; timeline has ${timeline.events.length} "
          "events: ${summary()}");
      rethrow;
    }
    _log("received text");

    // A message sent before the join (logged, not required): does the joined
    // room show it, and if not, does loading history bring it in?
    if (has("early $nonce")) {
      _log("pre-join message shown");
    } else {
      await timeline.loadMoreHistory();
      await Future.delayed(const Duration(seconds: 2));
      _log(has("early $nonce")
          ? "pre-join message shown only after loadMoreHistory"
          : "pre-join message NOT shown (events: ${summary()})");
    }

    // Send text: bob must see it.
    var sw = Stopwatch()..start();
    await room.sendMessage(message: "pong $nonce");
    await api.waitForEvent(
        roomId, (e) => (e["content"] as Map?)?["body"] == "pong $nonce");
    _log("sent text in ${sw.elapsedMilliseconds} ms");

    // Send an image: processing (decode, thumbnail, blurhash) + upload. A send
    // that hangs (the Windows ">1 min spinner" report) fails here.
    sw = Stopwatch()..start();
    final png = await _photoPng();
    final processed = await room.processAttachments([
      PendingFileAttachment(
          name: "smoke-$nonce.png",
          data: png,
          mimeType: "image/png",
          size: png.length)
    ]);
    _log("processed ${png.length} byte image in ${sw.elapsedMilliseconds} ms");
    await room.sendMessage(processedAttachments: processed);
    final image = await api.waitForEvent(
        roomId, (e) => (e["content"] as Map?)?["msgtype"] == "m.image",
        timeout: const Duration(seconds: 60));
    expect((image["content"] as Map)["url"], startsWith("mxc://"));
    _log("sent image in ${sw.elapsedMilliseconds} ms");

    // Encrypted: bob creates an E2EE room, the app joins and sends into it,
    // which runs the platform's build of the crypto library (Megolm session
    // creation + encryption). Bob is a plain HTTP client and can't decrypt;
    // he checks the app's event arrived as m.room.encrypted.
    final encRoomId = (await api.call("POST", "/_matrix/client/v3/createRoom", {
      "name": "smoke enc $nonce",
      "preset": "private_chat",
      "invite": [client.self!.identifier],
      "initial_state": [
        {
          "type": "m.room.encryption",
          "state_key": "",
          "content": {"algorithm": "m.megolm.v1.aes-sha2"}
        }
      ],
    }))["room_id"] as String;
    final encRoom = await client.joinRoom(encRoomId);
    await tester.waitFor(() => encRoom.isE2EE,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    sw = Stopwatch()..start();
    await encRoom.sendMessage(message: "secret $nonce");
    final enc = await api.waitForEvent(
        encRoomId,
        (e) =>
            e["type"] == "m.room.encrypted" &&
            e["sender"] == client.self!.identifier);
    expect((enc["content"] as Map)["algorithm"], "m.megolm.v1.aes-sha2");
    _log("sent encrypted in ${sw.elapsedMilliseconds} ms");
  });
}
