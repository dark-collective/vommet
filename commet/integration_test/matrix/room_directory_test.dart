// Vommet: Explore rooms (#48) end to end against the test homeserver.
//
// User 2 publishes a public space (with a banner and one child room) and a
// public room through the API; user 1 opens Explore from the sidebar, filters,
// searches, expands the space, joins the room, and sees it become "Open".

import 'dart:convert';
import 'dart:io';

import 'package:commet/ui/molecules/space_selector.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

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

  /// Uploads a 1x1 PNG and returns its mxc url.
  Future<String> uploadPng() async {
    var request = await _http.openUrl(
        "POST", base.resolve("/_matrix/media/v3/upload?filename=banner.png"));
    request.headers.contentType = ContentType("image", "png");
    request.headers.add("Authorization", "Bearer $token");
    request.add(base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="));
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
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Explore rooms: browse, filter, expand, join',
      (WidgetTester tester) async {
    var tag = RandomUtils.getRandomString(6).toLowerCase();
    var spaceName = "Directory Space $tag";
    var roomName = "Directory Room $tag";
    var childName = "Directory Child $tag";

    var api = _Api(Uri.https(tester.homeserver));
    await api.login(tester.userTwoName, tester.userTwoPassword);
    var server = api.base.host;
    var banner = await api.uploadPng();

    var child = await api.createRoom({
      "preset": "public_chat",
      "name": childName,
    });
    var space = await api.createRoom({
      "preset": "public_chat",
      "visibility": "public",
      "name": spaceName,
      "topic": "A space for the directory test",
      "creation_content": {"type": "m.space"},
      "initial_state": [
        {
          "type": "m.room.history_visibility",
          "state_key": "",
          "content": {"history_visibility": "world_readable"}
        },
        {
          "type": "page.codeberg.everypizza.room.banner",
          "state_key": "",
          "content": {"url": banner}
        },
      ],
    });
    await api.call(
        "PUT",
        "/_matrix/client/v3/rooms/${Uri.encodeComponent(space)}/state/"
            "m.space.child/${Uri.encodeComponent(child)}",
        {
          "via": [server]
        });
    var room = await api.createRoom({
      "preset": "public_chat",
      "visibility": "public",
      "name": roomName,
      "topic": "A room for the directory test",
    });

    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    // Open Explore from the sidebar
    var button = _key("sidebar_discover_button");
    await tester.dragUntilVisible(
        button, find.byType(SpaceSelector), const Offset(0, -50));
    await tester.tap(button);
    await tester.waitFor(
        () => _key("directory_row_$room").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    expect(_key("directory_row_$space"), findsOneWidget);

    // Spaces only
    await tester.tap(find.text("Spaces"));
    await tester.waitFor(() => _key("directory_row_$room").evaluate().isEmpty);
    expect(_key("directory_row_$space"), findsOneWidget);

    // Expand the space: banner (world-readable, same server) + its rooms
    await tester.tap(_key("directory_row_header_$space"));
    await tester.waitFor(() => find.text(childName).evaluate().isNotEmpty);
    expect(_key("directory_banner_$space"), findsOneWidget);
    expect(find.text("A space for the directory test"), findsOneWidget);

    // Rooms only + search
    await tester.tap(find.text("Rooms"));
    await tester.enterText(_key("directory_search"), roomName);
    await tester.waitFor(() =>
        _key("directory_row_$room").evaluate().isNotEmpty &&
        _key("directory_row_$space").evaluate().isEmpty);

    // Join it: the page closes and the room is ours
    await tester.tap(_key("directory_join_$room"));
    var client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(room),
        timeout: const Duration(seconds: 20));
    await tester.waitFor(() => _key("directory_search").evaluate().isEmpty,
        timeout: const Duration(seconds: 20));

    // Opening Explore again shows it as joined
    await tester.dragUntilVisible(
        button, find.byType(SpaceSelector), const Offset(0, -50));
    await tester.tap(button);
    await tester.waitFor(
        () => _key("directory_open_$room").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    // let the page finish sliding in before tapping inside it
    await tester.pump(const Duration(seconds: 1));

    // A server that can't be reached gets its own warning
    await tester.tap(_key("directory_server_button"));
    await tester
        .waitFor(() => _key("directory_server_search").evaluate().isNotEmpty);
    await tester.enterText(
        _key("directory_server_search"), "nowhere-$tag.invalid");
    await tester.pumpAndSettle();
    await tester.tap(_key("directory_server_custom"));
    await tester.waitFor(
        () => _key("directory_problem_unreachable").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
  });
}
