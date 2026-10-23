// Vommet: picture mosaics (#11) against the test homeserver.
//
// User 1 posts three pictures in a row through the API (body = filename, no
// caption, like any client); the app opens that room's timeline and the three
// must group into one mosaic: the oldest is the root, the other two children.
// Every check of the grouping rule is logged per event so a failure says why.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/molecules/timeline_events/media_group_member.dart';
import 'package:commet/utils/media_group.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:commet/ui/molecules/timeline_events/media_mosaic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

const _png =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

class _Api {
  _Api(this.base);
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

  Future<String> uploadPng(String name) async {
    var request = await _http.openUrl(
        "POST", base.resolve("/_matrix/media/v3/upload?filename=$name"));
    request.headers.contentType = ContentType("image", "png");
    request.headers.add("Authorization", "Bearer $token");
    request.add(base64Decode(_png));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("upload -> ${response.statusCode} $text");
    }
    return (jsonDecode(text) as Map<String, dynamic>)["content_uri"] as String;
  }

  Future<String> createRoom(Map<String, Object?> body) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", body))["room_id"]
          as String;

  Future<String> sendImage(String room, String name, int n) async {
    var url = await uploadPng(name);
    var txn = "mosaic-${DateTime.now().microsecondsSinceEpoch}-$n";
    return (await call(
        "PUT",
        "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
            "m.room.message/$txn",
        {
          "msgtype": "m.image",
          "body": name,
          "filename": name,
          "url": url,
          "info": {"mimetype": "image/png", "size": 70, "w": 1, "h": 1},
        }))["event_id"] as String;
  }
}

/// One line per event: every input of the grouping rule, so a failure log
/// shows which one keeps a picture out of the mosaic.
String _describe(int i, Timeline timeline, ThreadsComponent? threads) {
  final e = timeline.events[i];
  final parts = <String>[
    "[$i] ${e.runtimeType} ${e.eventId}",
    "sender=${e.senderId}",
    "ts=${e.originServerTs.toIso8601String()}",
    "status=${e.status}",
    "redacted=${timeline.isEventRedacted(e)}",
  ];
  if (e is TimelineEventMessage) {
    final a = e.attachments;
    parts.add("attachments=${a?.length}");
    if (a != null && a.isNotEmpty) {
      parts.add("type=${a.first.runtimeType} name=${jsonEncode(a.first.name)}");
    }
    parts.add("body=${jsonEncode(e.body)}");
  }
  if (e is TimelineEventFeatureRelated) {
    parts
        .add("relation=${(e as TimelineEventFeatureRelated).relationshipType}");
  }
  if (e is TimelineEventFeatureReactions) {
    parts.add(
        "reactions=${(e as TimelineEventFeatureReactions).hasReactions(timeline)}");
  }
  parts.add("thread=${threads?.isEventInResponseToThread(e, timeline)}");
  final member = mediaGroupMemberFor(e, timeline, threads: threads);
  parts.add("groupable=${member.groupable}");
  final pos = mediaGroupPositionAt(i, timeline, threads: threads);
  parts.add("role=${pos.role} root=${pos.rootIndex} members=${pos.members}");
  return parts.join(" ");
}

void _logTimeline(String label, Timeline timeline, ThreadsComponent? threads,
    List<String> sent) {
  // ignore: avoid_print
  print("MOSAIC $label timeline (index 0 = newest), sent=$sent");
  for (var i = 0; i < timeline.events.length && i < 12; i++) {
    // ignore: avoid_print
    print("MOSAIC $label ${_describe(i, timeline, threads)}");
  }
}

Future<void> _expectMosaicShown(
    WidgetTester tester, Client client, String roomId, String label) async {
  EventBus.doOpenRoom(roomId, clientId: client.identifier);
  try {
    await tester.waitFor(() => find.byType(MediaMosaic).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
  } catch (_) {
    // ignore: avoid_print
    print("MOSAIC $label UI: no MediaMosaic widget after opening the room");
    rethrow;
  }
  // ignore: avoid_print
  print("MOSAIC $label UI: MediaMosaic shown");

  // Let the open room settle (history paging, the composer's debounced
  // keyboard timer) before teardown closes the client, or their late
  // callbacks fail the next test.
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Picture mosaic: three pictures in a row group into one',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = await api.createRoom({
      "preset": "private_chat",
      "name": "Mosaic $tag",
    });
    var sent = <String>[];
    for (var n = 1; n <= 3; n++) {
      sent.add(await api.sendImage(roomId, "sheep_$n.png", n));
    }

    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    var room = client.getRoom(roomId)!;
    var timeline = await room.getTimeline();
    await tester.waitFor(
        () => sent.every((id) => timeline.events.any((e) => e.eventId == id)),
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);

    var threads = client.getComponent<ThreadsComponent>();
    _logTimeline("api", timeline, threads, sent);

    int indexOf(String id) =>
        timeline.events.indexWhere((e) => e.eventId == id);
    var oldest = indexOf(sent.first);
    var root = mediaGroupPositionAt(oldest, timeline, threads: threads);
    expect(root.role, MediaGroupRole.root,
        reason: "the oldest picture should be the mosaic's root");
    expect(root.members.map((i) => timeline.events[i].eventId).toList(), sent,
        reason: "all three pictures should be in the mosaic, oldest first");
    for (var id in sent.skip(1)) {
      expect(mediaGroupPositionAt(indexOf(id), timeline, threads: threads).role,
          MediaGroupRole.child);
    }
    expect(MediaGroups.maxSize, greaterThanOrEqualTo(3));
    expect(timeline.events[oldest] is TimelineEventMessage, isTrue);
    expect(
        (timeline.events[oldest] as TimelineEventMessage).attachments?.first
            is ImageAttachment,
        isTrue);

    await _expectMosaicShown(tester, client, roomId, "api");
  });

  // Like sending several pictures from the composer: the app's own
  // concurrent sends (local echoes first) in an encrypted room.
  testWidgets('Picture mosaic: three pictures sent by the app, encrypted room',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.username, tester.password);
    var roomId = await api.createRoom({
      "preset": "private_chat",
      "name": "Mosaic E2EE $tag",
      "initial_state": [
        {
          "type": "m.room.encryption",
          "state_key": "",
          "content": {"algorithm": "m.megolm.v1.aes-sha2"}
        }
      ],
    });

    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    var room = client.getRoom(roomId)!;
    var timeline = await room.getTimeline();
    var before = timeline.events.length;

    var processed = await room.processAttachments([
      for (var n = 1; n <= 3; n++)
        PendingFileAttachment(
            name: "sheep_$n.png",
            data: Uint8List.fromList(base64Decode(_png)),
            mimeType: "image/png"),
    ]);
    await room.sendMessage(processedAttachments: processed);

    await tester.waitFor(
        () =>
            timeline.events.length >= before + 3 &&
            timeline.events
                .take(3)
                .every((e) => e.status == TimelineEventStatus.synced),
        timeout: const Duration(seconds: 60),
        skipPumpAndSettle: true);

    var threads = client.getComponent<ThreadsComponent>();
    var sent = [for (var i = 2; i >= 0; i--) timeline.events[i].eventId];
    _logTimeline("app-e2ee", timeline, threads, sent);

    var root = mediaGroupPositionAt(2, timeline, threads: threads);
    expect(root.role, MediaGroupRole.root,
        reason: "the oldest of the three should be the mosaic's root");
    expect(root.members, [2, 1, 0]);

    await _expectMosaicShown(tester, client, roomId, "app-e2ee");
  });
}
